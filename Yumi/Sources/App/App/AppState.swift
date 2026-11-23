import Foundation
import SwiftUI
import Combine

// Integration pills — always-present, never purged
extension AgentTask {
    /// The permanent Claude Code task: the sessions' state lives in it (ClaudeTaskMirror).
    static let claudeCode = AgentTask(id: "integration_claude", name: "Claude Code", color: "#F5F6F8",
                                      state: .idle, steps: [], source: .claudeCode, isIntegration: true)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// True while filming (`YUMI_STUDIO=1`): nothing real runs and the island owns everything here.
    static let isStudio = StudioMode.isOn

    // Island state
    @Published var mode: IslandMode = .hidden
    @Published var view: IslandView = .overview

    // Tasks
    @Published var tasks: [AgentTask] = []
    /// How the Mac is doing (hot, busy, short of memory), read by `MacVitalsMonitor`. Nil when fine.
    @Published var macStrain: MacStrain? = nil
    @Published var focusId: String? = nil

    // Bot state override
    @Published var stateOverride: BotState? = nil

    // Real notch dimensions (set by IslandWindowController on launch)
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    // Last app active before Yumi (for window context capture)
    var lastExternalApp: NSRunningApplication? = nil

    // Bot drag-attach state (hides original bot while ghost follows cursor)
    @Published var isDraggingBot: Bool = false

    // Mouse tracking
    var mousePosition: CGPoint = .zero
    var lastMouseMove: Date = .now
    var lastActivity: Date = .now
    var isPresent: Bool = true

    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Upload progress (0-1) — set to 1.0 only at completion; animation is time-based
    @Published var uploadProgress: Double = 0

    // Upload animation timing (non-published — TimelineViews read these directly)
    var uploadStartTime: Date?
    var uploadDuration: Double = 2.4

    // File drag-over state (mailbox morph glow + mouth spring)
    @Published var fileDragOver: Bool = false

