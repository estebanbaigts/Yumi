import AppKit

/// Reads the Claude Code sessions out of the store: which one to show first, and how to say what it does.
enum ClaudeSessions {
    /// Claude Code sessions, the one to show first. A session waiting for the user comes
    /// before the others; then the most recently active.
    static func ordered(_ sessions: [SessionID: Session]) -> [Session] {
        sessions.values
            .filter { $0.agent.kind == .coding }
            .sorted { a, b in
                let waitingA = a.status == .waitingForUser, waitingB = b.status == .waitingForUser
                if waitingA != waitingB { return waitingA }
                if a.recency != b.recency { return a.recency > b.recency }
                return a.id.value < b.id.value
            }
    }

    /// The folder the session works in gives it its name; it can change during the session.
    static func projectName(_ session: Session) -> String {
        guard let directory = session.origin?.workingDirectory, !directory.isEmpty else { return session.title }
        return ClaudeHookTranslator.projectName(forDirectory: directory)
    }

    /// What the session is doing, said by Yumi, who watches over the shoulder.
    static func phrase(_ session: Session) -> String {
        let project = projectName(session)
        let agent = AgentCatalog.speaker(of: session.agent)
        switch session.activity {
        case .requestingPermission: return loc("\(agent) veut ton accord sur \(project). Je laisse passer ?")
        case .asking:               return loc("\(agent) a une question pour toi sur \(project).")
        case .working(let tool):    return loc("\(agent) \(ClaudeToolPhrase.sentence(tool)) sur \(project).")
        case .thinking:             return loc("\(agent) réfléchit sur \(project).")
        case .idle:
            switch session.status {
            case .rateLimited:    return loc("\(agent) a atteint sa limite sur \(project). On attend.")
            case .errored:        return loc("Ça a planté sur \(project). Tu veux voir où ?")
            case .completed:      return loc("C'est passé sur \(project).")
            case .waitingForUser: return loc("\(agent) t'attend sur \(project).")
            case .running:        return session.isTurnActive ? loc("\(agent) avance sur \(project). Je surveille.")
                                                              : loc("\(agent) attend ton message sur \(project).")
            }
        }
    }

    /// - Parameter hooksMissing: Claude Code is installed, Yumi's hooks are not: no session can
    ///   reach Yumi, and the module says so with a button to install them.
    /// Above what is only good to know (the next event), below what the person started (music).
    static let workingPriority = ModuleLivePriority.ambient + 20

    static func snapshot(_ sessions: [Session], hooksMissing: Bool = false, journals: [String: SessionJournal] = [:]) -> ModuleSnapshot {
        var snapshot = plainSnapshot(sessions)
        if let live = live(sessions, journals: journals) { snapshot.live = live }
        if hooksMissing && sessions.isEmpty {
            snapshot.status = loc("à brancher")
            snapshot.title = loc("Je ne vois pas tes sessions Claude Code.")
            snapshot.subtitle = loc("Il me manque mes hooks. Je m'installe ?")
            snapshot.primaryAction = loc("Installer")
            snapshot.secondaryAction = nil
        }
        snapshot = snapshot.withSymbols("terminal.fill")
        // "Ouvrir iTerm2" is a terminal all the same: its button draws one.
        if snapshot.secondaryAction != nil, let symbol = SessionHost.symbol(for: sessions.first?.origin) {
            snapshot.secondarySymbol = symbol
        }
        return snapshot
    }

