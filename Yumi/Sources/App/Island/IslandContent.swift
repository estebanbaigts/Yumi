import AppKit
import SwiftUI

// The words of the open island and what its buttons do. Built from `AppState`.

/// What the island says about the agent (Claude Code): who, what, since when.
@MainActor
enum IslandAgent {

    /// "Claude Code · yumi"
    static func name(_ task: AgentTask?) -> String {
        guard let task else { return "Claude Code" }
        let source = "Claude Code"
        // "VS Code" is the name of the task while no session has given its project
        return task.name.isEmpty || task.name == "VS Code" || task.name == source ? source : "\(source) · \(task.name)"
    }

    /// "Claude modifie IslandRootView.swift": the current step, said the way Yumi says it.
    static func doing(_ state: AppState) -> String {
        switch state.effectiveState {
        case .thinking:  return loc("Claude réfléchit")
        case .searching: return loc("Claude cherche")
        default:
            return state.focusTask?.steps.last.flatMap(sentence(forStep:)) ?? loc("Claude travaille")
        }
    }

    /// "Modifie · IslandRootView.swift" → "Claude modifie IslandRootView.swift".
    /// The labels are the ones of HookServer.frenchStep.
    private static func sentence(forStep step: String) -> String? {
        // The labels are localized the same way (ClaudeToolPhrase), so the step is read back in
        // the language it was written in.
        let verbs: KeyValuePairs<String, String> = [
            loc("Exécute"): loc("lance"), loc("Lit"): loc("lit"), loc("Écrit"): loc("écrit"), loc("Modifie"): loc("modifie"),
            loc("Cherche"): loc("cherche"), loc("Recherche"): loc("cherche"), loc("Recherche web"): loc("cherche sur le web"),
            loc("Récupère"): loc("récupère"), loc("Liste"): loc("regarde"), loc("Tâches"): loc("met à jour ses tâches"),
            loc("Agent"): loc("lance un agent"), loc("Notebook"): loc("modifie un notebook"),
        ]
        let parts = step.components(separatedBy: " · ")
        guard let verb = verbs.first(where: { $0.key == parts[0] })?.value else { return nil }
        let detail = parts.dropFirst().joined(separator: " · ")
        return detail.isEmpty ? loc("Claude \(verb)") : loc("Claude \(verb) \(detail)")
    }

    /// "Depuis douze minutes, trois fichiers touchés. Je surveille."
    static func watching(_ model: IslandModel) -> String {
        var parts: [String] = []
        if let start = model.workStart { parts.append(loc("depuis \(Voice.duration(Date.now.timeIntervalSince(start)))")) }
        if let files = Voice.files(model.filesTouched.count) { parts.append(files) }
        if parts.isEmpty { return loc("Il vient de s'y mettre. Je surveille.") }
        return Voice.sentence(parts.joined(separator: ", ")) + loc(". Je surveille.")
    }

    /// "12 min": the key figure, read at a glance.
    static func elapsed(_ model: IslandModel, until end: Date = .now) -> String? {
        guard let start = model.workStart else { return nil }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// "Trois fichiers touchés en douze minutes." He only says what he saw.
    static func finishedLine(_ state: AppState, _ model: IslandModel) -> String {
        if let files = Voice.files(model.filesTouched.count), let start = model.workStart {
            return Voice.sentence(loc("\(files) en \(Voice.duration((model.workEnd ?? .now).timeIntervalSince(start)))."))
        }
        return state.focusTask?.steps.last ?? loc("La session est terminée.")
    }
}

/// How a module looks in the island (Contracts/ModuleTypes.swift).
extension ModuleSnapshot {
    var color: Color { Color(hex: colorHex) }

    /// Its SF Symbol; a module that gives none gets one from what it is.
    var glyph: String {
        guard symbol == "circle.fill" else { return symbol }
        switch id {
        case "claude-code":       return "terminal"
        case "agenda":            return "calendar"
        case "notes":             return "note.text"
        case "focus":             return "timer"
        case "music", "musique":  return "music.note"
        case "weather", "meteo":  return "sun.max"
        case "github":            return "chevron.left.forwardslash.chevron.right"
        default:                  return symbol
        }
    }
}

// MARK: - What the buttons do

@MainActor
enum IslandActions {
    private static var state: AppState { .shared }

    /// A tap that changes nothing by itself: the little "tap" of the mock-up.
    /// The settings window, on a page. Does not depend on the menu bar item, which the notch
    /// can hide on a small screen.
    static func openSettings(_ page: SettingsPage = .general) {
        NotificationCenter.default.post(name: .openFullSettings, object: page)
    }

    static func tap() {
        SoundEngine.shared.play("blip")
    }

    /// Shows another view of the open island.
    static func go(_ view: IslandView) {
        leaveChatError(next: view)
        #if !APPSTORE
        if view == .prompt, state.promptContext == nil {
            state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp, askingFirst: false)
            state.contextAttached = true
            state.contextExplicit = false
        }
        #endif
        if view == .upload {
            // A fresh drop zone: the previous file has been dealt with
            state.droppedFile = nil
        }
        state.view = view
        state.lastActivity = .now
        tap()
    }

    static func showModule(_ id: String) {
        leaveChatError(next: .module)
        IslandModel.shared.selectedModuleID = id
        state.view = .module
        state.lastActivity = .now
        tap()
    }

