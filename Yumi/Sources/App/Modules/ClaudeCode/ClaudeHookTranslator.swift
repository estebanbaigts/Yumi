import Foundation

/// Turns the JSON a coding agent's hook sends into `YumiEvent`s: Claude Code, Codex, Gemini
/// CLI and the others that speak the same hooks. This is the only place that knows the hook
/// format; everything after it works on typed events. Which agent sent it, Yumi sees by
/// himself (`AgentCatalog`).
enum ClaudeHookTranslator {
    /// The agent of a hook nothing else tells apart.
    static let agent = AgentCatalog.fallback.agent

    /// Gemini CLI's names for the same moments.
    private static let aliases = ["BeforeTool": "PreToolUse", "AfterTool": "PostToolUse",
                                  "BeforeAgent": "UserPromptSubmit", "AfterAgent": "Stop"]

    /// Events for one hook payload, in the order they must be applied.
    /// - Parameter requestID: identifier given to a `PermissionRequest`, so its answer can be routed back.
    static func events(for payload: [String: Any], requestID: String = UUID().uuidString) -> [YumiEvent] {
        let given = payload["hook_event_name"] as? String ?? ""
        let name = aliases[given] ?? given
        let agent = AgentCatalog.agent(forHook: payload).agent
        let id = SessionID(payload["session_id"] as? String ?? "unknown")

        if name == "SessionEnd" { return [.sessionEnded(id)] }

        var specific: [YumiEvent] = []
        switch name {
        case "SessionStart":
            break

        case "UserPromptSubmit":
            specific = [.promptSubmitted(id, text: payload["prompt"] as? String ?? "")]

        case "PreToolUse":
            specific = [.toolStarted(id, tool(from: payload))]

        case "PostToolUse":
            specific = [.toolFinished(id, tool(from: payload))]

        case "PostToolUseFailure":
            specific = [.toolFinished(id, tool(from: payload)), .activityNoted(id, loc("Échec"))]

        case "PermissionRequest":
            let tool = payload["tool_name"] as? String ?? "Tool"
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let command = input["command"] as? String ?? (input["command"] as? [String])?.joined(separator: " ") ?? tool
            specific = [.permissionRequested(id, PermissionRequest(id: requestID, tool: tool, command: command))]

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let lower = message.lowercased()
            if lower.contains("rate limit") || lower.contains("limite d") {
                specific = [.rateLimited(id)]
            } else if message.hasSuffix("?") {
                specific = [.questionRequested(id, Question(text: message))]
            }

        case "Stop":
            if let message = payload["message"] as? String, !message.isEmpty {
                specific = [.activityNoted(id, String(message.prefix(60)))]
            }
            specific.append(.taskCompleted(id))

        case "StopFailure":
            // Out of usage is not a bug of the session: it waits for its limit to come back
            let message = payload["message"] as? String ?? ""
            let kind = "\(payload["error"] ?? "") \(payload["error_type"] ?? "") \(message)".lowercased()
            if kind.contains("rate_limit") || kind.contains("rate limit") || kind.contains("usage limit")
                || kind.contains("limit reached") || kind.contains("limite d") {
                specific = [.rateLimited(id)]
            } else {
                specific = [.sessionErrored(id, YumiError(message: message))]
            }

        case "SubagentStart":
            specific = [.activityNoted(id, loc("Un sous-agent démarre"))]

        case "SubagentStop":
            specific = [.activityNoted(id, loc("Un sous-agent a fini"))]

        default:
            return []
        }

        // Every hook introduces its session: Yumi may have been launched after it started.
        // The store ignores a start it already knows.
        let cwd = payload["cwd"] as? String ?? ""
        let origin = SessionOrigin(workingDirectory: cwd,
                                   hostBundleID: payload["bundle_id"] as? String ?? "",
                                   hostName: payload["term_program"] as? String ?? "",
                                   tty: payload["tty"] as? String ?? "",
                                   terminalSessionID: itermSession(payload["iterm_session_id"] as? String ?? ""))
        return [.sessionStarted(id, agent, title: projectName(forDirectory: cwd)),
                .sessionLocated(id, origin)] + specific
    }