    private static func plainSnapshot(_ sessions: [Session]) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "claude-code", name: loc("Agents"), colorHex: "#FFB547",
                                      status: loc("au repos"), title: loc("Personne ne code en ce moment."),
                                      subtitle: loc("Lance Claude Code, Codex ou Gemini, je regarderai."),
                                      primaryAction: loc("Voir"), secondaryAction: nil)
        guard let featured = sessions.first else { return snapshot }
        // The agent at work gives the module its name; several different ones, "Agents".
        let agents = Set(sessions.map(\.agent.id))
        if agents.count == 1 { snapshot.name = featured.agent.name }

        let waiting = sessions.filter { $0.status == .waitingForUser }.count
        snapshot.status = FrenchText.count(sessions.count, "session", "sessions")
        snapshot.title = phrase(featured)
        snapshot.subtitle = FrenchText.sentenceStart(FrenchText.spelledCount(sessions.count, loc("session ouverte"), loc("sessions ouvertes"), feminine: true))
        if waiting == 1 { snapshot.subtitle += loc(", une t'attend") }
        if waiting > 1 { snapshot.subtitle += loc(", \(FrenchText.spelled(waiting)) t'attendent") }
        snapshot.subtitle += "."
        snapshot.secondaryAction = SessionHost.openLabel(for: featured.origin)
        snapshot.needsAttention = waiting > 0
        snapshot.live = live(sessions)
        return snapshot
    }

    /// The folded island hears about Claude Code when a session is waiting for the user, and
    /// when several sessions run: how many, and the one waiting first.
    /// `sessions` is ordered: a waiting session, if any, is the first one.
    /// With a journal, a working session says what it is on: "yumi · Modifie IslandModel.swift".
    static func live(_ sessions: [Session], journals: [String: SessionJournal] = [:]) -> ModuleLive? {
        let open = sessions.filter { $0.status != .completed }.count
        let count = open > 1 ? FrenchText.count(open, "session", "sessions") : nil
        guard let session = sessions.first, session.status == .waitingForUser else {
            if let working = sessions.first(where: { $0.status == .running && $0.isTurnActive }),
               let journal = journals[working.id.value],
               let what = journal.current?.sentence ?? journal.currentTask {
                let progress = journal.progress.map { " \($0)" } ?? ""
                return ModuleLive(text: "\(projectName(working))\(progress) · \(what)", priority: Self.workingPriority,
                                  controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: loc("Voir"))])
            }
            guard let count else { return nil }
            return ModuleLive(text: count, priority: ModuleLivePriority.ambient,
                              controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: loc("Voir"))])
        }
        let name = projectName(session)
        let approval: Bool
        if case .requestingPermission = session.activity { approval = true } else { approval = false }
        let text: String
        if let count {
            text = approval ? loc("\(count) · accord sur \(name)") : loc("\(count) · \(name) t'attend")
        } else {
            let agent = AgentCatalog.speaker(of: session.agent)
            text = approval ? loc("\(agent) veut ton accord sur \(name)") : loc("\(agent) t'attend sur \(name)")
        }
        return ModuleLive(text: text, priority: ModuleLivePriority.attention,
                          controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "eye.fill", label: loc("Voir"))])
    }
}

/// The application a session runs in: a terminal, or an editor with an integrated terminal.
enum SessionHost {
    /// `TERM_PROGRAM` values of the hosts that do not always pass their bundle identifier along.
    private static let knownPrograms: [String: String] = [
        "apple_terminal": "com.apple.Terminal",
        "iterm.app":      "com.googlecode.iterm2",
        "vscode":         "com.microsoft.VSCode",
        "ghostty":        "com.mitchellh.ghostty",
        "wezterm":        "com.github.wez.wezterm",
        "warpterminal":   "dev.warp.Warp-Stable",
        "kitty":          "net.kovidgoyal.kitty",
        "alacritty":      "org.alacritty",
        "zed":            "dev.zed.Zed",
        "hyper":          "co.zeit.hyper",
        "tabby":          "org.tabby",
    ]

    /// Bundle identifiers that open a folder as a project rather than as a shell.
    private static let editorMarkers = ["vscode", "vscodium", "cursor", "windsurf", "dev.zed", "jetbrains", "xcode"]

