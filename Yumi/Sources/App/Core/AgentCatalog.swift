import Foundation

/// The AI agents and assistants Yumi knows, and how to tell which one is at work: from the
/// processes a hook was launched by, from where a session keeps its transcript, from the
/// names of the hook events, or from the application in front. Nobody tells Yumi which AI is
/// used: he sees it. Pure: values in, an agent out.
struct KnownAgent: Equatable, Sendable {
    let id: String
    /// "Claude Code", "Codex", "Gemini CLI", "ChatGPT".
    let name: String
    /// How Yumi calls it in a sentence: "Claude veut ton accord", "Codex modifie main.swift".
    let speaker: String
    let kind: AgentKind
    /// Executable names (the last part of the path) the agent runs as.
    var processes: [String] = []
    /// Words found in the arguments of a process run by an interpreter (node, bun, python).
    var scripts: [String] = []
    /// A folder of the home directory where the agent keeps its sessions: "/.codex/".
    var folder: String? = nil
    /// Applications of the agent, by bundle identifier.
    var bundleIDs: [String] = []

    var agent: Agent { Agent(id: AgentID(id), name: name, kind: kind) }
}

enum AgentCatalog {
    static let claudeCode = KnownAgent(id: "claude-code", name: "Claude Code", speaker: "Claude", kind: .coding,
                                       processes: ["claude"], scripts: ["claude-code", "@anthropic-ai/claude"], folder: "/.claude/")
    static let codex = KnownAgent(id: "codex", name: "Codex", speaker: "Codex", kind: .coding,
                                  processes: ["codex"], scripts: ["@openai/codex", "codex.js"], folder: "/.codex/",
                                  bundleIDs: ["com.openai.codex"])
    static let gemini = KnownAgent(id: "gemini-cli", name: "Gemini CLI", speaker: "Gemini", kind: .coding,
                                   processes: ["gemini"], scripts: ["@google/gemini-cli", "gemini-cli"], folder: "/.gemini/")
    static let cursor = KnownAgent(id: "cursor-agent", name: "Cursor", speaker: "Cursor", kind: .coding,
                                   processes: ["cursor-agent"], folder: "/.cursor/",
                                   bundleIDs: ["com.todesktop.230313mzl4w4u92"])
    static let copilot = KnownAgent(id: "copilot", name: "GitHub Copilot", speaker: "Copilot", kind: .coding,
                                    processes: ["copilot"], scripts: ["@github/copilot"], folder: "/.copilot/")
    static let opencode = KnownAgent(id: "opencode", name: "OpenCode", speaker: "OpenCode", kind: .coding,
                                     processes: ["opencode"], scripts: ["opencode-ai"], folder: "/opencode/")
    static let qwen = KnownAgent(id: "qwen-code", name: "Qwen Code", speaker: "Qwen", kind: .coding,
                                 processes: ["qwen"], scripts: ["@qwen-code/qwen-code"], folder: "/.qwen/")
    static let windsurf = KnownAgent(id: "windsurf", name: "Windsurf", speaker: "Windsurf", kind: .coding,
                                     bundleIDs: ["com.exafunction.windsurf"])

    // Assistants without hooks: Yumi only sees them in front.
    static let chatGPT = KnownAgent(id: "chatgpt", name: "ChatGPT", speaker: "ChatGPT", kind: .productivity,
                                    bundleIDs: ["com.openai.chat"])
    static let claudeApp = KnownAgent(id: "claude-app", name: "Claude", speaker: "Claude", kind: .productivity,
                                      bundleIDs: ["com.anthropic.claudefordesktop"])
    static let perplexity = KnownAgent(id: "perplexity", name: "Perplexity", speaker: "Perplexity", kind: .productivity,
                                       bundleIDs: ["ai.perplexity.mac"])
    static let geminiApp = KnownAgent(id: "gemini-app", name: "Gemini", speaker: "Gemini", kind: .productivity,
                                      bundleIDs: ["com.google.GeminiMacOS", "com.google.gemini"])
    static let copilotApp = KnownAgent(id: "copilot-app", name: "Copilot", speaker: "Copilot", kind: .productivity,
                                       bundleIDs: ["com.microsoft.copilot-mac"])

    /// The agents that run in a terminal and speak through hooks.
    static let hooked = [claudeCode, codex, gemini, cursor, copilot, opencode, qwen]
    static let all = hooked + [windsurf, chatGPT, claudeApp, perplexity, geminiApp, copilotApp]

    /// Before Yumi saw anything else, a hook was Claude Code's.
    static let fallback = claudeCode

    static func known(_ id: AgentID) -> KnownAgent? { all.first { $0.id == id.value } }

    /// How Yumi names the agent of a session in a sentence. Unknown: its name as given.
    static func speaker(of agent: Agent) -> String { known(agent.id)?.speaker ?? agent.name }

    /// Which agent sent a hook. In order of trust: the processes above the hook (the script
    /// lists them, nearest first), the folder of the transcript, the names of the events.
    static func agent(forHook payload: [String: Any]) -> KnownAgent {
        if let processes = payload["yumi_processes"] as? [String], let found = agent(forProcesses: processes) { return found }
        if let path = payload["transcript_path"] as? String, let found = agent(forPath: path) { return found }
        if let name = payload["hook_event_name"] as? String, geminiEvents.contains(name) { return gemini }
        return fallback
    }

    /// The nearest process that is a known agent. Each line is a command line: the executable,
    /// then its arguments (an interpreter's script says what it runs).
    static func agent(forProcesses processes: [String]) -> KnownAgent? {
        for line in processes {
            let words = line.split(separator: " ").map(String.init)
            guard let executable = words.first else { continue }
            let base = (executable as NSString).lastPathComponent.lowercased()
            if let found = hooked.first(where: { $0.processes.contains(base) }) { return found }
            let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3"]
            guard interpreters.contains(base) else { continue }
            let rest = words.dropFirst().joined(separator: " ").lowercased()
            if let found = hooked.first(where: { agent in
                agent.scripts.contains { rest.contains($0.lowercased()) }
                    || agent.processes.contains { rest.hasSuffix("/bin/\($0)") || rest.contains("/bin/\($0) ") }
            }) { return found }
        }
        return nil
    }

    /// The agent whose folder holds this path: "~/.codex/sessions/…" is Codex's.
    static func agent(forPath path: String) -> KnownAgent? {
        hooked.first { agent in agent.folder.map { path.contains($0) } ?? false }
    }

    /// The application in front, when it is an AI.
    static func agent(forBundleID bundleID: String?) -> KnownAgent? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return all.first { $0.bundleIDs.contains(bundleID) }
    }

    /// Gemini CLI names its hooks its own way.
    static let geminiEvents: Set<String> = ["BeforeTool", "AfterTool", "BeforeAgent", "AfterAgent", "BeforeModel", "AfterModel",
                                            "BeforeToolSelection", "PreCompress"]
}
