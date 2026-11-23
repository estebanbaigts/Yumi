import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?
    private var core: YumiCore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when the hook script closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any module or view touches it.
        // While filming (YUMI_STUDIO) the store stays empty and never touches the Keychain.
        _ = KeychainStore.shared
        // The keys of the old integrations go, once (they are no longer in Yumi).
        KeychainStore.shared.eraseRetiredKeys()
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Quitting (Contracts/AppLifecycle.swift)

    private var quit = QuitSequence()
    private var quitObservers: [NSObjectProtocol] = []

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // macOS says why with the quit request when the session is ending: log out, restart, shut down.
        let reason = NSAppleEventManager.shared().currentAppleEvent?
            .attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))
        let code = reason.map { $0.enumCodeValue != 0 ? $0.enumCodeValue : $0.typeCodeValue }
        guard quit.request(systemReason: code) == .sayGoodbye else { return .terminateNow }

        // The end is cancelled rather than suspended, so the island animates on a normal run loop;
        // the app is ended for good when the island is done, or after a few seconds whatever happens.
        quitObservers.append(NotificationCenter.default.addObserver(
            forName: .yumiQuitReady, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAfterGoodbye() }
        })
        // The Mac is turning off or the session is closing while Yumi says goodbye: no more waiting.
        quitObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAfterGoodbye() }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + QuitSequence.patience) { [weak self] in
            self?.endAfterGoodbye()
        }
        NotificationCenter.default.post(name: .yumiQuitRequested, object: nil)
        return .terminateCancel
    }

    private func endAfterGoodbye() {
        guard quit.finish() else { return }
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A chat answer still being written would leave its Claude Code process behind.
        ChatArchiveStore.shared.keep(AppState.shared.chatHistory)
        ClaudeService.shared.clearConversation(remember: false)
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: AppIdentity.productName)
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = AppIdentity.productName
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: loc("Ouvrir \(AppIdentity.productName)"), action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: loc("Réglages…"), action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: loc("Quitter Yumi"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings(_ sender: Any? = nil) {
        // The island may ask for a page: Claude Code, to install the hooks
        let page = (sender as? Notification)?.object as? SettingsPage
        let islandBottom = islandController?.makeRoomForSettings()
        if let w = settingsWindow, w.isVisible, page == nil {
            if let islandBottom, w.frame.maxY > islandBottom { w.setFrame(settingsFrame(w.frame.size, islandBottom), display: true) }
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        settingsWindow?.close()
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = loc("Réglages de \(AppIdentity.productName)")
        win.contentMinSize = NSSize(width: 700, height: 480)
        win.contentView = NSHostingView(rootView: SettingsView(page: page ?? .general))
        win.setFrame(settingsFrame(win.frame.size, islandBottom), display: false)
        win.isReleasedWhenClosed = false
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Never under the notch: under the menu bar, and under the island when it stays open.
    private func settingsFrame(_ size: CGSize, _ islandBottom: CGFloat?) -> CGRect {
        let screen = islandController?.window?.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(origin: .zero, size: size)
        return SettingsOpening.frame(size: size, visible: visible, islandBottom: islandBottom)
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        // Filming mode starts nothing real: no hooks, modules, memory, initiative or chat.
        // AppState is then left entirely to the island.
        let plan = LaunchPlan.current
        if plan.hookServer || plan.modules || plan.memory || plan.initiative || plan.context {
            let core = YumiCore(state: .shared)
            core.start()
            self.core = core
        }
        #if DEBUG
        if plan.chat { sendDevelopmentChatPrompts() }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings(_:)),
                                               name: .openFullSettings, object: nil)
    }
}

#if DEBUG
// MARK: - Development: chat without the island
// `YUMI_CHAT_PROMPT` sends its text to the chat a moment after launch ("||" separates several
// messages, sent one after the other) and prints the conversation as it grows. It exercises the
// real path, permission requests in the island included, without typing in the notch.
// `YUMI_CHAT_ANSWERS` ("allow,deny,always") scripts the answers to the permission requests of that
// run, in order: each one presses what the island's buttons press, a second after the request
// appears. Without it the requests wait for a real click. Neither exists in a Release build.