    /// Code editors whose bundle identifier does not say what they are.
    static let knownEditors = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium",
                               "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed"]

    enum Kind: Equatable, Sendable {
        /// A terminal emulator: bringing it forward shows the session.
        case terminal
        /// An editor with an integrated terminal: reopening the folder focuses the right window.
        case editor
        /// Another application that hosts sessions (the Claude desktop app, for instance).
        case other
    }

    static func bundleID(for origin: SessionOrigin?) -> String? {
        guard let origin else { return nil }
        if !origin.hostBundleID.isEmpty { return origin.hostBundleID }
        return knownPrograms[origin.hostName.lowercased()]
    }

    static func isEditor(_ origin: SessionOrigin?) -> Bool {
        guard let id = bundleID(for: origin) else { return false }
        return knownEditors.contains(id) || editorMarkers.contains { id.lowercased().contains($0) }
    }

    /// Names of the hosts, by bundle identifier, for the button that opens them.
    private static let names: [String: String] = [
        "com.apple.Terminal": "Terminal", "com.googlecode.iterm2": "iTerm2",
        "com.mitchellh.ghostty": "Ghostty", "com.github.wez.wezterm": "WezTerm",
        "dev.warp.Warp-Stable": "Warp", "net.kovidgoyal.kitty": "kitty", "org.alacritty": "Alacritty",
        "co.zeit.hyper": "Hyper", "org.tabby": "Tabby",
        "com.microsoft.VSCode": "VS Code", "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.vscodium.codium": "VSCodium", "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf", "dev.zed.Zed": "Zed",
        "com.anthropic.claudefordesktop": "Claude",
    ]

    /// The name of the application the session runs in: "iTerm2", "Ghostty". Nil when it is unknown.
    static func appName(for origin: SessionOrigin?) -> String? {
        guard let id = bundleID(for: origin) else { return nil }
        if let name = names[id] { return name }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// The button that brings the session forward, named after the application it opens:
    /// "Ouvrir iTerm2", never a terminal the session is not in. Nil when the host is unknown.
    static func openLabel(for origin: SessionOrigin?) -> String? {
        guard let kind = kind(of: origin) else { return nil }
        if let name = appName(for: origin) { return loc("Ouvrir \(name)") }
        switch kind {
        case .editor:   return loc("Ouvrir l'éditeur")
        case .terminal: return loc("Ouvrir le terminal")
        case .other:    return loc("Ouvrir la session")
        }
    }

    /// The symbol of that button: a terminal, an editor, or nil for the generic one.
    static func symbol(for origin: SessionOrigin?) -> String? {
        switch kind(of: origin) {
        case .terminal: return "terminal.fill"
        case .editor:   return "curlybraces"
        default:        return nil
        }
    }

    /// What kind of application hosts the session, or nil when it is unknown.
    static func kind(of origin: SessionOrigin?) -> Kind? {
        guard let origin, let id = bundleID(for: origin) else { return nil }
        if isEditor(origin) { return .editor }
        // Only terminals set TERM_PROGRAM; the known ones are also recognised by their identifier.
        if !origin.hostName.isEmpty || knownPrograms.values.contains(id) { return .terminal }
        return .other
    }
}

// MARK: - The list of sessions

/// Every session of the module's list, with since when each one is in its state. A finished
/// session (its answer done, or the session closed) stays a moment with its result, then leaves.
struct SessionBoard: Equatable, Sendable {
    /// How long a finished session stays in the list.
    static let keepFinished: TimeInterval = 90

    private struct Seen: Equatable, Sendable {
        var session: Session
        /// What the session is doing, in words: when it changes, the clock starts again.
        var phase: String
        var since: Date
        /// The session closed: it is no longer in the store.
        var closed = false
    }

    private var seen: [SessionID: Seen] = [:]
    /// Finished sessions already gone from the list, with the phase they left in: they come
    /// back only when they start something else.
    private var departed: [SessionID: String] = [:]

    init() {}

    /// Takes the sessions of the store as they are now. A session missing from them was closed.
    mutating func update(_ sessions: [Session], now: Date = .now) {
        let present = Set(sessions.map(\.id))
        for (id, entry) in seen where !present.contains(id) && !entry.closed {
            seen[id]?.closed = true
            seen[id]?.since = now
        }
        departed = departed.filter { present.contains($0.key) }
        for session in sessions {
            let phase = Self.phase(session)
            if departed[session.id] == phase { continue }
            departed[session.id] = nil
            if let old = seen[session.id], !old.closed, old.phase == phase {
                seen[session.id]?.session = session
            } else {
                seen[session.id] = Seen(session: session, phase: phase, since: now)
            }
        }
        for (id, entry) in seen where Self.expired(entry, now: now) {
            seen[id] = nil
            if !entry.closed { departed[id] = entry.phase }
        }
    }

    /// The sessions to list, the ones waiting for something first.
    /// - Parameter journals: what each session is working on (ClaudeSessionJournals), by session id.
    func rows(now: Date = .now, journals: [String: SessionJournal] = [:]) -> [ModuleRow] {
        seen.values
            .filter { !Self.expired($0, now: now) }
            .sorted { a, b in
                let rankA = Self.rank(a), rankB = Self.rank(b)
                if rankA != rankB { return rankA < rankB }
                if a.session.recency != b.session.recency { return a.session.recency > b.session.recency }
                return a.session.id.value < b.session.id.value
            }
            .map { Self.enriched(Self.row($0), journals[$0.session.id.value], now: now) }
    }

