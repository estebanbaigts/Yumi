import Testing
import Foundation

// Yumi's hooks in Codex's ~/.codex/hooks.json and Gemini CLI's ~/.gemini/settings.json: the
// same merge as Claude Code's, the person's own hooks and settings left as they were.

@Suite struct AgentHooksTests {
    private let command = #""/Users/me/Library/Application Support/Yumi/yumi-hook""#
    private func isOwn(_ text: String) -> Bool { text == command }

    private func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func hooks(_ data: Data, _ event: String) -> [[String: Any]] {
        let matchers = (object(data)["hooks"] as? [String: Any])?[event] as? [[String: Any]] ?? []
        return matchers.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    /// A Gemini CLI settings file like a real one: its own settings, and another tool's hooks.
    private let gemini = #"""
    {"security": {"auth": {"selectedType": "oauth-personal"}},
     "hooks": {
       "BeforeTool": [{"matcher": "^run_shell_command$", "hooks": [{"name": "other", "type": "command", "command": "other hook", "timeout": 5000}]}],
       "AfterAgent": [{"hooks": [{"name": "other-end", "type": "command", "command": "other end", "timeout": 30000}]}]
     }}
    """#

    @Test func geminiGetsItsEventsInMillisecondsAndKeepsEverythingElse() throws {
        let merged = try HookSettings.merge(Data(gemini.utf8), command: command, events: HookTarget.gemini.pairs,
                                            isOwn: isOwn, isLegacy: { _ in false }).data
        // Every event of Gemini CLI, with a timeout in milliseconds.
        for event in HookTarget.gemini.events {
            let own = hooks(merged, event.name).filter { $0["command"] as? String == command }
            #expect(own.count == 1, "\(event.name)")
            #expect(own.first?["timeout"] as? Int == 10_000)
        }
        // The other tool's hooks and the person's settings are still there.
        #expect(hooks(merged, "BeforeTool").contains { $0["command"] as? String == "other hook" && $0["timeout"] as? Int == 5000 })
        #expect(hooks(merged, "AfterAgent").contains { $0["command"] as? String == "other end" })
        #expect((object(merged)["security"] as? [String: Any])?["auth"] != nil)
        // No Claude Code event in Gemini's file.
        #expect(hooks(merged, "PreToolUse").isEmpty && hooks(merged, "PermissionRequest").isEmpty)
    }

    @Test func installingTwiceGivesTheSameFile() throws {
        let once = try HookSettings.merge(Data(gemini.utf8), command: command, events: HookTarget.gemini.pairs,
                                          isOwn: isOwn, isLegacy: { _ in false }).data
        let twice = try HookSettings.merge(once, command: command, events: HookTarget.gemini.pairs,
                                           isOwn: isOwn, isLegacy: { _ in false }).data
        #expect(once == twice)
    }

    @Test func codexGetsTheClaudeStyleEventsInSeconds() throws {
        let merged = try HookSettings.merge(nil, command: command, events: HookTarget.codex.pairs,
                                            isOwn: isOwn, isLegacy: { _ in false }).data
        #expect(hooks(merged, "PermissionRequest").first?["timeout"] as? Int == 120)
        #expect(hooks(merged, "PreToolUse").first?["timeout"] as? Int == 10)
        #expect(HookSettings.installed(merged, event: HookTarget.codex.marker, isOwn: isOwn))
        #expect(!HookSettings.installed(nil, event: HookTarget.codex.marker, isOwn: isOwn))
        #expect(!HookSettings.installed(Data("not json".utf8), event: "SessionStart", isOwn: isOwn))
    }

    @Test func removingLeavesOnlyWhatWasThere() throws {
        let merged = try HookSettings.merge(Data(gemini.utf8), command: command, events: HookTarget.gemini.pairs,
                                            isOwn: isOwn, isLegacy: { _ in false }).data
        let removed = try #require(try HookSettings.removing(merged, isOwn: isOwn))
        #expect(!HookSettings.installed(removed, event: "SessionStart", isOwn: isOwn))
        #expect(hooks(removed, "SessionStart").isEmpty)
        #expect(hooks(removed, "BeforeTool").count == 1 && hooks(removed, "AfterAgent").count == 1)
        // Nothing of Yumi's left: nothing to write.
        #expect(try HookSettings.removing(removed, isOwn: isOwn) == nil)
        #expect(throws: HookSettings.Problem.notJSON) { try HookSettings.removing(Data("{oops".utf8), isOwn: isOwn) }
    }

    @Test func theBackupIsNamedAfterTheFile() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let codex = HookSettings.backupURL(for: URL(fileURLWithPath: "/Users/me/.codex/hooks.json"), now: now) { _ in false }
        #expect(codex.lastPathComponent.hasPrefix("hooks.json.bak-"))
        #expect(codex.deletingLastPathComponent().path == "/Users/me/.codex")
    }

    @Test func eachAgentHasItsFile() {
        #expect(HookTarget.codex.shownPath == "~/.codex/hooks.json")
        #expect(HookTarget.gemini.url(home: URL(fileURLWithPath: "/Users/me")).path == "/Users/me/.gemini/settings.json")
        #expect(HookTarget.claudeCode.pairs.count == 12)
    }
}
