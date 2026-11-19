import Foundation
import Testing

// yumi/github-pages: the island's GitHub view in three pages, one at a time.

@Suite struct GitHubPagesTests {
    private func defaults() -> UserDefaults {
        let name = "GitHubPagesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func threePagesInOrder() {
        #expect(GitHubPage.allCases == [.activity, .recent, .pulls, .repos])
        #expect(GitHubPage.pulls.rowsKey == "pulls")
        #expect(GitHubPage.activity.rowsKey == nil)
        #expect(GitHubPage.recent.rowsKey == "recent")
        #expect(GitHubPage.repos.rowsKey == "repos")
    }

    @Test func movingStopsAtTheEnds() {
        #expect(GitHubPage.activity.moved(by: 1) == .recent)
        #expect(GitHubPage.recent.moved(by: 1) == .pulls)
        #expect(GitHubPage.pulls.moved(by: 1) == .repos)
        #expect(GitHubPage.repos.moved(by: 1) == .repos)
        #expect(GitHubPage.repos.moved(by: -1) == .pulls)
        #expect(GitHubPage.activity.moved(by: -1) == .activity)
        #expect(GitHubPage.activity.moved(by: 5) == .repos)
        #expect(!GitHubPage.activity.hasPrevious && GitHubPage.activity.hasNext)
        #expect(GitHubPage.repos.hasPrevious && !GitHubPage.repos.hasNext)
    }

    @Test func thePageIsRemembered() {
        let store = defaults()
        #expect(GitHubPage.stored(in: store) == .activity)
        GitHubPage.repos.store(in: store)
        #expect(GitHubPage.stored(in: store) == .repos)
        store.set(42, forKey: GitHubPage.storageKey)
        #expect(GitHubPage.stored(in: store) == .activity)
    }

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func push(_ id: Int64, _ repo: String, ago: TimeInterval, commits: [String], total: Int? = nil) -> GitHubPush {
        GitHubPush(eventID: id, repo: repo, branch: "main", actor: "me", date: now.addingTimeInterval(-ago),
                   total: total ?? commits.count,
                   commits: commits.map { GitHubCommit(sha: "\($0)0000000", message: "fix \($0)", author: "me",
                                                       url: URL(string: "https://github.com/\(repo)/commit/\($0)")) })
    }

    @Test func recentMixesRepositoriesNewestFirst() {
        let pushes = [push(1, "me/a", ago: 7200, commits: ["a1"]),
                      push(3, "me/b", ago: 60, commits: ["b2", "b1"]),
                      push(2, "me/hidden", ago: 600, commits: ["h1"])]
        let rows = GitHubPages.recent(pushes: pushes, hidden: ["me/hidden"])
        #expect(rows.map(\.title) == ["fix b2", "fix b1", "fix a1"])
        #expect(rows[0].detail == "b · main")
        #expect(rows[0].action == "https://github.com/me/b/commit/b2")
        #expect(rows[0].date == now.addingTimeInterval(-60))
        #expect(GitHubPages.recent(pushes: pushes, hidden: [], limit: 2).count == 2)
    }

    @Test func reposCountCommitsPullsAndChecks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let pushes = [push(1, "me/a", ago: 60, commits: ["a1"], total: 2),
                      push(2, "me/a", ago: 3 * 86_400, commits: ["a2"], total: 3)]
        let pulls = [GitHubPull(repo: "me/b", number: 4, title: "x", author: "me", sha: "s", url: nil, checks: .failed),
                     GitHubPull(repo: "me/b", number: 5, title: "y", author: "me", sha: "t", url: nil, checks: .passed)]
        let rows = GitHubPages.repos(followed: ["me/b", "me/c"], pushes: pushes, pulls: pulls, hidden: ["me/c"],
                                     now: now, calendar: calendar)
        #expect(rows.map(\.title) == ["b", "a"])
        #expect(rows[0].state == .failure)
        #expect(rows[0].action == "yumi-repo:me/b")
        #expect(rows[1].state == .neutral)
        #expect(rows[1].detail.contains("5"))
    }

    @Test func anOpenedRepositoryListsItsLatestPushesWithTheirCommitsAndFiles() {
        var pushes = (1...7).map { push(Int64($0), "me/a", ago: Double(100 * (8 - $0)), commits: ["c\($0)"]) }
        pushes[6].files = [GitHubFile(name: "Sources/App.swift", additions: 12, deletions: 3)]
        pushes[6].head = "abc"
        pushes[6].before = "def"
        pushes[6].total = 3
        pushes.append(push(9, "me/other", ago: 1, commits: ["o1"]))
        let rows = GitHubPages.repo("me/a", pushes: pushes, loading: false)
        #expect(rows.first?.action == GitHubPages.backAction)
        #expect(rows.count == 1 + GitHubPages.repoPushes)
        #expect(rows[1].id == "repo-push-7")
        #expect(rows[1].details == ["fix c7 (c700000)", "· et 2 de plus", "· Sources/App.swift  +12 −3"])
        #expect(rows[1].action == "https://github.com/me/a/compare/def...abc")
        #expect(rows[1].actionLabel == "Ouvrir sur GitHub")
        #expect(rows[2].action == "https://github.com/me/a/commits/main")
    }

    @Test func anOpenedRepositoryWithoutPushesSaysSo() {
        #expect(GitHubPages.repo("me/a", pushes: [], loading: true).last?.title == "Je regarde…")
        #expect(GitHubPages.repo("me/a", pushes: [], loading: false).last?.title == "Aucun push récent.")
    }
}

@Suite struct GitHubMergeCountTests {
    @Test func aMergeIsNotCountedTwice() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var merge = GitHubPush(eventID: 2, repo: "me/a", branch: "main", actor: "me", date: now, total: 3, commits: [])
        merge.merge = true
        let pushes = [GitHubPush(eventID: 1, repo: "me/a", branch: "feat", actor: "me", date: now, total: 3, commits: []), merge]
        #expect(GitHubActivity.counts(pushes, now: now, calendar: .current)["me/a"]?.today == 3)
        #expect(merge.title == "PR fusionnée sur main")
    }

    @Test func pullRequestsAskingMyReviewComeFirst() {
        let pulls = [GitHubPull(repo: "me/a", number: 1, title: "Vieille", author: "lea", sha: "1", checks: .passed),
                     GitHubPull(repo: "me/a", number: 2, title: "Rouge", author: "sam", sha: "2", checks: .failed),
                     GitHubPull(repo: "me/b", number: 3, title: "À relire", author: "lea", sha: "3", asksMyReview: true),
                     GitHubPull(repo: "me/hidden", number: 4, title: "Cachée", author: "x", sha: "4")]
        let rows = GitHubPages.pulls(pulls, hidden: ["me/hidden"])
        #expect(rows.map(\.title) == ["#3 · À relire", "#2 · Rouge", "#1 · Vieille"])
        #expect(rows.map(\.state) == [.waiting, .failure, .success])
        #expect(rows[0].detail == "b · lea")
        #expect(rows[0].action == "https://github.com/me/b/pull/3")
    }

    @Test func recentLinesAreGroupedByDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let hour: TimeInterval = 3600
        let rows = [now - hour, now - 2 * hour, now - 26 * hour].enumerated().map { index, date in
            ModuleRow(id: "\(index)", title: "c\(index)", detail: "", state: .busy, label: "", date: date)
        }
        let days = GitHubPages.days(rows, now: now, calendar: calendar)
        #expect(days[0].section == "Aujourd'hui")
        #expect(days[1].section == nil)
        #expect(days[2].section == "Hier")
    }
}
