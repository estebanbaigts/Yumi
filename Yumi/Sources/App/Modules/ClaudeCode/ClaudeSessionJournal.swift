import Foundation

// What each Claude Code session is working on, read from its hooks: the person's request, the
// task of Claude's todo list and the progress, the action in progress, the last actions, and a
// short summary when a turn ends. Everything stays on the Mac: nothing here goes to Yumi's
// engine or anywhere else, and commands and requests are shown with their secrets masked.

/// One hook, reduced to what the journal keeps. Pure: payload in, note out.
struct SessionNote: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case prompt(String)
        case toolStarted(ToolStep)
        case toolFinished(ToolStep, failed: Bool)
        case todos([SessionTodo])
        /// The end of a turn, with Claude's last message when it could be read.
        case stop(lastMessage: String?)
        case notification(String)
        case ended
    }

    var session: String
    var kind: Kind

    /// The note of a hook payload, nil for one that says nothing new.
    /// - Parameter lastMessage: reads Claude's last message for a Stop (from the transcript).
    static func from(_ payload: [String: Any], lastMessage: (String) -> String? = { _ in nil }) -> SessionNote? {
        guard let session = payload["session_id"] as? String else { return nil }
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let tool = payload["tool_name"] as? String ?? ""
        // Gemini CLI names the same moments its own way.
        let aliases = ["BeforeTool": "PreToolUse", "AfterTool": "PostToolUse", "BeforeAgent": "UserPromptSubmit", "AfterAgent": "Stop"]
        let event = payload["hook_event_name"] as? String ?? ""
        switch aliases[event] ?? event {
        case "UserPromptSubmit":
            guard let prompt = (payload["prompt"] as? String).flatMap({ SessionText.oneLine(SecretMask.mask($0)) }), !prompt.isEmpty else { return nil }
            return SessionNote(session: session, kind: .prompt(prompt))
        case "PreToolUse":
            if tool == "TodoWrite", let todos = SessionTodo.list(from: input) { return SessionNote(session: session, kind: .todos(todos)) }
            return SessionNote(session: session, kind: .toolStarted(ToolStep(tool: tool, input: input)))
        case "PostToolUse":
            if tool == "TodoWrite", let todos = SessionTodo.list(from: input) { return SessionNote(session: session, kind: .todos(todos)) }
            return SessionNote(session: session, kind: .toolFinished(ToolStep(tool: tool, input: input), failed: false))
        case "PostToolUseFailure":
            return SessionNote(session: session, kind: .toolFinished(ToolStep(tool: tool, input: input), failed: true))
        case "Stop":
            let message = (payload["transcript_path"] as? String).flatMap(lastMessage)
            return SessionNote(session: session, kind: .stop(lastMessage: message.flatMap(SessionText.firstSentence)))
        case "Notification":
            guard let message = (payload["message"] as? String).flatMap({ SessionText.oneLine($0) }), !message.isEmpty else { return nil }
            return SessionNote(session: session, kind: .notification(message))
        case "SessionEnd":
            return SessionNote(session: session, kind: .ended)
        default:
            return nil
        }
    }
}

/// One item of Claude's todo list (the TodoWrite tool).
struct SessionTodo: Equatable, Sendable {
    enum State: String, Sendable { case pending, inProgress = "in_progress", completed }
    var text: String
    var state: State

