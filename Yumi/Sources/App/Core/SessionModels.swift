import Foundation

// MARK: - Session lifecycle status

/// Lifecycle of one session.
enum SessionStatus: Equatable, Codable, Sendable {
    case running
    case waitingForUser
    case errored
    case completed
    /// The agent is held back by a usage limit until further notice.
    case rateLimited
}

// MARK: - Current activity

/// What the agent is doing right now inside a session.
enum YumiActivity: Equatable, Codable, Sendable {
    case idle
    /// The agent received a prompt and has not started a tool yet.
    case thinking
    case working(ToolInfo)
    case asking(Question)
    case requestingPermission(PermissionRequest)
}

// MARK: - Event payloads

/// A tool invocation (command run, file edit, search, …).
struct ToolInfo: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var name: String
    var summary: String

    init(id: String = UUID().uuidString, name: String, summary: String = "") {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// A permission the agent needs before continuing (e.g. run a command).
struct PermissionRequest: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var tool: String
    var command: String

    init(id: String = UUID().uuidString, tool: String, command: String = "") {
        self.id = id
        self.tool = tool
        self.command = command
    }
}

/// A question the agent asks the user.
struct Question: Equatable, Codable, Sendable, Identifiable {
    let id: String
    var text: String
    var options: [String]

    init(id: String = UUID().uuidString, text: String, options: [String] = []) {
        self.id = id
        self.text = text
        self.options = options
    }
}

/// An error reported by a session.
struct YumiError: Equatable, Codable, Sendable {
    var message: String

    init(message: String) { self.message = message }
}

// MARK: - Origin

/// Where a session runs. Lets Yumi bring the right window back to the front.
struct SessionOrigin: Equatable, Codable, Sendable {
    /// Folder the agent works in. Empty when unknown.
    var workingDirectory: String
    /// Bundle identifier of the application hosting the session (terminal, editor). Empty when unknown.
    var hostBundleID: String
    /// Name the host gives itself (`TERM_PROGRAM` for a terminal). Empty when unknown.
    var hostName: String
    /// Terminal device of the session (`/dev/ttys004`): finds its tab in Terminal or iTerm2. Empty when unknown.
    var tty: String
    /// iTerm2's own identifier of the session's pane (the UUID of `ITERM_SESSION_ID`). Empty when unknown.
    var terminalSessionID: String
    /// The model the agent runs on, as it names it ("claude-opus-4-5-20251101"). nil when unknown.
    var model: String? = nil

    init(workingDirectory: String = "", hostBundleID: String = "", hostName: String = "",
         tty: String = "", terminalSessionID: String = "") {
        self.workingDirectory = workingDirectory
        self.hostBundleID = hostBundleID
        self.hostName = hostName
        self.tty = tty
        self.terminalSessionID = terminalSessionID
    }
}

// MARK: - Session

/// One session = one run of an agent (e.g. one Claude Code conversation).
/// A plain value type: the store owns all sessions, events transform them.
struct Session: Equatable, Codable, Sendable, Identifiable {
    let id: SessionID
    let agent: Agent
    var title: String
    var status: SessionStatus
    var activity: YumiActivity
    var origin: SessionOrigin?
    /// True between a prompt and the end of the answer. Tells a session busy between
    /// two tools (running, no activity) from one waiting for its next prompt.
    var isTurnActive: Bool
    /// Rank of the last event that touched the session: the highest value is the most
    /// recently active session. Lets consumers order sessions without a clock.
    var recency: Int

    init(id: SessionID = SessionID(), agent: Agent, title: String) {
        self.id = id
        self.agent = agent
        self.title = title
        self.status = .running
        self.activity = .idle
        self.origin = nil
        self.isTurnActive = false
        self.recency = 0
    }
}
