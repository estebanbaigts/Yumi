import Testing
import Foundation

@Suite struct SessionHostTests {
    private let desktop = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.anthropic.claudefordesktop")
    private let terminal = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.apple.Terminal", hostName: "Apple_Terminal")
    private let code = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.microsoft.VSCode", hostName: "vscode")

    @Test func kinds() {
        #expect(SessionHost.kind(of: terminal) == .terminal)
        #expect(SessionHost.kind(of: SessionOrigin(hostName: "ghostty")) == .terminal)
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "com.unknown.term", hostName: "SomeTerm")) == .terminal)
        #expect(SessionHost.kind(of: code) == .editor)
        #expect(SessionHost.kind(of: desktop) == .other)
        #expect(SessionHost.kind(of: SessionOrigin(hostName: "tmux")) == nil)
        #expect(SessionHost.kind(of: nil) == nil)
    }

    @Test func theSecondButtonNamesWhatItOpens() {
        func second(_ origin: SessionOrigin) -> String? {
            var sessions = SessionReducer.apply(.sessionStarted(SessionID("s"), ClaudeHookTranslator.agent, title: "yumi"), to: [:])
            sessions = SessionReducer.apply(.sessionLocated(SessionID("s"), origin), to: sessions)
            return ClaudeSessions.snapshot(ClaudeSessions.ordered(sessions)).secondaryAction
        }
        #expect(second(terminal) == "Ouvrir Terminal")
        #expect(second(SessionOrigin(hostName: "iTerm.app")) == "Ouvrir iTerm2")
        #expect(second(SessionOrigin(hostName: "ghostty")) == "Ouvrir Ghostty")
        #expect(second(code) == "Ouvrir VS Code")
        #expect(second(desktop) == "Ouvrir Claude")
        // A host Yumi cannot name keeps the generic button
        #expect(second(SessionOrigin(hostBundleID: "com.example.not-installed", hostName: "SomeTerm")) == "Ouvrir le terminal")
        #expect(second(SessionOrigin(workingDirectory: "/dev/yumi")) == nil)
    }

    @Test func cursorIsAnEditorByItsRealIdentifier() {
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "com.todesktop.230313mzl4w4u92")) == .editor)
    }

    @Test func antigravityAndKiroAreEditors() {
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "com.google.antigravity", hostName: "vscode")) == .editor)
        #expect(SessionHost.appName(for: SessionOrigin(hostBundleID: "com.google.antigravity")) == "Antigravity")
        #expect(SessionHost.kind(of: SessionOrigin(hostBundleID: "dev.kiro.desktop")) == .editor)
    }

    @Test func aDroppedPathIsQuotedForTheShell() {
        #expect(TerminalTab.shellQuoted("/Users/me/My file.png") == "'/Users/me/My file.png'")
        #expect(TerminalTab.shellQuoted("/tmp/it's.txt") == "'/tmp/it'\\''s.txt'")
    }

    @Test func onlyITermCanTypeIntoASession() {
        let iTerm = SessionOrigin(hostBundleID: TerminalTab.iTerm, tty: "/dev/ttys004")
        let script = TerminalTab.typeScript("'/a \"b\".txt' ", for: iTerm, bundleID: TerminalTab.iTerm)
        #expect(script?.contains(#"write text "'/a \"b\".txt' " newline no"#) == true)
        #expect(TerminalTab.typeScript("x", for: SessionOrigin(tty: "/dev/ttys004"), bundleID: TerminalTab.terminal) == nil)
        #expect(TerminalTab.typeScript("x", for: SessionOrigin(), bundleID: TerminalTab.iTerm) == nil)
    }
}