    // Sound enabled — persisted
    @Published var soundEnabled: Bool = true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled") }
    }

    // Sound volume (0–0.2) — persisted, synced to SoundEngine
    @Published var soundVolume: Double = 0.12 {
        didSet {
            UserDefaults.standard.set(soundVolume, forKey: "soundVolume")
            SoundEngine.shared.volume = Float(soundVolume)
        }
    }

    // Context for prompt (window attach / file)
    @Published var promptContext: PromptContext? = nil
    /// The context shown in the chat goes with the next message; one click on « Avec … » detaches it.
    @Published var contextAttached: Bool = true
    /// The context comes from a gesture of the person (« Résumer », a dragged window, a dropped
    /// file): it goes as it is. Otherwise a page's address is reduced to its domain.
    var contextExplicit: Bool = false

    // Dropped file (set during upload flow)
    @Published var droppedFile: DroppedFile? = nil

    // Short note message (shown in NoteView)
    @Published var noteMessage: String? = nil

    // Auto-close delay — persisted
    @Published var autoCloseInterval: TimeInterval = 15 {
        didSet { UserDefaults.standard.set(autoCloseInterval, forKey: "autoCloseInterval") }
    }

    // Absence interval — persisted: how long the compact island stays without the pointer before hiding
    @Published var absenceInterval: TimeInterval = 3 * 60 {
        didSet { UserDefaults.standard.set(absenceInterval, forKey: "absenceInterval") }
    }

    // Greeting threshold — how long hidden before greeting on reappear (default 2 min)
    var greetThresholdSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(greetThresholdSeconds, forKey: "greetThreshold") }
    }

    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }

    // Vercel project filter — empty = watch all projects

    // Chat conversation history
    @Published var chatHistory: [ChatMessage] = []
    // The answer in progress, word by word and action by action (see Contracts/ChatLive.swift).
    // nil when the chat is idle.
    @Published var chatLive: ChatLive? = nil

    // What Yumi remembers (see Contracts/MemoryTypes.swift). Filled by the core's memory store.
    @Published var memory: [MemoryEntry] = []
    // The person's first name, nil until they give it at first launch.
    @Published var userName: String? = nil

    // What Yumi says on his own right now (see Contracts/RemarkTypes.swift). nil when he is quiet.
    @Published var remark: YumiRemark? = nil

    // Pending approval request from Claude Code hook
    @Published var pendingApproval: ApprovalInfo? = nil

    // What the Context Engine sees: front application, window, session (see Context/).
    // Filled by the core; stays disabled while filming or when the person turns it off.
    @Published var context: ContextSnapshot = .disabled()

    // The Context Engine runs only while this is on. Persisted.
    @Published var contextEnabled: Bool = true {
        didSet { UserDefaults.standard.set(contextEnabled, forKey: "contextEngineEnabled") }
    }

    // The agent runtime (see AgentRuntime/), set by the core at launch. nil while filming.
    // Started from the settings' agent section; Yumi reacts to its runs (AgentReaction).
    @Published var agent: RuntimeAgent? = nil
    // The permission system (see Permissions/), set by the core at launch. nil while filming.
    @Published var permissions: LocalPermissionManager? = nil

    // Modules shown in the island, pinned ones first (see Contracts/ModuleTypes.swift).
    // Kept up to date by the ModuleRegistry: one snapshot per selected module, in selection order.
    @Published var modules: [ModuleSnapshot] = []

    // MARK: - Init (loads persisted settings)

    private init() {
        let ud = UserDefaults.standard

        if let v = ud.object(forKey: "soundEnabled") as? Bool   { soundEnabled = v }
        if let v = ud.object(forKey: "soundVolume")  as? Double { soundVolume  = v }
        // Migrate old 60s default → 15s
        if let v = ud.object(forKey: "autoCloseInterval") as? Double {
            autoCloseInterval = (v == 60) ? 15 : v
        }
        if let v = ud.object(forKey: "absenceInterval")   as? Double { absenceInterval   = v }
        if let v = ud.object(forKey: "greetThreshold")    as? Double { greetThresholdSeconds = v }
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "contextEngineEnabled") as? Bool { contextEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }

        // Sync SoundEngine volume on launch
        SoundEngine.shared.volume = Float(soundVolume)

        // Always load integration pills
        loadIntegrationTasks()
    }

    // MARK: - Computed

    var focusTask: AgentTask? {
        tasks.first { $0.id == focusId } ?? tasks.first
    }

    var effectiveState: BotState {
        stateOverride ?? focusTask?.state ?? .idle
    }

    // MARK: - Task management

    func addTask(_ task: AgentTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
        if focusId == nil { focusId = task.id }
        syncMode()
        syncView()
    }

    func removeTask(id: String) {
        tasks.removeAll { $0.id == id }
        if focusId == id { focusId = tasks.first?.id }
        syncMode()
        syncView()
    }

    func updateTask(id: String, state: BotState) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].state = state
    }

    func setFocus(_ id: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        focusId = id
        tasks[idx].pillBadge = nil  // clear badge when user brings task to focus
    }

    func syncMode() {
        // If no tasks and not expanded/peek, go hidden
        if tasks.isEmpty && mode == .compact {
            mode = .hidden
        } else if !tasks.isEmpty && mode == .hidden && isPresent {
            mode = .compact
        }
    }

    func syncView() {
        guard mode == .expanded else { return }
        if view == .empty && !tasks.isEmpty { view = .overview }
        else if view == .overview && tasks.isEmpty { view = .empty }
    }

    /// Loads the permanent Claude Code task. Safe to call multiple times.
    func loadIntegrationTasks() {
        if !tasks.contains(where: { $0.id == AgentTask.claudeCode.id }) { tasks.append(AgentTask.claudeCode) }
        if focusId == nil { focusId = AgentTask.claudeCode.id }
    }
}

// MARK: - Supporting types

enum PromptContext {
    case window(appName: String, title: String, url: String?)
    case file(name: String, fileURL: URL?)

    /// What may leave with a message, after the person's choice (ChatContextPolicy).
    func outgoing(attached: Bool, explicit: Bool) -> PromptContext? {
        let chat: ChatContext = switch self {
        case .window(let app, let title, let url): .window(app: app, title: title, url: url)
        case .file(let name, let fileURL): .file(name: name, path: fileURL?.path)
        }
        switch ChatContextPolicy.outgoing(chat, attached: attached, explicit: explicit) {
        case .window(let app, let title, let url)?: return .window(appName: app, title: title, url: url)
        case .file?: return self
        case nil: return nil
        }
    }
}

struct DroppedFile {
    var url: URL
    var name: String
}

// MARK: - Chat

enum ChatRole { case user, assistant }

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    /// Who answered (Apple, Simple, Claude…), shown discreetly under the answer.
    var engine: String? = nil
    /// Buttons under the answer: the simple mode offers them when it did not understand.
    var suggestions: [ChatSuggestion] = []
}
