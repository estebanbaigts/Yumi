import Testing
import Foundation

// Yumi sees by himself which AI is at work: the processes above a hook, the folder of its
// transcript, the names of its events, or the application in front.

@Suite struct AgentCatalogTests {
    @Test func theNearestKnownProcessGivesTheAgent() {
        #expect(AgentCatalog.agent(forProcesses: ["/bin/zsh -c hook", "codex --full-auto", "-zsh"])?.id == "codex")
        #expect(AgentCatalog.agent(forProcesses: ["/opt/homebrew/bin/claude --resume"])?.id == "claude-code")
        #expect(AgentCatalog.agent(forProcesses: ["/Users/me/.local/bin/gemini"])?.id == "gemini-cli")
        #expect(AgentCatalog.agent(forProcesses: ["cursor-agent chat"])?.id == "cursor-agent")
        // Through an interpreter: the script says what runs.
        #expect(AgentCatalog.agent(forProcesses: ["node /usr/local/lib/node_modules/@openai/codex/bin/codex.js"])?.id == "codex")
        #expect(AgentCatalog.agent(forProcesses: ["node /opt/homebrew/bin/gemini"])?.id == "gemini-cli")
        #expect(AgentCatalog.agent(forProcesses: ["node /x/node_modules/@anthropic-ai/claude-code/cli.js"])?.id == "claude-code")
        // The nearest wins: Codex started from a Claude Code session is Codex.
        #expect(AgentCatalog.agent(forProcesses: ["codex exec", "claude"])?.id == "codex")
        #expect(AgentCatalog.agent(forProcesses: ["/bin/zsh", "login -fp me"]) == nil)
        #expect(AgentCatalog.agent(forProcesses: ["node server.js"]) == nil)
    }

    @Test func withoutProcessesTheTranscriptThenTheEventsSay() {
        #expect(AgentCatalog.agent(forHook: ["transcript_path": "/Users/me/.codex/sessions/2026/a.jsonl"]).id == "codex")
        #expect(AgentCatalog.agent(forHook: ["transcript_path": "/Users/me/.gemini/tmp/x/chat.json"]).id == "gemini-cli")
        #expect(AgentCatalog.agent(forHook: ["hook_event_name": "BeforeTool"]).id == "gemini-cli")
        #expect(AgentCatalog.agent(forHook: ["hook_event_name": "PreToolUse"]).id == "claude-code")
        // The processes come first.
        #expect(AgentCatalog.agent(forHook: ["yumi_processes": ["codex"], "transcript_path": "/Users/me/.claude/x.jsonl"]).id == "codex")
    }

    @Test func theAppInFrontWhenItIsAnAI() {
        #expect(AgentCatalog.agent(forBundleID: "com.openai.chat")?.name == "ChatGPT")
        #expect(AgentCatalog.agent(forBundleID: "com.anthropic.claudefordesktop")?.name == "Claude")
        #expect(AgentCatalog.agent(forBundleID: "com.apple.Safari") == nil)
        #expect(AgentCatalog.agent(forBundleID: nil) == nil)
    }

    @Test func eachAgentHasItsNameInASentence() {
        #expect(AgentCatalog.speaker(of: AgentCatalog.codex.agent) == "Codex")
        #expect(AgentCatalog.speaker(of: AgentCatalog.gemini.agent) == "Gemini")
        #expect(AgentCatalog.speaker(of: AgentCatalog.claudeCode.agent) == "Claude")
        #expect(AgentCatalog.speaker(of: Agent(id: AgentID("new"), name: "Nouveau", kind: .coding)) == "Nouveau")
    }
}

@Suite struct AgentHookTests {
    private func agent(of events: [YumiEvent]) -> Agent? {
        for event in events { if case .sessionStarted(_, let agent, _) = event { return agent } }
        return nil
    }

    private func started(_ events: [YumiEvent]) -> (String, String)? {
        guard case .toolStarted(_, let tool)? = events.last else { return nil }
        return (tool.name, tool.summary)
    }

    @Test func aCodexHookStartsACodexSession() {
        let events = ClaudeHookTranslator.events(for: ["hook_event_name": "PreToolUse", "session_id": "c", "cwd": "/dev/yumi",
                                                       "yumi_processes": ["/bin/sh -c hook", "codex"],
                                                       "tool_name": "shell", "tool_input": ["command": ["bash", "-lc", "git status"]]])
        #expect(agent(of: events)?.id.value == "codex")
        #expect(started(events).map { [$0.0, $0.1] } == ["shell", "git status"])
        #expect(ClaudeToolPhrase.label(for: "shell") == "Exécute")
    }