extension AppDelegate {
    private func sendDevelopmentChatPrompts() {
        guard let text = ProcessInfo.processInfo.environment["YUMI_CHAT_PROMPT"], !text.isEmpty else { return }
        let prompts = text.components(separatedBy: "||").map { $0.trimmingCharacters(in: .whitespaces) }
        let state = AppState.shared
        Task { @MainActor in
            var answers = (ProcessInfo.processInfo.environment["YUMI_CHAT_ANSWERS"] ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            var printed = 0
            @MainActor func printNew() {
                for message in state.chatHistory.dropFirst(printed) {
                    print("[chat] \(message.role == .user ? "moi" : "yumi") : \(message.content)")
                }
                printed = state.chatHistory.count
                fflush(stdout)
            }
            try? await Task.sleep(for: .seconds(2))
            for prompt in prompts {
                state.chatHistory.append(ChatMessage(role: .user, content: prompt))
                state.noteMessage = nil
                state.stateOverride = .thinking
                let watcher = Task { @MainActor in
                    var last = ""
                    var answered: String?
                    var lastLive: ChatLive?
                    var liveUpdates = 0
                    while !Task.isCancelled {
                        printNew()
                        if let request = state.pendingApproval, ChatSessionRegistry.shared.contains(request.sessionId),
                           answered != request.command, !answers.isEmpty {
                            answered = request.command
                            let answer = answers.removeFirst()
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1))
                                // Still the same request on screen: never answer another one.
                                guard state.pendingApproval?.command == request.command,
                                      state.pendingApproval?.sessionId == request.sessionId else { return }
                                print("[chat] réponse scriptée : \(answer)")
                                HookServer.shared.sendApprovalDecision(answer)
                            }
                        } else if state.pendingApproval == nil {
                            answered = nil
                        }
                        let now = "\(state.effectiveState)\(state.pendingApproval.map { " · demande : \($0.tool) \($0.command)" } ?? "")"
                        if now != last { print("[chat] état : \(now)"); fflush(stdout); last = now }
                        if state.chatLive != lastLive {
                            lastLive = state.chatLive
                            liveUpdates += 1
                            if let live = lastLive {
                                let activity = live.activity.map { "\($0.kind.rawValue) « \($0.label) »\($0.detail.map { " [\($0.replacingOccurrences(of: "\n", with: " ⏎ "))]" } ?? "")" } ?? "aucune"
                                let done = live.done.map { "\($0.label)\($0.succeeded ? "" : " (non)")" }.joined(separator: ", ")
                                print("[live \(liveUpdates)] texte : \(live.text.count) car. · action : \(activity) · faites : [\(done)]")
                            } else {
                                print("[live \(liveUpdates)] nil")
                            }
                            fflush(stdout)
                        }
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                }
                await ClaudeService.shared.chat(query: prompt, context: state.promptContext, state: state)
                watcher.cancel()
                printNew()
                if let note = state.noteMessage { print("[chat] erreur : \(note)") }
                print("[chat] après la réponse, chatLive : \(state.chatLive == nil ? "nil" : "encore renseigné")")
            }
            if ProcessInfo.processInfo.environment["YUMI_CHAT_END"] != nil {
                // Ends the conversation the way the island does, and waits for its summary.
                let before = state.memory
                ClaudeService.shared.clearConversation()
                for _ in 0..<80 where state.memory == before { try? await Task.sleep(for: .milliseconds(500)) }
            }
            for entry in state.memory { print("[mémoire] \(entry.kind.rawValue) : \(entry.text)") }
            print("[chat] fin")
            fflush(stdout)
        }
    }
}
#endif

// MARK: - Core
// Composition root of everything that feeds the island: the event engine, the session store,
// the modules and the hook server. Nothing here is a singleton; the pieces are created once
// and handed to each other.

@MainActor
final class YumiCore {
    /// A session silent for this long is considered gone (terminal killed without a SessionEnd).
    private static let sessionLifetime: TimeInterval = 12 * 3600

    private let engine = EventEngine()
    private let store = SessionStore()
    private let ingress: EventIngress
    private let mirror: ClaudeTaskMirror
    let modules: ModuleRegistry

