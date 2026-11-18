import Foundation

// MARK: - Island Mode

enum IslandMode: String, CaseIterable {
    case hidden, compact, expanded
}

// MARK: - Island View

enum IslandView: String, CaseIterable {
    case overview, empty, approval, question, error, finished
    case confused, upload, choose, prompt
    case searching, result, note, settings, greeting
    /// Detail of one module (the one in `IslandModel.selectedModuleID`).
    case module
    /// First launch: Yumi asks the person's first name.
    case welcome
    /// Everything Yumi remembers, to read, correct and erase.
    case memory
    /// The quick task field and the day's list of its destination.
    case quickTask
}

// MARK: - What the island shows (design/maquette/reference.html)

/// The eight views of the open island. Several legacy `IslandView` values, still set by
/// the hook server and the chat service, land on the same screen.
enum IslandScreen: String, CaseIterable {
    /// `home` is the overview ("Tous"): what the island opens on when nothing is urgent.
    case home, working, alert, finished, error, module, talk, drop, settings, welcome, memory, quickTask

    /// The screen for what the application says right now. A view that names a screen wins;
    /// on the home view, only what is urgent takes its place.
    static func resolve(view: IslandView, state: BotState, approvalPending: Bool) -> IslandScreen {
        switch view {
        case .approval, .question:                      return .alert
        case .finished:                                 return .finished
        case .error:                                    return .error
        case .prompt, .searching, .result, .note:       return .talk
        case .upload, .choose:                          return .drop
        case .module:                                   return .module
        case .settings:                                 return .settings
        case .welcome:                                  return .welcome
        case .memory:                                   return .memory
        case .quickTask:                                return .quickTask
        case .overview, .empty, .confused, .greeting:
            // Only what waits for the person takes the home's place. An error or a finished
            // session is shown once, when it happens (`view` .error or .finished): it must never
            // stand between the person and the rest of the island until the session moves again
            // (a Claude Code session out of usage stays in error until the limit comes back).
            if approvalPending { return .alert }
            switch state {
            case .approval, .question:                  return .alert
            case .error, .finished, .working, .thinking, .searching, .idle, .ratelimit, .sleeping, .dizzy:
                return .home
            }
        }
    }
}

// MARK: - Bot State

enum BotState: String, CaseIterable {
    case idle, working, thinking, searching
    case approval, question, error, finished
    case ratelimit, sleeping, dizzy
}

// MARK: - Bot Emote

enum BotEmote: String, CaseIterable {
    case love, surprised, proud, wink, yawn, happy, annoyed
}

// MARK: - Approval info (pending PermissionRequest from Claude Code)

struct ApprovalInfo: Sendable {
    var sessionId: String
    var tool: String
    var command: String
    /// Set when Yumi's own agent asks (Permissions/): the island shows its short sentence, and
    /// its details on demand, instead of a command.
    var agentRequest: ApprovalRequest? = nil
    /// The request this card answers (`HookServer`). A click answers this one or nothing: the
    /// queue may have moved on (an expiry, a withdrawal) between the drawing and the click.
    var requestID: String? = nil
}

// MARK: - Pill badge (shown on pill edge when non-focused task has an alert)

enum PillBadge { case approval, finished, error }

// MARK: - Agent Task

struct AgentTask: Identifiable, Equatable {
    var id: String
    var name: String
    var color: String          // hex
    var state: BotState
    var stepIndex: Int = 0
    var steps: [String]
    var source: AgentSource
    var isIntegration: Bool = false  // true for the permanent Claude Code task
    var emote: BotEmote? = nil
    var pillBadge: PillBadge? = nil  // alert badge shown on pill when not focused
    var sessionCwd: String?  = nil  // last known working directory (Claude Code sessions)
    var agentName: String = "Claude Code"  // the coding agent of the session shown: "Codex", "Gemini CLI"
    var speaker: String = "Claude"         // how Yumi names it in a sentence: "Codex modifie main.swift"
}

enum AgentSource: Equatable {
    case claudeCode
}