@MainActor
@Suite struct ClaudeCodeVoirTests {
    @Test func withoutASessionOrWithAnApprovalPendingVoirOpensTheIsland() {
        var shown = 0
        let module = ClaudeCodeModule(onShow: { shown += 1 })
        module.start {}
        module.perform(.primary)
        #expect(shown == 1)

        // A session whose host is unknown: nowhere to go but the island.
        let id = SessionID("a")
        var sessions = SessionReducer.apply(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        module.receive(.sessionStarted(id, ClaudeHookTranslator.agent, title: "yumi"), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 2)

        // An approval pending, even with a known host: it is answered in the island.
        let origin = SessionOrigin(workingDirectory: "/dev/yumi", hostBundleID: "com.example.not-installed")
        let request = PermissionRequest(tool: "Bash", command: "ls")
        sessions = SessionReducer.apply(.sessionLocated(id, origin), to: sessions)
        sessions = SessionReducer.apply(.permissionRequested(id, request), to: sessions)
        module.receive(.permissionRequested(id, request), sessions: sessions)
        module.perform(.primary)
        #expect(shown == 3)
    }

    @Test func anApplicationThatIsNotInstalledCannotBeBroughtForward() {
        #expect(!ClaudeCodeModule.bringToFront(SessionOrigin(hostBundleID: "com.example.not-installed")))
        #expect(!ClaudeCodeModule.bringToFront(nil))
    }
}

@Suite struct TerminalTabTests {
    @Test func theHookSaysWhichTabTheSessionRunsIn() {
        let events = ClaudeHookTranslator.events(for: [
            "hook_event_name": "UserPromptSubmit", "session_id": "s", "cwd": "/dev/yumi",
            "term_program": "iTerm.app", "bundle_id": "com.googlecode.iterm2",
            "tty": "/dev/ttys029", "iterm_session_id": "w0t9p0:5EA8CE8A-6833-4935-9CED-65F56FF8BF1D",
        ])
        let origin = events.compactMap { event -> SessionOrigin? in
            if case .sessionLocated(_, let origin) = event { return origin }
            return nil
        }.first
        #expect(origin?.tty == "/dev/ttys029")
        #expect(origin?.terminalSessionID == "5EA8CE8A-6833-4935-9CED-65F56FF8BF1D")
    }

    @Test func aSessionLineNamesTheApplicationItOpens() {
        var sessions = SessionReducer.apply(.sessionStarted(SessionID("s"), ClaudeHookTranslator.agent, title: "yumi"), to: [:])
        sessions = SessionReducer.apply(.sessionLocated(SessionID("s"), SessionOrigin(hostBundleID: "com.googlecode.iterm2", hostName: "iTerm.app")), to: sessions)
        var board = SessionBoard()
        board.update(Array(sessions.values))
        #expect(board.rows().first?.actionLabel == "Ouvrir iTerm2")
    }

    @Test func iTermFindsThePaneByItsIdentifierOrItsTTY() throws {
        let origin = SessionOrigin(tty: "/dev/ttys029", terminalSessionID: "5EA8CE8A-6833")
        let script = try #require(TerminalTab.script(for: origin, bundleID: TerminalTab.iTerm))
        #expect(script.contains("unique id of s is \"5EA8CE8A-6833\" or tty of s is \"/dev/ttys029\""))
        #expect(script.contains("select t"))
    }

    @Test func terminalFindsTheTabByItsTTY() throws {
        let script = try #require(TerminalTab.script(for: SessionOrigin(tty: "/dev/ttys004"), bundleID: TerminalTab.terminal))
        #expect(script.contains("tty of t is \"/dev/ttys004\""))
        #expect(script.contains("set selected tab of w to t"))
    }

    @Test func nothingToAskWithoutATabOrAnotherTerminal() {
        #expect(TerminalTab.script(for: SessionOrigin(), bundleID: TerminalTab.terminal) == nil)
        #expect(TerminalTab.script(for: SessionOrigin(), bundleID: TerminalTab.iTerm) == nil)
        #expect(TerminalTab.script(for: SessionOrigin(tty: "/dev/ttys004"), bundleID: "com.mitchellh.ghostty") == nil)
    }

    @Test func aValueThatIsNotATTYNeverReachesTheScript() {
        let origin = SessionOrigin(tty: "/dev/ttys004\" then do shell script \"rm")
        #expect(TerminalTab.script(for: origin, bundleID: TerminalTab.terminal) == nil)
    }
}