    /// Version of the reply protocol the hook script speaks. Scripts written before version 2
    /// do not send it and do not expect an acknowledgement.
    static func protocolVersion(of payload: [String: Any]) -> Int {
        payload["hook_protocol"] as? Int ?? 1
    }

    /// iTerm2 names a pane `w0t1p0:UUID`; its AppleScript knows it by the UUID alone.
    static func itermSession(_ value: String) -> String {
        String(value.split(separator: ":", maxSplits: 1).last ?? "")
    }

    static func projectName(forDirectory directory: String) -> String {
        let name = URL(fileURLWithPath: directory).lastPathComponent
        return directory.isEmpty || name.isEmpty || name == "/" ? "Session" : name
    }

    private static func tool(from payload: [String: Any]) -> ToolInfo {
        let name = payload["tool_name"] as? String ?? "Tool"
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        return ToolInfo(name: name, summary: detail(of: input))
    }

    /// The part of a tool input worth showing: the command, the file name or the query.
    private static func detail(of input: [String: Any]) -> String {
        if let command = input["command"] as? String {
            return String(command.prefix(40))
        } else if let command = input["command"] as? [String] {
            // Codex gives the command as its words: ["bash", "-lc", "git status"].
            let words = command.first == "bash" || command.first == "zsh" || command.first == "sh" ? Array(command.suffix(1)) : command
            return String(words.joined(separator: " ").prefix(40))
        } else if let path = input["path"] as? String {
            return URL(fileURLWithPath: path).lastPathComponent
        } else if let file = (input["file_path"] ?? input["absolute_path"]) as? String {
            return URL(fileURLWithPath: file).lastPathComponent
        } else if let query = input["query"] as? String {
            return String(query.prefix(40))
        }
        return ""
    }
}

/// The wording for the tools Claude Code runs, in the language Yumi speaks.
enum ClaudeToolPhrase {
    /// Computed each time: the words follow the language Yumi speaks.
    private static var labels: [String: String] {
        [
            "Bash":       loc("Exécute"),
            "Read":       loc("Lit"),
            "Write":      loc("Écrit"),
            "Edit":       loc("Modifie"),
            "Glob":       loc("Cherche"),
            "Grep":       loc("Recherche"),
            "WebSearch":  loc("Recherche web"),
            "WebFetch":   loc("Récupère"),
            "TodoWrite":  loc("Tâches"),
            "Task":       loc("Agent"),
            "LS":         loc("Liste"),
            "MultiEdit":  loc("Modifie"),
            "NotebookEdit": loc("Notebook"),
            // Codex, Gemini CLI and the others name the same tools their own way.
            "shell":             loc("Exécute"),
            "exec_command":      loc("Exécute"),
            "local_shell":       loc("Exécute"),
            "run_shell_command": loc("Exécute"),
            "apply_patch":       loc("Modifie"),
            "replace":           loc("Modifie"),
            "edit_file":         loc("Modifie"),
            "read_file":         loc("Lit"),
            "read_many_files":   loc("Lit"),
            "write_file":        loc("Écrit"),
            "list_directory":    loc("Liste"),
            "glob":              loc("Cherche"),
            "search_file_content": loc("Recherche"),
            "grep":              loc("Recherche"),
            "google_web_search": loc("Recherche web"),
            "web_search":        loc("Recherche web"),
            "web_fetch":         loc("Récupère"),
            "update_plan":       loc("Tâches"),
            "write_todos":       loc("Tâches"),
        ]
    }

    static func label(for tool: String) -> String { labels[tool] ?? tool }

    /// One line of the activity log: "Modifie · main.swift".
    static func step(_ tool: ToolInfo) -> String {
        let label = label(for: tool.name)
        return tool.summary.isEmpty ? label : "\(label) · \(tool.summary)"
    }

    /// The same, as the end of a sentence: "modifie main.swift".
    static func sentence(_ tool: ToolInfo) -> String {
        let label = label(for: tool.name)
        let lowered = label.prefix(1).lowercased() + label.dropFirst()
        return tool.summary.isEmpty ? lowered : "\(lowered) \(tool.summary)"
    }
}