    /// The row with what the journal knows: the action or the task in progress instead of
    /// "travaille", the progress of the todo list, the summary of a finished turn, the details.
    static func enriched(_ row: ModuleRow, _ journal: SessionJournal?, now: Date) -> ModuleRow {
        guard let journal else { return row }
        var row = row
        row.progress = journal.progress
        row.details = journal.details(now: now)
        switch row.state {
        case .busy:
            if let step = journal.current { row.detail = step.sentence }
            else if let task = journal.currentTask { row.detail = task }
        case .success:
            if let summary = journal.summary { row.detail = summary }
        default:
            break
        }
        return row
    }

    /// When the next finished session leaves the list, to refresh it then.
    func nextDeparture(now: Date = .now) -> Date? {
        seen.values.filter { Self.finished($0) }.map { $0.since.addingTimeInterval(Self.keepFinished) }
            .filter { $0 > now }.min()
    }

    /// The session of a row's action, for the button.
    func session(_ action: String) -> Session? {
        seen[SessionID(action)]?.session
    }

    private static func finished(_ entry: Seen) -> Bool {
        entry.closed || entry.session.status == .completed
    }

    private static func expired(_ entry: Seen, now: Date) -> Bool {
        finished(entry) && now.timeIntervalSince(entry.since) >= keepFinished
    }

    private static func phase(_ session: Session) -> String {
        switch session.activity {
        case .requestingPermission: return "approval"
        case .asking:               return "question"
        case .working(let tool):    return "tool:\(tool.name):\(tool.summary)"
        case .thinking:             return "thinking"
        case .idle:                 return "idle:\(session.status):\(session.isTurnActive)"
        }
    }

    /// Approval, question, working, error, open, finished.
    private static func rank(_ entry: Seen) -> Int {
        if entry.closed { return 5 }
        let session = entry.session
        switch session.activity {
        case .requestingPermission: return 0
        case .asking:               return 1
        case .working, .thinking:   return 2
        case .idle:
            switch session.status {
            case .waitingForUser: return 1
            case .running:        return session.isTurnActive ? 2 : 4
            case .errored, .rateLimited: return 3
            case .completed:      return 5
            }
        }
    }

    private static func row(_ entry: Seen) -> ModuleRow {
        let session = entry.session
        var row = ModuleRow(id: session.id.value, title: ClaudeSessions.projectName(session), detail: "",
                            state: .neutral, label: "", date: entry.since,
                            action: SessionHost.kind(of: session.origin) == nil ? nil : session.id.value)
        row.actionLabel = SessionHost.openLabel(for: session.origin)
        if entry.closed {
            row.state = .success
            row.label = loc("terminée")
            row.detail = loc("Session fermée.")
            return row
        }
        switch session.activity {
        case .requestingPermission(let request):
            row.state = .waiting
            row.label = loc("attend un accord")
            row.detail = request.command.isEmpty ? loc("Demande \(request.tool).") : loc("Demande \(request.tool) : \(request.command)")
        case .asking(let question):
            row.state = .waiting
            row.label = loc("attend ta réponse")
            row.detail = question.text.isEmpty ? loc("A une question pour toi.") : question.text
        case .working(let tool):
            row.state = .busy
            row.label = loc("travaille")
            row.detail = FrenchText.sentenceStart(ClaudeToolPhrase.sentence(tool))
        case .thinking:
            row.state = .busy
            row.label = loc("travaille")
            row.detail = loc("Réfléchit.")
        case .idle:
            switch session.status {
            case .waitingForUser:
                row.state = .waiting
                row.label = loc("attend ta réponse")
                row.detail = loc("T'attend.")
            case .running:
                row.state = session.isTurnActive ? .busy : .neutral
                row.label = session.isTurnActive ? loc("travaille") : loc("ouverte")
                row.detail = session.isTurnActive ? loc("Avance.") : loc("Attend ton message.")
            case .errored:
                row.state = .failure
                row.label = loc("en erreur")
                row.detail = loc("Ça a planté.")
            case .rateLimited:
                row.state = .failure
                row.label = loc("limite atteinte")
                row.detail = loc("A atteint sa limite.")
            case .completed:
                row.state = .success
                row.label = loc("terminée")
                row.detail = loc("C'est passé.")
            }
        }
        return row
    }
}
