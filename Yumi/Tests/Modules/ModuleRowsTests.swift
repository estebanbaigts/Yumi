import Testing
import Foundation

// The lists of the activity view: Claude Code sessions, GitHub pull requests and events.

@Suite struct SessionBoardTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func session(_ id: String, _ folder: String, recency: Int, _ change: (inout Session) -> Void = { _ in }) -> Session {
        var session = Session(id: SessionID(id), agent: ClaudeHookTranslator.agent, title: folder)
        session.origin = SessionOrigin(workingDirectory: "/Users/me/dev/\(folder)", hostBundleID: "com.mitchellh.ghostty", hostName: "ghostty")
        session.recency = recency
        session.isTurnActive = true
        change(&session)
        return session
    }

    @Test func sessionsWaitingForSomethingComeFirstApprovalBeforeAnswer() {
        let working = session("a", "yumi", recency: 9) { $0.activity = .working(ToolInfo(name: "Edit", summary: "main.swift")) }
        let asking = session("b", "site", recency: 2) { $0.activity = .asking(Question(text: "On garde ?")); $0.status = .waitingForUser }
        let approval = session("c", "api", recency: 1) {
            $0.activity = .requestingPermission(PermissionRequest(tool: "Bash", command: "rm -rf build")); $0.status = .waitingForUser
        }
        let failed = session("d", "blog", recency: 8) { $0.status = .errored; $0.isTurnActive = false }
        var board = SessionBoard()
        board.update([working, asking, approval, failed], now: start)
        let rows = board.rows(now: start)
        #expect(rows.map(\.title) == ["api", "site", "yumi", "blog"])
        #expect(rows.map(\.state) == [.waiting, .waiting, .busy, .failure])
        #expect(rows.map(\.label) == ["attend un accord", "attend ta réponse", "travaille", "en erreur"])
        #expect(rows[0].detail == "Demande Bash : rm -rf build")
        #expect(rows[1].detail == "On garde ?")
        #expect(rows[2].action == "a")
    }

    @Test func theClockStartsAgainWhenTheSessionChangesWhatItDoes() {
        var board = SessionBoard()
        let first = session("a", "yumi", recency: 1) { $0.activity = .working(ToolInfo(name: "Read", summary: "a.swift")) }
        board.update([first], now: start)
        var again = first
        again.recency = 2
        board.update([again], now: start.addingTimeInterval(30))
        #expect(board.rows().first?.date == start)
        var next = first
        next.activity = .working(ToolInfo(name: "Edit", summary: "b.swift"))
        board.update([next], now: start.addingTimeInterval(60))
        #expect(board.rows().first?.date == start.addingTimeInterval(60))
    }

    @Test func aFinishedSessionStaysAMomentThenLeaves() {
        var board = SessionBoard()
        let done = session("a", "yumi", recency: 1) { $0.status = .completed; $0.isTurnActive = false }
        board.update([done], now: start)
        #expect(board.rows(now: start.addingTimeInterval(60)).map(\.label) == ["terminée"])
        #expect(board.nextDeparture(now: start) == start.addingTimeInterval(SessionBoard.keepFinished))
        #expect(board.rows(now: start.addingTimeInterval(SessionBoard.keepFinished)).isEmpty)
        // Still completed in the store: it does not come back.
        board.update([done], now: start.addingTimeInterval(SessionBoard.keepFinished + 30))
        board.update([done], now: start.addingTimeInterval(SessionBoard.keepFinished + 40))
        #expect(board.rows(now: start.addingTimeInterval(SessionBoard.keepFinished + 40)).isEmpty)
        // A new prompt brings it back.
        var busy = done
        busy.status = .running
        busy.activity = .thinking
        busy.isTurnActive = true
        board.update([busy], now: start.addingTimeInterval(140))
        #expect(board.rows(now: start.addingTimeInterval(140)).map(\.label) == ["travaille"])
    }

    @Test func aClosedSessionIsShownFinishedThenLeaves() {
        var board = SessionBoard()
        board.update([session("a", "yumi", recency: 1) { $0.activity = .thinking }], now: start)
        board.update([], now: start.addingTimeInterval(10))
        let rows = board.rows(now: start.addingTimeInterval(20))
        #expect(rows.map(\.state) == [.success])
        #expect(rows.first?.date == start.addingTimeInterval(10))
        #expect(board.rows(now: start.addingTimeInterval(10 + SessionBoard.keepFinished)).isEmpty)
    }

    @Test func theFoldedIslandCountsTheSessionsAndNamesTheOneWaiting() {
        let approval = session("c", "api", recency: 3) {
            $0.activity = .requestingPermission(PermissionRequest(tool: "Bash")); $0.status = .waitingForUser
        }
        let working = session("a", "yumi", recency: 2) { $0.activity = .thinking }
        let other = session("b", "site", recency: 1) { $0.activity = .thinking }
        let waiting = ClaudeSessions.live([approval, working, other])
        #expect(waiting?.text == "3 sessions · accord sur api")
        #expect(waiting?.priority == ModuleLivePriority.attention)
        let busy = ClaudeSessions.live([working, other])
        #expect(busy?.text == "2 sessions")
        #expect(busy?.priority == ModuleLivePriority.ambient)
        #expect(ClaudeSessions.live([working]) == nil)
        #expect(ClaudeSessions.live([approval])?.text == "Claude veut ton accord sur api")
    }
}