    private var chatObserver: AnyCancellable?
    /// What Yumi remembers. The store owns the file; AppState shows it to the island.
    let memory: MemoryStore
    /// Decides when Yumi speaks first (Contracts/RemarkTypes.swift).
    private let initiative: InitiativeDriver
    private var lastSeen: [SessionID: Date] = [:]
    private var consumer: Task<Void, Never>?
    /// What the person is doing on the Mac (Context/). It only looks: nothing acts on it yet.
    let context = ContextEngine(providers: [WorkspaceContextProvider(), WindowContextProvider()])
    private var contextConsumer: Task<Void, Never>?
    private var contextSwitch: AnyCancellable?
    /// Decides, for every step of the agent, allow, ask or deny (Permissions/). Asks in the
    /// island's approval queue; remembers in Yumi's folder; keeps its history there too.
    let permissions = LocalPermissionManager(
        store: FilePermissionStore(url: AppIdentity.supportDirectory.appendingPathComponent("permissions.json")),
        audit: PermissionAuditLog(sink: FileAuditSink(url: AppIdentity.supportDirectory.appendingPathComponent("permissions-audit.jsonl"))))
    private let approvalPresenter = IslandApprovalPresenter()
    private var permissionConsumer: Task<Void, Never>?
    /// Turns a request into checked, observable work (AgentRuntime/). Does nothing until asked.
    /// Plans with the Anthropic key of the settings; every step goes through `permissions`.
    let agent: RuntimeAgent
    private var agentConsumer: Task<Void, Never>?
    private var agentReaction: AgentReaction?

    init(state: AppState) {
        ingress = EventIngress(engine: engine)
        let mirror = ClaudeTaskMirror(state: state)
        self.mirror = mirror
        memory = MemoryStore { book in
            if state.memory != book.entries { state.memory = book.entries }
            if state.userName != book.name { state.userName = book.name }
        }
        let claudeCode = ClaudeCodeModule(onShow: { mirror.show() },
                                          hooksMissing: { EngineFactory.hasClaudeCode && !HookServer.hooksInstalled() },
                                          onInstallHooks: { IslandActions.openSettings(.claudeCode) })
        let agenda = AgendaModule()
        let focus = FocusModule()
        let notes = NotesModule()
        let weather = WeatherModule()
        let music = MusicModule()
        let notion = NotionModule(api: Self.notionAPI,
                                  openSettings: { NotificationCenter.default.post(name: .openFullSettings, object: nil) })
        agent = Self.makeAgent(permissions: permissions,
                               modules: ModuleBridge(focus: focus, agenda: agenda, notes: notes, weather: weather, notion: notion, music: music))
        #if !APPSTORE
        // A task ticked in the island goes through the runtime: the approval, the write, the check.
        let agent = agent
        notion.complete = { task in
            let (plan, request) = CompleteNotionTaskTool.plan(for: task)
            _ = await agent.execute(plan, for: request)
        }
        #endif
        let memory = memory
        var initiativeDefaults = UserDefaults.standard
        #if DEBUG
        // A development build run next to the installed app keeps its own record of what it said.
        if ProcessInfo.processInfo.environment["YUMI_SUPPORT_DIR"] != nil,
           let separate = UserDefaults(suiteName: "\(AppIdentity.keychainService).dev") {
            if let talk = UserDefaults.standard.string(forKey: YumiTalk.defaultsKey) { separate.set(talk, forKey: YumiTalk.defaultsKey) }
            initiativeDefaults = separate
        }
        #endif
        initiative = InitiativeDriver(links: InitiativeLinks(
            show: { remark in
                state.remark = remark
                #if DEBUG
                if ProcessInfo.processInfo.environment["YUMI_TRACE_INITIATIVE"] != nil {
                    print(remark.map { "[remarque] \($0.text)\($0.action.map { " [\($0)]" } ?? "") (\($0.mood.rawValue), \(Int($0.duration)) s)" } ?? "[remarque] retirée")
                    fflush(stdout)
                }
                #endif
            },
            memory: { memory.book },
            focusRunning: { focus.isFocusing },
            agenda: {
                guard let events = agenda.upcomingToday else { return (nil, nil) }
                return (events.count, events.first.map { ($0.title, $0.start) })
            },
            perform: { action in
                switch action {
                case .takeBreak:   focus.takeBreak()
                case .openSession: ClaudeTaskMirror.openSession()
                }
            }), defaults: initiativeDefaults)
        // The chat answers through Claude Code: its module tells the folded island what it is doing.
        // The text of the answer changes many times a second, the announcement only with the action.
        chatObserver = state.$chatLive
            .map(ChatAnnouncement.init)
            .removeDuplicates()
            .sink { [weak claudeCode] in claudeCode?.announceChat($0) }
        modules = ModuleRegistry(
            modules: [
                claudeCode,
                agenda,
                notes,
                focus,
                music,
                weather,
                ScreenTimeModule(
                    onThreshold: { [initiative] minutes, threshold in
                        initiative.notice(.screenTime(minutes: minutes, threshold: threshold))
                    },
                    onBreak: { [initiative] in initiative.rested() },
                    openSettings: { NotificationCenter.default.post(name: .openFullSettings, object: SettingsPage.modules) }),
                notion,
                GitHubModule(
                    token: { GitHubAuth.currentToken },
                    prepare: { await GitHubAuth.shared.renewIfNeeded() },
                    viaApp: { GitHubAuth.viaApp },
                    onConnect: { NotificationCenter.default.post(name: .openFullSettings, object: nil) },
                    onNews: { [initiative] event, count in initiative.notice(.repository(event, count: count)) }),
                GmailModule(
                    credentials: {
                        guard let address = UserDefaults.standard.string(forKey: GmailModule.addressKey), !address.isEmpty,
                              let password = KeychainStore.shared.get(GmailModule.passwordKey), !password.isEmpty else { return nil }
                        return (address, password)
                    },
                    source: {
                        MailSource.current(gmailConnected: KeychainStore.shared.get(GmailModule.passwordKey)?.isEmpty == false)
                    },
                    hiddenAccounts: { MailAccounts.hidden() },
                    onNewMail: { [initiative] mail, count in
                        initiative.notice(.mail(from: mail.from, subject: mail.subject, count: count))
                    },
                    onConnect: { NotificationCenter.default.post(name: .openFullSettings, object: SettingsPage.modules) }),
            ],
            onPublish: { snapshots in
                state.modules = snapshots
                Self.trace(snapshots)
            }
        )
    }