    static func list(from input: [String: Any]) -> [SessionTodo]? {
        guard let items = input["todos"] as? [[String: Any]] else { return nil }
        return items.compactMap { item in
            let text = (item["activeForm"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? item["content"] as? String ?? ""
            guard let line = SessionText.oneLine(text), !line.isEmpty else { return nil }
            return SessionTodo(text: line, state: State(rawValue: item["status"] as? String ?? "") ?? .pending)
        }
    }
}

/// A tool run, said the way Yumi says it: "Modifie IslandModel.swift", "Lance swift test".
struct ToolStep: Equatable, Sendable {
    enum Kind: Equatable, Sendable { case edit, read, command, search, web, other }

    var tool: String
    var kind: Kind
    /// The file name, the command (secrets masked), the query.
    var target: String
    /// The full path of a file, to count the files touched.
    var path: String?

    init(tool: String, input: [String: Any]) {
        self.tool = tool
        let file = input["file_path"] as? String ?? input["notebook_path"] as? String ?? input["path"] as? String
            ?? input["absolute_path"] as? String
        // Claude Code's names first, then those of Codex, Gemini CLI and the others.
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch", "replace", "edit_file", "write_file": kind = .edit
        case "Read", "read_file", "read_many_files": kind = .read
        case "Bash", "shell", "exec_command", "local_shell", "run_shell_command": kind = .command
        case "Grep", "Glob", "LS", "glob", "grep", "search_file_content", "list_directory": kind = .search
        case "WebSearch", "WebFetch", "google_web_search", "web_search", "web_fetch": kind = .web
        default: kind = .other
        }
        if let command = input["command"] as? String {
            target = SessionText.oneLine(SecretMask.mask(command), limit: 60) ?? ""
        } else if let words = input["command"] as? [String] {
            // Codex gives the command as its words: ["bash", "-lc", "git status"].
            let command = ["bash", "zsh", "sh"].contains(words.first ?? "") ? (words.last ?? "") : words.joined(separator: " ")
            target = SessionText.oneLine(SecretMask.mask(command), limit: 60) ?? ""
        } else if let file {
            target = URL(fileURLWithPath: file).lastPathComponent
        } else if let query = (input["pattern"] ?? input["query"] ?? input["url"]) as? String {
            target = SessionText.oneLine(SecretMask.mask(query), limit: 50) ?? ""
        } else {
            target = ""
        }
        path = kind == .edit ? file : nil
    }

    /// "Modifie IslandModel.swift", "Lance swift test", "Cherche TODO".
    var sentence: String {
        let verb: String
        switch kind {
        case .edit:    verb = tool == "Write" || tool == "write_file" ? loc("Écrit") : loc("Modifie")
        case .read:    verb = loc("Lit")
        case .command: verb = loc("Lance")
        case .search:  verb = loc("Cherche")
        case .web:     verb = tool == "WebFetch" || tool == "web_fetch" ? loc("Lit la page") : loc("Cherche sur le web")
        case .other:   verb = tool
        }
        return target.isEmpty ? verb : "\(verb) \(target)"
    }
}

/// What the journal knows of one session.
struct SessionJournal: Equatable, Sendable {
    var request: String?
    var todos: [SessionTodo] = []
    var current: ToolStep?
    /// The last actions, newest last.
    var history: [ToolStep] = []
    var filesTouched: [String] = []
    var commands = 0
    var failures = 0
    var started: Date
    /// Set when a turn ends, cleared by the next request.
    var summary: String?
    var notification: String?

    static let historyLength = 12

    init(started: Date) { self.started = started }

    /// "3/7", nil without a list.
    var progress: String? {
        guard !todos.isEmpty else { return nil }
        return "\(todos.filter { $0.state == .completed }.count)/\(todos.count)"
    }

    /// The task Claude is on: the one in progress, or the next one to do.
    var currentTask: String? {
        (todos.first { $0.state == .inProgress } ?? todos.first { $0.state == .pending })?.text
    }

    mutating func apply(_ kind: SessionNote.Kind, now: Date) {
        switch kind {
        case .prompt(let text):
            // A new request: a new turn, with its own count
            self = SessionJournal(started: now)
            request = text
        case .toolStarted(let step):
            current = step
            notification = nil
        case .toolFinished(let step, let failed):
            if current?.tool == step.tool { current = nil }
            history.append(step)
            if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
            if let path = step.path, !filesTouched.contains(path) { filesTouched.append(path) }
            if step.kind == .command { commands += 1 }
            if failed { failures += 1 }
        case .todos(let list):
            todos = list
        case .stop(let message):
            current = nil
            summary = Self.summary(files: filesTouched.count, commands: commands, todos: todos, message: message)
        case .notification(let text):
            notification = text
        case .ended:
            current = nil
            if summary == nil { summary = Self.summary(files: filesTouched.count, commands: commands, todos: todos, message: nil) }
        }
    }

    /// "Deux fichiers modifiés, une commande, 5/5 tâches. J'ai ajouté le test."
    static func summary(files: Int, commands: Int, todos: [SessionTodo], message: String?) -> String {
        var parts: [String] = []
        if files > 0 { parts.append(FrenchText.spelledCount(files, loc("fichier modifié"), loc("fichiers modifiés"))) }
        if commands > 0 { parts.append(FrenchText.spelledCount(commands, loc("commande"), loc("commandes"), feminine: true)) }
        if !todos.isEmpty {
            parts.append(loc("\(todos.filter { $0.state == .completed }.count)/\(todos.count) tâches"))
        }
        var text = parts.isEmpty ? loc("Rien de modifié") : FrenchText.sentenceStart(parts.joined(separator: ", "))
        text += "."
        if let message, !message.isEmpty { text += " " + message }
        return text
    }

