import Foundation
import Darwin
import AppKit

// MARK: - HookServer
// Listens on a Unix domain socket for events from the hook script (Claude Code hooks).
// Socket threads translate each hook into typed events and post them to the engine; they never
// touch the app state. Permission requests keep their socket open until a decision is made.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory paths (names live in AppIdentity)
    static var supportDir: URL { AppIdentity.supportDirectory }
    static var socketPath: String { AppIdentity.socketPath }
    static var hookScriptPath: String { AppIdentity.hookScriptPath }

    /// Seconds a permission request waits in the island before Claude Code asks in the terminal instead.
    /// Shorter than the 120 s Claude Code gives the hook.
    private static let approvalTimeout: TimeInterval = 115

    private var serverFD: Int32 = -1
    private var ingress: EventIngress?

    /// Hook scripts waiting for a decision, by request identifier. Socket threads add, the main actor removes.
    private let heldLock = NSLock()
    private var held: [String: HeldSocket] = [:]

    /// Permission requests waiting for the user, oldest first. The first one is on screen.
    @MainActor private var approvals: [PendingApproval] = []

    private struct PendingApproval {
        let requestID: String
        let sessionID: SessionID
        let info: ApprovalInfo
        /// Set for a request of the chat: the decision goes to this closure instead of a hook socket.
        var respond: (@MainActor (String) -> Void)?
        /// A request of Yumi's own agent runtime (Permissions/): its expiry belongs to the permission system.
        var isAgent = false
        /// Told when the request comes on screen: the permission system starts its time to answer then.
        var shown: (@MainActor () -> Void)?

        var isChat: Bool { respond != nil && !isAgent }
    }

    private init() {}

    // MARK: - Start

    /// - Parameter ingress: where the translated hook events go. Its engine must already have its subscribers.
    func start(ingress: EventIngress) {
        self.ingress = ingress
        #if !APPSTORE
        installHookScript()
        #endif
        Thread.detachNewThread { self.serverThread() }
    }

    // MARK: - Socket server (background thread)

    private func serverThread() {
        let path = Self.socketPath
        try? FileManager.default.createDirectory(at: Self.supportDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        guard Darwin.listen(fd, 10) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
        }
    }

    // MARK: - Client handler (background thread)

    private func handleClient(fd: Int32) {
        // Read newline-delimited JSON
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        // A session started by the chat is followed by the chat itself, through the output of its
        // process: its permission requests arrive there too. "ask" leaves that request undecided
        // here, so the answer given in the island goes back through the process.
        if let sessionID = payload["session_id"] as? String, ChatSessionRegistry.shared.contains(sessionID) {
            sendLine(fd: fd, text: eventName == "PermissionRequest" ? #"{"permissionDecision":"ask"}"# : #"{"ok":true}"#)
            close(fd)
            return
        }

        // What the session is working on, for the module's details. Read here, off the main thread:
        // a Stop reads the end of the session's transcript, on this Mac only.
        if let note = SessionNote.from(payload, lastMessage: { path in
            SessionText.readTail(path).flatMap(SessionText.lastAssistantText(transcript:))
        }) {
            Task { @MainActor in ClaudeSessionJournals.shared.apply(note) }
        }

        if eventName == "PermissionRequest" {
            // Hold fd open: Claude Code waits for our decision (up to 120s)
            let requestID = UUID().uuidString
            let events = ClaudeHookTranslator.events(for: payload, requestID: requestID)
            guard let ingress, !events.isEmpty else {
                // "ask" → the hook script outputs nothing → Claude Code asks in the terminal
                sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
                return
            }
            let socket = HeldSocket(fd: fd, acknowledges: ClaudeHookTranslator.protocolVersion(of: payload) >= 2)
            heldLock.withLock { held[requestID] = socket }
            ingress.post(events)
        } else {
            ingress?.post(ClaudeHookTranslator.events(for: payload))
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
    }

    // MARK: - Permission requests (blocking: Claude Code waits for the decision)

    /// Queues a permission request and shows it if nothing else is waiting.
    /// Called when the request comes out of the engine, once its session is known.
    @MainActor
    fileprivate func presentApproval(_ request: PermissionRequest, session sessionID: SessionID) {
        guard let socket = heldLock.withLock({ held[request.id] }) else { return }
        nbLog("PermissionRequest \(request.tool): \(request.command)")

        // One request at a time per session: an older one goes back to the terminal.
        for stale in approvals where stale.sessionID == sessionID {
            resolveApproval(stale.requestID, decision: "ask")
        }

        approvals.append(PendingApproval(
            requestID: request.id, sessionID: sessionID,
            info: ApprovalInfo(sessionId: sessionID.value, tool: request.tool, command: request.command, requestID: request.id)))

        // The script now knows the app is alive and waits for the user.
        if socket.acknowledges { socket.send(#"{"ack":true}"#) }

        let requestID = request.id
        // The script went away: answered in the terminal, or Claude Code stopped waiting.
        socket.watch { [weak self] in
            Task { @MainActor in self?.resolveApproval(requestID, decision: "ask") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.approvalTimeout) { [weak self] in
            // "ask" → the hook script outputs nothing → Claude Code re-asks rather than denying
            self?.resolveApproval(requestID, decision: "ask")
        }

        if approvals.count == 1 { showApproval(approvals[0]) }
    }

    /// Queues a permission request of the chat's own Claude Code session. It is shown and answered
    /// like any other; the decision ("allow", "always", "deny", or "ask" when nobody answered in
    /// time) is given to `respond`.
    @MainActor
    func presentChatApproval(id requestID: String, session: String, tool: String, command: String,
                             respond: @escaping @MainActor (String) -> Void) {
        nbLog("PermissionRequest (chat) \(tool): \(command)")
        approvals.append(PendingApproval(
            requestID: requestID, sessionID: SessionID(session),
            info: ApprovalInfo(sessionId: session, tool: tool, command: command, requestID: requestID),
            respond: respond))
        if approvals.count == 1 { showApproval(approvals[0]) }
    }

    /// Queues an approval of Yumi's own agent runtime. It is shown like the others; the answer
    /// ("allow", "always" for this session, "deny") goes to `respond`, and only from a click.
    /// The permission system expires it and withdraws it itself (`withdrawAgentApproval`), counting
    /// the time to answer from the moment it is on screen (`shown`), not while it queues.
    @MainActor
    func presentAgentApproval(_ approval: ApprovalRequest, shown: @escaping @MainActor () -> Void,
                              respond: @escaping @MainActor (String) -> Void) {
        nbLog("Approval (agent) \(approval.toolID), \(approval.items.count) action(s), risk \(approval.riskLevel.rawValue)")
        approvals.append(PendingApproval(
            requestID: approval.id.uuidString, sessionID: SessionID("yumi-agent"),
            info: ApprovalInfo(sessionId: "yumi-agent", tool: approval.toolName, command: approval.headline, agentRequest: approval,
                                requestID: approval.id.uuidString),
            respond: respond, isAgent: true, shown: shown))
        if approvals.count == 1 { showApproval(approvals[0]) }
    }

    /// Takes an agent approval off screen without answering it (expired, cancelled).
    @MainActor
    func withdrawAgentApproval(id: UUID) {
        guard let index = approvals.firstIndex(where: { $0.requestID == id.uuidString && $0.isAgent }) else { return }
        let approval = approvals.remove(at: index)
        guard index == 0 else { return }
        if let next = approvals.first {
            showApproval(next)
        } else {
            closeApprovalView(after: approval)
        }
    }

    /// Withdraws a chat request that no longer needs an answer (decided elsewhere, or its process ended).
    /// - Parameter backToChat: false when the conversation itself was dropped: the view is left as it is.
    @MainActor
    func cancelChatApproval(id requestID: String, backToChat: Bool = true) {
        guard let index = approvals.firstIndex(where: { $0.requestID == requestID && $0.isChat }) else { return }
        let approval = approvals.remove(at: index)
        guard index == 0 else { return }
        if let next = approvals.first {
            showApproval(next)
        } else {
            closeApprovalView(after: approval, backToChat: backToChat)
        }
    }

    /// Opens the island on a permission request. Approval always forces the island open: the user must be able to respond.
    @MainActor
    private func showApproval(_ approval: PendingApproval) {
        let state = AppState.shared
        if approval.isAgent {
            // Yumi itself asks: the character shows it. The time limit is the permission system's,
            // and starts now.
            state.stateOverride = .approval
            approval.shown?()
        } else if approval.isChat {
            // The chat is not one of the sessions of the pill: the character itself shows the request.
            state.stateOverride = .approval
            // Claude Code waits for the chat without limit. The time to answer is counted from the
            // moment the request is on screen, not while it queues behind another one.
            let requestID = approval.requestID
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.approvalTimeout) { [weak self] in
                self?.resolveApproval(requestID, decision: "ask")
            }
        } else {
            // A chat request withdrawn just before must not leave its mark on the character.
            if state.stateOverride == .approval { state.stateOverride = .thinking }
            state.updateTask(id: ClaudeTaskMirror.taskID, state: .approval)
            state.focusId = ClaudeTaskMirror.taskID
        }
        state.pendingApproval = approval.info
        state.isPinned = true
        SoundEngine.shared.play("approval")
        Self.expandIfNeeded(to: .approval)
    }

    /// Called by ApprovalView buttons. Writes the decision to the waiting hook script and cleans up.
    /// - Parameter requestID: the request the button was drawn for. When another one is now in
    ///   front, the click is dropped: an answer never goes to a request the person did not see.
    @MainActor
    func sendApprovalDecision(_ decision: String, for requestID: String? = nil) {
        guard let current = approvals.first else {
            closeApprovalView(after: nil)
            return
        }
        if let requestID, requestID != current.requestID {
            nbLog("Approval answer dropped: \(requestID) is no longer in front")
            return
        }
        resolveApproval(current.requestID, decision: decision)
    }

    /// Answers one request and moves on to the next. Does nothing if the request is already answered.
    @MainActor
    private func resolveApproval(_ requestID: String, decision: String) {
        guard let index = approvals.firstIndex(where: { $0.requestID == requestID }) else { return }
        let approval = approvals.remove(at: index)

        let json: String
        switch decision {
        case "allow":  json = #"{"permissionDecision":"allow"}"#
        case "always": json = #"{"permissionDecision":"always"}"#
        case "ask":    json = #"{"permissionDecision":"ask"}"#
        default:       json = #"{"permissionDecision":"deny"}"#
        }
        if let respond = approval.respond {
            respond(decision)
        } else {
            heldLock.withLock { held.removeValue(forKey: requestID) }?.finish(json)
            ingress?.post(.permissionResolved(approval.sessionID, requestID: requestID))
        }

        // Only the request on screen changes what the island shows.
        guard index == 0 else { return }
        if let next = approvals.first {
            showApproval(next)
        } else {
            closeApprovalView(after: approval)
        }
    }

    @MainActor
    private func closeApprovalView(after approval: PendingApproval?, backToChat: Bool = true) {
        let state = AppState.shared
        state.pendingApproval = nil
        state.isPinned = false
        if approval?.isAgent == true {
            // The agent's own events tell the character what comes next (AppDelegate).
            if state.stateOverride == .approval { state.stateOverride = nil }
            state.view = state.tasks.isEmpty ? .empty : .overview
            return
        }
        if approval?.isChat == true {
            // Back to the conversation the request interrupted. The chat sets the character's state.
            if state.stateOverride == .approval { state.stateOverride = backToChat ? .thinking : nil }
            if backToChat { state.view = .prompt }
            return
        }
        state.updateTask(id: ClaudeTaskMirror.taskID, state: .working)
        if let idx = state.tasks.firstIndex(where: { $0.id == ClaudeTaskMirror.taskID }) {
            state.tasks[idx].pillBadge = nil
        }
        state.view = state.tasks.isEmpty ? .empty : .overview
    }

    /// True while a permission request is on screen.
    @MainActor
    var hasPendingApproval: Bool { !approvals.isEmpty }

    // MARK: - Island helpers

    @MainActor
    fileprivate static func expandIfNeeded(to view: IslandView) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            // Only force-switch view for alerts, leave user on their current view otherwise
            if isAlert { state.view = view }
        } else if isAlert {
            // Alerts always force-expand
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            // Non-alert work events: reveal compact only, never force-expand
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        // Already compact and non-alert: the character state update is enough, no expand
    }

    // MARK: - Logging

    fileprivate func nbLog(_ message: String) {
        let logsDir = AppIdentity.logsDirectory
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let logFile = logsDir.appendingPathComponent(AppIdentity.hookLogFileName)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: logFile)
        }
    }

    private func sendLine(fd: Int32, text: String) {
        writeLine(text, to: fd)
    }

    // MARK: - Hook script installation

    /// The launcher at `url` (the path settings.json names) and the Python relay beside it.
    @discardableResult
    static func writeHook(at url: URL, throwing: Bool = false) throws -> Bool {
        let relay = url.deletingLastPathComponent().appendingPathComponent(HookLauncher.relayName)
        do {
            try hookScriptSource.write(to: relay, atomically: true, encoding: .utf8)
            try HookLauncher.script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: url.path)
            return true
        } catch {
            if throwing { throw error }
            return false
        }
    }

    func installHookScript() {
        #if APPSTORE
        // In App Store mode the script is written during settings hook installation
        // (requires a security-scoped bookmark to ~/.claude chosen by the user)
        #else
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try? Self.writeHook(at: URL(fileURLWithPath: Self.hookScriptPath))
        #endif
    }

    // MARK: - settings.json helpers

    /// Events registered in settings.json, with their timeout in seconds.
    private static let hookEvents: [(String, Int)] = [
        ("SessionStart", 10), ("SessionEnd", 10),
        ("UserPromptSubmit", 10),
        ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
        ("PermissionRequest", 120),
        ("Notification", 10),
        ("Stop", 10), ("StopFailure", 10),
        ("SubagentStart", 10), ("SubagentStop", 10),
    ]

    private static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Hook definitions of one settings.json matcher entry.
    private static func hookList(_ matcher: [String: Any]) -> [[String: Any]] {
        matcher["hooks"] as? [[String: Any]] ?? []
    }

    /// True if the matcher entry holds one of this app's hooks.
    private static func isOwnMatcher(_ matcher: [String: Any]) -> Bool {
        hookList(matcher).contains { hook in
            (hook["command"] as? String).map(AppIdentity.isOwnHookCommand) ?? false
        }
    }

    /// Removes the hooks whose command satisfies `shouldRemove` (see `HookSettings.strip`).
    private static func stripHooks(from matchers: inout [[String: Any]],
                                   where shouldRemove: (String) -> Bool) -> Int {
        HookSettings.strip(&matchers, where: shouldRemove)
    }

    /// The "hooks" dictionary of settings.json, or nil if the file is missing or unreadable.
    private static func installedHooks(at settingsURL: URL = defaultSettingsURL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return settings["hooks"] as? [String: Any]
    }

    // MARK: - Hook detection

    /// Returns true if settings.json has one of this app's hooks on SessionStart.
    static func hooksInstalled() -> Bool {
        guard let matchers = installedHooks()?["SessionStart"] as? [[String: Any]] else { return false }
        return matchers.contains(where: isOwnMatcher)
    }

    /// Returns true if settings.json has one of this app's PermissionRequest hooks with timeout < 120s.
    static func hooksNeedUpdate() -> Bool {
        guard let matchers = installedHooks()?["PermissionRequest"] as? [[String: Any]] else { return false }
        for matcher in matchers {
            for hook in hookList(matcher) {
                if let cmd = hook["command"] as? String,
                   AppIdentity.isOwnHookCommand(cmd),
                   let timeout = hook["timeout"] as? Int,
                   timeout < 120 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Claude Code settings.json hook installer

    private var _pendingHooksData: Data?

    /// Number of legacy hooks the last preview removes. Shown before the user confirms.
    private(set) var pendingLegacyHookCount = 0

    /// Returns preview JSON without writing — call writeClaudeHooks() to confirm.
    func previewClaudeHooks() throws -> String {
        let data = try buildHooksData(settingsURL: Self.defaultSettingsURL)
        _pendingHooksData = data
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes the hooks to disk (call after user confirms preview). An existing file is backed
    /// up first, and nothing is written if the backup fails.
    func writeClaudeHooks() throws {
        guard let data = _pendingHooksData else { return }
        try Self.backUpAndWrite(data, to: Self.defaultSettingsURL)
        _pendingHooksData = nil
    }

    /// Backup of the current file (if there is one), then the new content. Throws before writing
    /// anything when the backup cannot be made.
    static func backUpAndWrite(_ data: Data, to settingsURL: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: settingsURL.path) {
            let backup = HookSettings.backupURL(for: settingsURL, now: Date()) { manager.fileExists(atPath: $0.path) }
            try manager.copyItem(at: settingsURL, to: backup)
        }
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Merges this app's hooks into the settings.json at `settingsURL`, replacing any it already has
    /// and removing the legacy hooks of an earlier notch app from every event. A file that cannot be
    /// read as a JSON object is refused, never replaced.
    private func buildHooksData(settingsURL: URL) throws -> Data {
        let existing: Data?
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do { existing = try Data(contentsOf: settingsURL) } catch {
                throw HookSettingsReadError(path: settingsURL.path)
            }
        } else {
            existing = nil
        }
        let merged = try HookSettings.merge(existing, command: AppIdentity.hookCommand, events: Self.hookEvents,
                                            isOwn: AppIdentity.isOwnHookCommand, isLegacy: AppIdentity.isLegacyHookCommand)
        pendingLegacyHookCount = merged.legacyRemoved
        return merged.data
    }

    func uninstallClaudeHooks() throws {
        try removeHooks(settingsURL: Self.defaultSettingsURL)
    }

    /// Removes this app's hooks from the settings.json at `settingsURL`. Legacy hooks are left alone.
    private func removeHooks(settingsURL: URL) throws {
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                guard Self.stripHooks(from: &matchers, where: AppIdentity.isOwnHookCommand) > 0 else { continue }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
    }

    // MARK: - App Store: hooks via security-scoped bookmark

    #if APPSTORE
    /// App Store variant — needs a security-scoped bookmark URL pointing to ~/.claude
    func previewClaudeHooksAppStore(claudeURL: URL) throws -> String {
        let accessing = claudeURL.startAccessingSecurityScopedResource()
        defer { if accessing { claudeURL.stopAccessingSecurityScopedResource() } }
        let data = try buildHooksData(settingsURL: claudeURL.appendingPathComponent("settings.json"))
        _pendingHooksData = data
        return String(data: data, encoding: .utf8) ?? ""
    }

    func writeClaudeHooksAppStore(claudeURL: URL) throws {
        guard let data = _pendingHooksData else { return }
        let accessing = claudeURL.startAccessingSecurityScopedResource()
        defer { if accessing { claudeURL.stopAccessingSecurityScopedResource() } }

        // Write the hook script into ~/.claude
        let scriptURL = claudeURL.appendingPathComponent(AppIdentity.appStoreHookScriptRelativePath)
        try FileManager.default.createDirectory(at: scriptURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Self.writeHook(at: scriptURL, throwing: true)

        // Write settings.json, after a backup
        try Self.backUpAndWrite(data, to: claudeURL.appendingPathComponent("settings.json"))
        _pendingHooksData = nil
    }

    func uninstallClaudeHooksAppStore(claudeURL: URL) throws {
        let accessing = claudeURL.startAccessingSecurityScopedResource()
        defer { if accessing { claudeURL.stopAccessingSecurityScopedResource() } }
        try removeHooks(settingsURL: claudeURL.appendingPathComponent("settings.json"))
    }
    #endif
}

/// settings.json exists but cannot be read (permissions): nothing is written.
struct HookSettingsReadError: LocalizedError {
    var path: String
    var errorDescription: String? { loc("Je ne peux pas lire \((path as NSString).abbreviatingWithTildeInPath). Je n'y ai pas touché.") }
}

// MARK: - Socket helpers

private func writeLine(_ text: String, to fd: Int32) {
    let bytes = Array((text + "\n").utf8)
    bytes.withUnsafeBytes { buffer in
        var sent = 0
        while sent < buffer.count {
            let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
            if n <= 0 { break }
            sent += n
        }
    }
}

/// The socket of a hook script waiting for a permission decision.
/// Everything that touches the descriptor runs on one serial queue, so a reply, a hang-up and
/// the close can never overlap.
private final class HeldSocket: @unchecked Sendable {
    private static let queue = DispatchQueue(label: "\(AppIdentity.notificationPrefix).hook-replies")

    /// True when the script waits for an acknowledgement before it waits for the decision.
    let acknowledges: Bool
    private let fd: Int32
    private var watcher: DispatchSourceRead?
    private var closed = false

    init(fd: Int32, acknowledges: Bool) {
        self.fd = fd
        self.acknowledges = acknowledges
    }

    /// Writes a line and keeps the socket open.
    func send(_ line: String) {
        Self.queue.async {
            guard !self.closed else { return }
            writeLine(line, to: self.fd)
        }
    }

    /// Writes the last line and closes the socket.
    func finish(_ line: String) {
        Self.queue.async {
            guard !self.closed else { return }
            writeLine(line, to: self.fd)
            self.shut()
        }
    }

    /// Calls `onHangUp` once if the script closes its end before `finish`.
    func watch(onHangUp: @escaping @Sendable () -> Void) {
        Self.queue.async { [weak self] in
            guard let self, !self.closed, self.watcher == nil else { return }
            let fd = self.fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.queue)
            source.setEventHandler { [weak self] in
                guard let self, !self.closed else { return }
                var byte: UInt8 = 0
                let n = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
                if n > 0 {
                    // The script never writes twice; drop whatever this is so the source settles.
                    _ = recv(fd, &byte, 1, MSG_DONTWAIT)
                    return
                }
                if n < 0 && (errno == EAGAIN || errno == EINTR) { return }
                self.shut()
                onHangUp()
            }
            // The descriptor is closed by the cancel handler, once the source has let go of it.
            source.setCancelHandler { close(fd) }
            self.watcher = source
            source.resume()
        }
    }

    private func shut() {
        closed = true
        if let watcher {
            watcher.cancel()
            self.watcher = nil
        } else {
            close(fd)
        }
    }
}

// MARK: - Claude Code sessions → island
// Keeps the permanent Claude Code pill ("integration_claude") in step with the sessions, and plays
// the sounds and island reactions of each event. The pill shows one session at a time: the one
// waiting for the user, otherwise the most recently active.

@MainActor
final class ClaudeTaskMirror {
    static let taskID = "integration_claude"
    static let idleName = "Claude Code"

    private let state: AppState
    /// Sessions already announced (sound and reveal happen once per session).
    private var known: Set<SessionID> = []
    /// Last lines of each session's activity log.
    private var steps: [SessionID: [String]] = [:]
    /// Sessions that have just finished: they show "finished" for a moment, then go idle.
    private var celebrating: [SessionID: Int] = [:]
    private var celebrationCount = 0

    init(state: AppState) {
        self.state = state
    }

    private var focused: Bool { state.focusId == Self.taskID }

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        // Every coding agent that speaks through hooks: Claude Code, Codex, Gemini CLI…
        if let id = event.sessionID, let session = sessions[id], session.agent.kind != .coding { return }

        var approval: (PermissionRequest, SessionID)?

        switch event {
        case .sessionStarted(let id, _, let title):
            guard known.insert(id).inserted else { break }
            HookServer.shared.nbLog("SessionStart \(title) (\(id.value.prefix(8)))")
            if state.isPresent { HookServer.expandIfNeeded(to: .overview) }
            SoundEngine.shared.play("work")

        case .promptSubmitted(let id, let text):
            celebrating[id] = nil
            if !text.isEmpty { append(String(text.prefix(60)), to: id) }
            if state.isPresent { HookServer.expandIfNeeded(to: .overview) }

        case .toolStarted(let id, let tool):
            celebrating[id] = nil
            let step = ClaudeToolPhrase.step(tool)
            append(step, to: id)
            HookServer.shared.nbLog("PreToolUse \(step)")

        case .activityNoted(let id, let line):
            append(line, to: id)

        case .rateLimited:
            SoundEngine.shared.play("rate")

        case .questionRequested(let id, let question):
            append(question.text, to: id)

        case .taskCompleted(let id):
            SoundEngine.shared.play("finish")
            celebrate(id)
            if focused {
                HookServer.expandIfNeeded(to: .finished)
            } else {
                setBadge(.finished)
            }

        case .sessionErrored:
            SoundEngine.shared.play("error")
            if focused {
                HookServer.expandIfNeeded(to: .error)
            } else {
                setBadge(.error)
            }

        case .sessionEnded(let id):
            known.remove(id)
            steps[id] = nil
            celebrating[id] = nil

        case .permissionRequested(let id, let request):
            approval = (request, id)

        case .agentRegistered, .sessionLocated, .toolFinished, .permissionResolved:
            break
        }

        refresh(sessions)
        if let (request, id) = approval {
            HookServer.shared.presentApproval(request, session: id)
        }
    }

    // MARK: Pill

    /// Rewrites the pill from the session to show. Touches `AppState` only when something changed.
    private func refresh(_ sessions: [SessionID: Session]) {
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.taskID }) else { return }
        var task = state.tasks[idx]
        let featured = ClaudeSessions.ordered(sessions).first
        Self.featuredOrigin = featured?.origin
        Self.origins = sessions.compactMapValues(\.origin)
        if let session = featured {
            task.name = ClaudeSessions.projectName(session)
            task.agentName = session.agent.name
            task.speaker = AgentCatalog.speaker(of: session.agent)
            if let cwd = session.origin?.workingDirectory, !cwd.isEmpty { task.sessionCwd = cwd }
            task.steps = steps[session.id] ?? []
            task.stepIndex = max(0, task.steps.count - 1)
            task.state = botState(for: session)
        } else {
            // No session left: back to the resting pill.
            task.name = Self.idleName
            task.steps = []
            task.stepIndex = 0
            task.state = .idle
            task.pillBadge = nil
        }
        if task != state.tasks[idx] { state.tasks[idx] = task }
        lastSessions = sessions
    }

    private var lastSessions: [SessionID: Session] = [:]

    private func botState(for session: Session) -> BotState {
        switch session.activity {
        case .requestingPermission: return .approval
        case .asking:               return .question
        case .thinking:             return .thinking
        case .working:              return .working
        case .idle:
            switch session.status {
            case .rateLimited:    return .ratelimit
            case .errored:        return .error
            case .completed:      return celebrating[session.id] != nil ? .finished : .idle
            case .waitingForUser: return .question
            case .running:        return session.isTurnActive ? .working : .idle
            }
        }
    }

    private func append(_ step: String, to id: SessionID) {
        var log = steps[id] ?? []
        log.append(step)
        if log.count > 20 { log.removeFirst() }
        steps[id] = log
    }

    /// Shows "finished" for 5.2 s, unless the session starts working again before that.
    private func celebrate(_ id: SessionID) {
        celebrationCount += 1
        let token = celebrationCount
        celebrating[id] = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [weak self] in
            guard let self, self.celebrating[id] == token else { return }
            self.celebrating[id] = nil
            self.setBadge(nil)
            self.refresh(self.lastSessions)
        }
    }

    private func setBadge(_ badge: PillBadge?) {
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.taskID }),
              state.tasks[idx].pillBadge != badge else { return }
        state.tasks[idx].pillBadge = badge
    }

    /// Where the session shown by the pill runs.
    private static var featuredOrigin: SessionOrigin?
    /// Where each session runs, for the cards that answer one of them (an approval).
    private static var origins: [SessionID: SessionOrigin] = [:]

    /// The button that brings forward the application a session runs in, or nil when it is unknown.
    static func openLabel(session id: String) -> String? {
        SessionHost.openLabel(for: origins[SessionID(id)])
    }

    /// Brings forward the application, and the tab when the terminal can say, of one session.
    @discardableResult
    static func openSession(_ id: String) -> Bool {
        ClaudeCodeModule.bringToFront(origins[SessionID(id)])
    }

    /// Brings forward the application the session of the pill runs in: its terminal, its editor
    /// (on the project), or the Claude app. Never another one. Returns false when it is unknown.
    @discardableResult
    static func openSession() -> Bool {
        ClaudeCodeModule.bringToFront(featuredOrigin)
    }

    /// Opens the island on the Claude Code sessions: on the pending approval if there is one.
    func show() {
        state.setFocus(Self.taskID)
        NotificationCenter.default.post(name: .hookExpand,
                                        object: HookServer.shared.hasPendingApproval ? IslandView.approval : IslandView.overview)
    }
}