private let pullsAnswer = """
[{"number":14,"title":"Le repli","html_url":"https://github.com/me/Yumi/pull/14","updated_at":"2026-10-02T09:00:00Z",
  "user":{"login":"lea"},"head":{"sha":"aaa"},"requested_reviewers":[{"login":"Me"}]},
 {"number":15,"title":"Les sons","html_url":"https://github.com/me/Yumi/pull/15","user":{"login":"me"},"head":{"sha":"bbb"},"requested_reviewers":[]}]
"""

@Suite struct GitHubBoardTests {
    @Test func pullRequestsAreReadWithTheirAuthorAndWhoMustReview() {
        let pulls = GitHubFeed.pulls(from: Data(pullsAnswer.utf8), repo: "me/Yumi", login: "me")
        #expect(pulls.map(\.number) == [14, 15])
        #expect(pulls[0].author == "lea")
        #expect(pulls[0].sha == "aaa")
        #expect(pulls[0].asksMyReview)
        #expect(!pulls[1].asksMyReview)
        #expect(pulls[0].updated != nil)
    }

    @Test func checksAreRedAsSoonAsOneFailsRunningWhileOneRunsGreenOtherwise() {
        func checks(_ runs: String) -> GitHubChecks? { GitHubFeed.checks(from: Data(#"{"total_count":2,"check_runs":[\#(runs)]}"#.utf8)) }
        #expect(checks(#"{"status":"completed","conclusion":"success"},{"status":"in_progress","conclusion":null}"#) == .running)
        #expect(checks(#"{"status":"completed","conclusion":"failure"},{"status":"queued"}"#) == .failed)
        #expect(checks(#"{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"skipped"}"#) == .passed)
        #expect(checks("") == nil)
    }

    @Test func rowsGoByRepositoryReviewFirstThenRedThenEvents() {
        var red = GitHubPull(repo: "me/Yumi", number: 3, title: "Casse", author: "me", sha: "c", url: URL(string: "https://github.com/me/Yumi/pull/3"))
        red.checks = .failed
        var review = GitHubPull(repo: "me/Yumi", number: 2, title: "À relire", author: "lea", sha: "d", url: nil, asksMyReview: true)
        review.checks = .passed
        var green = GitHubPull(repo: "me/site", number: 9, title: "Vert", author: "me", sha: "e", url: nil)
        green.checks = .passed
        let star = GitHubEvent(id: 7, kind: .star, repo: "me/Yumi", actor: "louis", url: URL(string: "https://github.com/me/Yumi"),
                               date: Date(timeIntervalSince1970: 5))
        let rows = GitHubBoard.rows(pulls: [red, review, green], recent: [star])
        #expect(rows.map(\.title) == ["À relire", "Casse", "Vert", "Une étoile"])
        #expect(rows.map(\.label) == ["ta review", "CI rouge", "CI verte", "star"])
        #expect(rows.map(\.state) == [.waiting, .failure, .success, .neutral])
        #expect(rows.map(\.section) == ["me/Yumi", nil, "me/site", "Derniers événements"])
        #expect(rows[1].action == "https://github.com/me/Yumi/pull/3")
        #expect(rows[3].date == Date(timeIntervalSince1970: 5))
    }

    @Test func onlyChecksThatTurnRedAreNews() {
        var before = GitHubPull(repo: "me/Yumi", number: 3, title: "Casse", author: "me", sha: "c", url: nil)
        before.checks = .running
        var after = before
        after.checks = .failed
        #expect(GitHubBoard.turnedRed(before: [before], after: [after]).map(\.number) == [3])
        #expect(GitHubBoard.turnedRed(before: nil, after: [after]).isEmpty)
        #expect(GitHubBoard.turnedRed(before: [after], after: [after]).isEmpty)
    }

    @Test func redChecksPutGitHubInFrontOfTheFoldedIsland() {
        var red = GitHubPull(repo: "me/Yumi", number: 3, title: "Casse", author: "me", sha: "c", url: nil)
        red.checks = .failed
        let snapshot = GitHubSummary.snapshot(connection: .connected, repo: nil, openPulls: nil, last: nil, review: nil,
                                              pulls: [red], red: red)
        #expect(snapshot.live?.text == "CI rouge : Casse")
        #expect(snapshot.live?.priority == ModuleLivePriority.attention)
        #expect(snapshot.needsAttention)
        #expect(snapshot.rows.count == 1)
    }

    @Test func eventsKeepTheirTime() {
        let feed = #"[{"id":"9","type":"ForkEvent","actor":{"login":"o"},"repo":{"name":"me/Yumi"},"payload":{},"created_at":"2026-10-02T09:04:00Z"}]"#
        let events = GitHubFeed.events(from: Data(feed.utf8), login: "me", received: true)
        #expect(events.first?.date == (try? Date("2026-10-02T09:04:00Z", strategy: .iso8601)))
    }
}