    /// The lines shown when the session is unfolded.
    func details(now: Date) -> [String] {
        var lines: [String] = []
        if let request { lines.append(loc("Demande : \(request)")) }
        if let task = currentTask, let progress { lines.append(loc("Tâche \(progress) : \(task)")) }
        if let summary { lines.append(summary) }
        for step in history.reversed() { lines.append("· " + step.sentence) }
        lines.append(loc("Depuis \(FrenchText.minutes(now.timeIntervalSince(started)))"))
        return lines
    }
}

/// Text cut for one line of the island.
enum SessionText {
    static func oneLine(_ text: String, limit: Int = 90) -> String? {
        let flat = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !flat.isEmpty else { return nil }
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        // At a word when there is one near the end
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit * 2 / 3 {
            return String(cut[..<space]) + "…"
        }
        return String(cut) + "…"
    }

    /// The first sentence of Claude's last message, at most one line.
    static func firstSentence(_ text: String) -> String? {
        guard let line = oneLine(SecretMask.mask(text), limit: 140) else { return nil }
        if let end = line.firstIndex(where: { ".!?".contains($0) }), line.distance(from: line.startIndex, to: end) > 10 {
            return String(line[...end])
        }
        return oneLine(line, limit: 100)
    }

    /// The last text Claude wrote, from the end of a transcript (JSON lines). Read on this Mac,
    /// never sent anywhere.
    static func lastAssistantText(transcript: String) -> String? {
        for line in transcript.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any] else { continue }
            if let text = message["content"] as? String, !text.isEmpty { return text }
            let parts = (message["content"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            if let text = parts.last, !text.isEmpty { return text }
        }
        return nil
    }

    /// The end of a transcript file: the last 64 KB are enough for the last message.
    static func readTail(_ path: String, bytes: Int = 65_536) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return (try? handle.readToEnd()).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Hides what looks like a secret in a command or a request before it is shown.
enum SecretMask {
    static let hidden = "•••"

    private static let patterns: [(String, String)] = [
        // KEY=value, API_TOKEN="value", password: value
        (#"(?i)\b([A-Z0-9_]*(?:KEY|TOKEN|SECRET|PASSWORD|PASSWD|PWD|CREDENTIALS?)[A-Z0-9_]*)(\s*[=:]\s*)("[^"]*"|'[^']*'|\S+)"#, "$1$2\(hidden)"),
        // --token value, --password=value, -p value for passwords is too common to guess: options named after secrets only
        (#"(?i)(--?(?:api-?key|token|secret|password|passwd|auth))(\s+|=)("[^"]*"|'[^']*'|\S+)"#, "$1$2\(hidden)"),
        // Authorization: Bearer …
        (#"(?i)(authorization:\s*(?:bearer|basic|token)\s+)[^\s'"]+"#, "$1\(hidden)"),
        // user:password@host in a URL
        (#"(://[^/\s:@]+:)[^@\s/]+@"#, "$1\(hidden)@"),
        // Well-known token shapes
        (#"\b(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abpr]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|ntn_[A-Za-z0-9]{20,}|secret_[A-Za-z0-9]{20,}|glpat-[A-Za-z0-9_-]{20,})\b"#, hidden),
    ]

    static func mask(_ text: String) -> String {
        var result = text
        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: template)
        }
        return result
    }
}

/// The journals of every session, fed by the hook server, read by the Claude Code module.
@MainActor
final class ClaudeSessionJournals {
    static let shared = ClaudeSessionJournals()

    private(set) var journals: [String: SessionJournal] = [:]
    /// Called after each change, by the module while it runs.
    var onChange: (@MainActor () -> Void)?

    func apply(_ note: SessionNote, now: Date = .now) {
        var journal = journals[note.session] ?? SessionJournal(started: now)
        journal.apply(note.kind, now: now)
        journals[note.session] = journal
        onChange?()
    }

    func journal(_ session: String) -> SessionJournal? { journals[session] }

    /// Journals of sessions gone from the list are dropped.
    func keep(only sessions: Set<String>) {
        journals = journals.filter { sessions.contains($0.key) }
    }
}