// MARK: - Notification names for hook server → controller communication

extension Notification.Name {
    static let hookExpand = AppIdentity.notification("hookExpand")
}

// MARK: - Hook script (Python)
// One template for both builds: only the header and the socket path differ.

extension HookServer {
    static var hookScriptSource: String {
        #if APPSTORE
        let variant = " (App Store)"
        let summary = "Socket lives inside the sandboxed container; script runs outside the sandbox."
        #else
        let variant = ""
        let summary = "Reads JSON from stdin, forwards to \(AppIdentity.productName) via Unix socket, translates response."
        #endif
        return hookScriptTemplate(
            header: "\(AppIdentity.hookScriptName): \(AppIdentity.productName)\(variant) hook relay for Claude Code",
            summary: summary,
            socketPath: AppIdentity.hookScriptSocketPath
        )
    }
}

private func hookScriptTemplate(header: String, summary: String, socketPath: String) -> String {
"""
#!/usr/bin/env python3
# \(header)
# \(summary)
import sys, json, os, socket, subprocess

def ancestors():
    # The command lines of the processes above the hook, nearest first: the app tells from
    # them which agent is at work (Claude Code, Codex, Gemini CLI...). One ps for all of them.
    try:
        out = subprocess.run(['/bin/ps', '-A', '-o', 'pid=,ppid=,args='],
                             capture_output=True, text=True, timeout=0.5).stdout
        table = {}
        for line in out.splitlines():
            parts = line.split(None, 2)
            if len(parts) >= 2:
                table[parts[0]] = (parts[1], parts[2][:200] if len(parts) > 2 else '')
        found = []
        pid = str(os.getppid())
        for _ in range(8):
            if pid not in table or pid in ('0', '1'):
                break
            parent, args = table[pid]
            found.append(args)
            pid = parent
        return found
    except Exception:
        return []

def find_tty():
    # The hook runs without a terminal; the claude process above it holds the one of its tab.
    try:
        pid = os.getppid()
        for _ in range(4):
            out = subprocess.run(['/bin/ps', '-o', 'ppid=,tty=', '-p', str(pid)],
                                 capture_output=True, text=True, timeout=0.3).stdout.split()
            if len(out) < 2:
                return ''
            if out[1] not in ('??', '-'):
                return '/dev/' + out[1]
            pid = int(out[0])
            if pid <= 1:
                return ''
    except Exception:
        pass
    return ''

def main():
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            return
        payload = json.loads(raw)
    except Exception:
        return

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    payload.setdefault('yumi_processes', ancestors())
    if 'tty' not in payload:
        payload['tty'] = find_tty()
    if 'cwd' not in payload or not payload['cwd']:
        payload['cwd'] = os.getcwd()

    event = payload.get('hook_event_name', '')
    socket_path = os.path.expanduser(
        '\(socketPath)'
    )

    if event == 'PermissionRequest':
        # Wait for \(AppIdentity.productName)'s decision (Claude Code allows up to 120s), but only if the app shows it is alive:
        # it must acknowledge the request within 2 seconds, or Claude Code asks in the terminal as usual.
        payload['hook_protocol'] = 2
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(2)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            pending = b''

            def read_line():
                nonlocal pending
                while b'\\n' not in pending:
                    chunk = s.recv(4096)
                    if not chunk:
                        line, pending = pending, b''
                        return line
                    pending += chunk
                line, pending = pending.split(b'\\n', 1)
                return line

            def parse(line):
                try:
                    obj = json.loads(line.decode().strip())
                    return obj if isinstance(obj, dict) else {}
                except Exception:
                    return {}

            resp_obj = parse(read_line())
            if resp_obj.get('ack'):
                s.settimeout(118)
                resp_obj = parse(read_line())
            s.close()
            decision = resp_obj.get('permissionDecision', '')
            if decision == 'allow':
                out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                sys.stdout.write(json.dumps(out) + '\\n')
                sys.stdout.flush()
                sys.exit(0)
            elif decision == 'always':
                # Let Claude Code persist the rule via updatedPermissions
                suggestions = payload.get('permission_suggestions', [])
                out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                sys.stdout.write(json.dumps(out) + '\\n')
                sys.stdout.flush()
                sys.exit(0)
            elif decision == 'deny':
                out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': '\(AppIdentity.denyMessage)'}}}
                sys.stdout.write(json.dumps(out) + '\\n')
                sys.stdout.flush()
                sys.exit(0)
            # 'ask' or unknown: fall through → no output → Claude Code re-asks
        except Exception:
            pass
        # App unreachable, silent, timed out, or no explicit decision: print nothing
        # Claude Code will handle the absence of output (re-ask or default behaviour)
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly, never block Claude Code

main()
sys.exit(0)
"""
}