    @Test func geminiEventsAreReadAsTheSameMoments() {
        let base: [String: Any] = ["session_id": "g", "cwd": "/dev/site"]
        let before = ClaudeHookTranslator.events(for: base.merging(["hook_event_name": "BeforeTool", "tool_name": "read_file",
                                                                    "tool_input": ["absolute_path": "/dev/site/index.html"]]) { $1 })
        #expect(agent(of: before)?.id.value == "gemini-cli")
        #expect(started(before).map { [$0.0, $0.1] } == ["read_file", "index.html"])
        let after = ClaudeHookTranslator.events(for: base.merging(["hook_event_name": "AfterAgent"]) { $1 })
        #expect(after.last == .taskCompleted(SessionID("g")))
    }

    @Test func aCodexApprovalShowsItsCommand() {
        let events = ClaudeHookTranslator.events(for: ["hook_event_name": "PermissionRequest", "session_id": "c", "cwd": "/dev/yumi",
                                                       "yumi_processes": ["codex"], "tool_name": "shell",
                                                       "tool_input": ["command": ["rm", "-rf", "build"]]], requestID: "r")
        #expect(events.last == .permissionRequested(SessionID("c"), PermissionRequest(id: "r", tool: "shell", command: "rm -rf build")))
    }
}

@Suite struct AgentSentenceTests {
    private func session(_ agent: KnownAgent, _ events: [YumiEvent] = []) -> Session {
        var sessions = SessionReducer.apply(.sessionStarted(SessionID("s"), agent.agent, title: "yumi"), to: [:])
        for event in events { sessions = SessionReducer.apply(event, to: sessions) }
        return sessions[SessionID("s")]!
    }

    @Test func theAgentAtWorkIsNamed() {
        let codex = session(AgentCatalog.codex, [.promptSubmitted(SessionID("s"), text: "go")])
        #expect(ClaudeSessions.phrase(codex).hasPrefix("Codex "))
        let snapshot = ClaudeSessions.snapshot([codex])
        #expect(snapshot.name == "Codex")
    }

    @Test func severalAgentsGiveAgents() {
        var sessions = SessionReducer.apply(.sessionStarted(SessionID("a"), AgentCatalog.codex.agent, title: "a"), to: [:])
        sessions = SessionReducer.apply(.sessionStarted(SessionID("b"), AgentCatalog.gemini.agent, title: "b"), to: sessions)
        #expect(ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions)).name == "Agents")
        #expect(ClaudeSessions.snapshot([]).name == "Agents")
    }

}

@Suite struct AgentJournalTests {
    @Test func otherAgentsToolsAreSaidLikeClaudeCodes() {
        #expect(ToolStep(tool: "shell", input: ["command": ["bash", "-lc", "git status"]]).sentence == "Lance git status")
        #expect(ToolStep(tool: "apply_patch", input: ["path": "/a/main.swift"]).sentence == "Modifie main.swift")
        #expect(ToolStep(tool: "read_file", input: ["absolute_path": "/a/index.html"]).sentence == "Lit index.html")
        let note = SessionNote.from(["hook_event_name": "BeforeTool", "session_id": "g", "tool_name": "run_shell_command",
                                     "tool_input": ["command": "npm test"]])
        #expect(note?.kind == .toolStarted(ToolStep(tool: "run_shell_command", input: ["command": "npm test"])))
    }
}

@Suite struct ToolDetailTests {
    @Test func aLongCommandIsCutAtAWordWithSecretsMasked() {
        let long = ClaudeHookTranslator.short("git commit -m \"une très longue description du changement\"")
        #expect(long.hasSuffix("…") && long.count <= 41)
        #expect(!long.hasSuffix(" …"))
        #expect(ClaudeHookTranslator.short("export API_TOKEN=abcdef123456") == "export API_TOKEN=•••")
        #expect(ClaudeHookTranslator.short("npm test") == "npm test")
    }
}

@Suite struct AgentSessionRowsTests {
    private func session(_ id: String, _ agent: KnownAgent, cwd: String) -> Session {
        var sessions = SessionReducer.apply(.sessionStarted(SessionID(id), agent.agent, title: id), to: [:])
        sessions = SessionReducer.apply(.sessionLocated(SessionID(id), SessionOrigin(workingDirectory: cwd, hostBundleID: "", hostName: "")), to: sessions)
        return sessions[SessionID(id)]!
    }

    @Test func severalAgentsEachLineSaysWhose() {
        var board = SessionBoard()
        board.update([session("a", AgentCatalog.codex, cwd: "/dev/site"), session("b", AgentCatalog.gemini, cwd: "/dev/boulangerie")])
        #expect(Set(board.rows().map(\.title)) == ["site · Codex", "boulangerie · Gemini"])
    }

    @Test func oneAgentKeepsTheProjectAlone() {
        var board = SessionBoard()
        board.update([session("a", AgentCatalog.claudeCode, cwd: "/dev/site"), session("b", AgentCatalog.claudeCode, cwd: "/dev/api")])
        #expect(Set(board.rows().map(\.title)) == ["site", "api"])
    }
}