    /// A module button was pressed: the core does the work (Contracts/ModuleTypes.swift).
    static func module(_ id: String, _ action: String) {
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": id, "action": action])
        tap()
        IslandModel.shared.pose(.pop)
    }

    /// A line of a module's list was clicked.
    static func row(_ module: String, _ action: String) {
        NotificationCenter.default.post(name: .moduleRowAction, object: nil,
                                        userInfo: ["module": module, "row": action])
        tap()
    }

    /// A button of the folded island: the same action as in the detail view, and the
    /// island stays folded.
    static func liveControl(_ id: String, _ action: String) {
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": id, "action": action])
        tap()
        state.lastActivity = .now
    }

    /// A click on Yumi: he bounces, and the chat opens.
    static func pokeYumi(talking: Bool) {
        SoundEngine.shared.play("pop")
        IslandModel.shared.pose(.boing)
        if !talking { go(.prompt) }
    }

    // MARK: First name

    /// The person gave their first name: the core keeps it (Contracts/MemoryTypes.swift).
    static func giveName(_ name: String) {
        UserDefaults.standard.set(Date.now, forKey: IslandPrefs.nameAskedKey)
        NotificationCenter.default.post(name: .memorySetName, object: nil, userInfo: ["name": name])
        SoundEngine.shared.play("approve")
        IslandModel.shared.pose(.wave)
        go(.overview)
    }

    /// Passed over: he asks again in a few days, not before.
    static func skipName() {
        UserDefaults.standard.set(Date.now, forKey: IslandPrefs.nameAskedKey)
        fold()
    }

    // MARK: Memory (Contracts/MemoryTypes.swift)

    static func correct(_ id: String, _ text: String) {
        NotificationCenter.default.post(name: .memoryEdit, object: nil, userInfo: ["id": id, "text": text])
        tap()
    }

    static func forget(_ id: String) {
        NotificationCenter.default.post(name: .memoryDelete, object: nil, userInfo: ["id": id])
        tap()
    }

    static func forgetEverything() {
        NotificationCenter.default.post(name: .memoryClear, object: nil)
        SoundEngine.shared.play("close")
        IslandModel.shared.pose(.dip)
    }

    // MARK: GitHub

    /// The key the core reads the token from (KeychainStore, never on disk).
    static let githubTokenKey = "github-token"

    static var githubConnected: Bool { KeychainStore.shared.get(githubTokenKey)?.isEmpty == false }

    /// Hands the token to the core's Keychain store, and tells the module to read it again.
    static func connectGitHub(_ token: String?) {
        if let token {
            KeychainStore.shared.set(githubTokenKey, value: token)
            SoundEngine.shared.play("approve")
        } else {
            KeychainStore.shared.remove(githubTokenKey)
            tap()
        }
        NotificationCenter.default.post(name: .moduleAction, object: nil,
                                        userInfo: ["module": "github", "action": "secondary"])
    }

    static func manageModules() {
        NotificationCenter.default.post(name: .openFullSettings, object: nil)
        tap()
    }

    static func fold() {
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    /// The chat service leaves `stateOverride = .error` behind after a failure; nothing
    /// else clears it.
    static func leaveChatError(next: IslandView?) {
        if state.view == .note, next != .note, state.stateOverride == .error {
            state.stateOverride = nil
        }
    }

    /// Brings the agent's own window forward: the application its session runs in.
    static func openAgent(_ task: AgentTask?) {
        // Where the conversation is: the terminal, the editor or the Claude app the session runs in.
        ClaudeTaskMirror.openSession()
    }

    // MARK: Talk

    static func send(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.noteMessage = nil
        state.stateOverride = .thinking
        state.view = .prompt
        state.lastActivity = .now
        SoundEngine.shared.play("send")
        let appState = state
        // Only what the person left attached goes, and a page only by its domain without a gesture.
        let context = appState.promptContext?.outgoing(attached: appState.contextAttached, explicit: appState.contextExplicit)
        Task { await ClaudeService.shared.chat(query: query, context: context, state: appState) }
    }

    // MARK: Drop

    /// "Résumer": the file he was given, or failing that the window the user was in.
    static func summarize() {
        if let file = state.droppedFile {
            send(loc("Résume-moi \(file.name) en trois points"))
            return
        }
        #if !APPSTORE
        if let context = WindowContextCapture.captureActive(from: state.lastExternalApp) {
            newConversation()
            state.promptContext = context
            state.contextAttached = true
            state.contextExplicit = true
            send(loc("Résume-moi cette fenêtre en trois points"))
            return
        }
        #endif
        go(.prompt)
    }

    /// "Envoyer": a new mail with the file attached; the user writes and sends it.
    static func sendByMail() {
        guard let file = state.droppedFile, let service = NSSharingService(named: .composeEmail) else {
            tap()
            return
        }
        service.subject = file.name
        service.perform(withItems: [file.url])
        SoundEngine.shared.play("send")
        IslandModel.shared.pose(.pop)
        fold()
    }

    /// "Ranger": the file stays in Yumi's inbox (FileDropHandler copied it there).
    static func putAway() {
        guard state.droppedFile != nil else {
            tap()
            return
        }
        SoundEngine.shared.play("approve")
        IslandModel.shared.pose(.pop)
        state.droppedFile = nil
        fold()
    }

    /// A new file or window is a new subject: the conversation starts again with it.
    static func newConversation() {
        ClaudeService.shared.clearConversation()
        state.chatHistory = []
        state.noteMessage = nil
    }
}