    /// Debug builds only: with `YUMI_TRACE_MODULES` set, prints the snapshots each time they change.
    private static func trace(_ snapshots: [ModuleSnapshot]) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["YUMI_TRACE_MODULES"] != nil else { return }
        for snapshot in snapshots {
            let actions = [snapshot.primaryAction, snapshot.secondaryAction].compactMap { $0 }.joined(separator: " | ")
            print("[\(snapshot.name)] \(snapshot.status) · \(snapshot.title) · \(snapshot.subtitle) · \(actions)\(snapshot.needsAttention ? " · !" : "")\(snapshot.live.map { " · en direct (\($0.priority)) : \($0.text)" } ?? "")")
        }
        print("")
        fflush(stdout)
        #endif
    }

    func start() {
        startContext(state: .shared)
        startAgent(state: .shared)
        memory.start()
        ClaudeService.shared.memory = memory
        modules.share(with: .shared)
        modules.start()
        initiative.start()
        // The iPhone, through the person's iCloud, when this build can and they turned it on
        MacLink.shared.start()
        #if DEBUG
        if let seconds = ProcessInfo.processInfo.environment["YUMI_TRACE_INITIATIVE"].flatMap(Double.init) {
            // Development: after that many seconds, says how often the initiative was woken.
            Task { [initiative] in
                try? await Task.sleep(for: .seconds(seconds))
                print("[initiative] réveils en \(Int(seconds)) s : \(initiative.wakeUps)")
                fflush(stdout)
            }
        }
        #endif
        consumer = Task { [engine, store, ingress, weak self] in
            // Subscribe before the socket opens: the engine does not keep events for later.
            let events = await engine.subscribe()
            HookServer.shared.start(ingress: ingress)
            for await event in events {
                let sessions = await store.apply(event)
                guard let self else { return }
                self.mirror.receive(event, sessions: sessions)
                self.modules.receive(event, sessions: sessions)
                self.initiative.session(event, sessions: sessions)
                self.endSilentSessions(after: event, in: sessions)
            }
        }
    }

    /// The engine feeds `AppState.context`, and follows the switch of the settings.
    private func startContext(state: AppState) {
        guard LaunchPlan.current.context else { return }
        let messages = context.messages()
        contextConsumer = Task { [weak state] in
            for await message in messages {
                switch message {
                case .event(let event):
                    Self.trace(event)
                case .contextUpdated(let snapshot):
                    guard let state else { return }
                    state.context = snapshot
                }
            }
        }
        contextSwitch = state.$contextEnabled
            .removeDuplicates()
            .sink { [context] enabled in context.setEnabled(enabled) }
    }

    /// The runtime Yumi works with. It plans with the Claude Code installed on the Mac, used as a
    /// model without any tool, through the person's own Claude Code login; without it, with the
    /// settings' Anthropic key; with neither, it says how to set one up. Writing is allowed up to
    /// creating a file or a reminder, which always asks first; starting a Focus and summing up the
    /// day need no question. The App Store build may not launch programs nor write outside its
    /// container: it plans with the key only, and only reads.
    /// Notion, with the integration key of the settings (Keychain).
    static let notionAPI = NotionAPI(key: { KeychainStore.shared.get("notion-integration-key") })

    private static func makeAgent(permissions: LocalPermissionManager, modules: ModuleBridge) -> RuntimeAgent {
        // The engines of the settings, in their order (EngineFactory): read again at each request.
        // Without any, the simple mode plans the common requests itself.
        let planner = EngineFactory.agentPlanner
        #if APPSTORE
        return RuntimeAgent(planner: planner, permissions: permissions)
        #else
        var tools = ToolRegistry.standard
        // The files Yumi created: the only ones it may add to later.
        let created = FileCreatedFilesLog(url: AppIdentity.supportDirectory.appendingPathComponent("created-files.json"))
        try? tools.register(CreateFileTool(log: created))
        try? tools.register(AppendToFileTool(log: created))
        try? tools.register(AddEventTool(store: EventKitEventStore()))
        try? tools.register(AddNotionTaskTool(store: NotionAgentStore(api: notionAPI)))
        try? tools.register(CompleteNotionTaskTool(store: NotionAgentStore(api: notionAPI)))
        try? tools.register(AddReminderTool(store: EventKitReminderStore()))
        try? tools.register(StartFocusTool(focus: modules))
        try? tools.register(GetTodayTool(source: modules))
        try? tools.register(ControlMusicTool(music: modules))
        return RuntimeAgent(planner: planner, tools: tools, permissions: permissions,
                            policy: AgentPolicy(maximumRisk: .write))
        #endif
    }

    /// The settings reach the runtime through `AppState.agent`; Yumi reacts to every run.
    private func startAgent(state: AppState) {
        state.agent = agent
        state.permissions = permissions
        permissions.presenter = approvalPresenter
        let permissionEvents = permissions.events()
        permissionConsumer = Task { [weak state] in
            for await event in permissionEvents {
                guard let state else { return }
                ApprovalReaction.apply(event, to: state)
            }
        }
        let reaction = AgentReaction(state: state)
        agentReaction = reaction
        let events = agent.events()
        #if DEBUG
        let traces = ProcessInfo.processInfo.environment["YUMI_TRACE_AGENT"] != nil
        #else
        let traces = false
        #endif
        agentConsumer = Task { [agent] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            for await event in events {
                reaction.apply(event, agent: agent)
                if traces, let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
                    print("[agent] \(line)")
                    fflush(stdout)
                }
            }
        }
    }

    /// Debug builds only: with `YUMI_TRACE_CONTEXT` set, prints each context event as JSON.
    private static func trace(_ event: ContextEvent) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["YUMI_TRACE_CONTEXT"] != nil else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(event), let line = String(data: data, encoding: .utf8) {
            print("[contexte] \(line)")
            fflush(stdout)
        }
        #endif
    }

    /// Sessions normally end with a hook. One that has said nothing for hours is dropped,
    /// unless it is waiting for the user. Checked when an event arrives: no timer needed.
    private func endSilentSessions(after event: YumiEvent, in sessions: [SessionID: Session]) {
        let now = Date()
        if let id = event.sessionID { lastSeen[id] = sessions[id] == nil ? nil : now }
        for (id, seen) in lastSeen where now.timeIntervalSince(seen) > Self.sessionLifetime {
            lastSeen[id] = nil
            if let session = sessions[id], session.status != .waitingForUser {
                ingress.post(.sessionEnded(id))
            }
        }
    }
}
