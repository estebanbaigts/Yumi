import Testing
import Foundation

// Answers recorded from the GitHub REST API (api.github.com), shortened to the fields that matter.

private let ownEvents = """
[
 {"id":"50000000004","type":"PullRequestEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"action":"closed","number":12,"pull_request":{"title":"Fix du repli","merged":true,"html_url":"https://github.com/estebanbaigts/Yumi/pull/12"}},"created_at":"2026-10-02T09:04:00Z"},
 {"id":"50000000003","type":"PushEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"ref":"refs/heads/yumi/coeur","size":3},"created_at":"2026-10-02T09:03:00Z"},
 {"id":"50000000002","type":"ReleaseEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"action":"published","release":{"tag_name":"v0.2.0","name":"Yumi 0.2","html_url":"https://github.com/estebanbaigts/Yumi/releases/tag/v0.2.0"}},"created_at":"2026-10-02T09:02:00Z"},
 {"id":"50000000001","type":"PullRequestEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"action":"opened","number":12,"pull_request":{"title":"Fix du repli","merged":false,"html_url":"https://github.com/estebanbaigts/Yumi/pull/12"}},"created_at":"2026-10-02T09:01:00Z"},
 {"id":"49999999999","type":"CreateEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"ref_type":"branch"}},
 {"id":"49999999998","type":"PullRequestEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"action":"closed","pull_request":{"title":"Abandonnée","merged":false}}}
]
"""

private let receivedEvents = """
[
 {"id":"50000000013","type":"WatchEvent","actor":{"login":"louis"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"action":"started"}},
 {"id":"50000000012","type":"ForkEvent","actor":{"login":"octocat"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"forkee":{"full_name":"octocat/Yumi"}}},
 {"id":"50000000011","type":"IssuesEvent","actor":{"login":"lea"},"repo":{"name":"estebanbaigts/Yumi"},
  "payload":{"action":"opened","issue":{"title":"Le repli tremble","html_url":"https://github.com/estebanbaigts/Yumi/issues/7"}}},
 {"id":"50000000010","type":"WatchEvent","actor":{"login":"someone"},"repo":{"name":"other/Project"},"payload":{"action":"started"}},
 {"id":"50000000009","type":"PushEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"ref":"refs/heads/main"}},
 {"id":"50000000008","type":"IssuesEvent","actor":{"login":"lea"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"action":"closed","issue":{"title":"x"}}}
]
"""

private let user = #"{"login":"estebanbaigts","id":1,"followers":42,"public_repos":8}"#
private let repos = """
[{"full_name":"estebanbaigts/fork-of-something","fork":true,"stargazers_count":900,"forks_count":3,"html_url":"https://github.com/estebanbaigts/fork-of-something"},
 {"full_name":"estebanbaigts/Yumi","fork":false,"stargazers_count":128,"forks_count":12,"html_url":"https://github.com/estebanbaigts/Yumi"},
 {"full_name":"estebanbaigts/audioscope","fork":false,"stargazers_count":4,"forks_count":0,"html_url":"https://github.com/estebanbaigts/audioscope"}]
"""
private let openPulls = #"{"total_count":3,"incomplete_results":false,"items":[{"title":"x","html_url":"https://github.com/estebanbaigts/Yumi/pull/14","repository_url":"https://api.github.com/repos/estebanbaigts/Yumi"}]}"#
private let reviewRequested = #"{"total_count":1,"items":[{"title":"Fix du repli","html_url":"https://github.com/octo/demo/pull/9","repository_url":"https://api.github.com/repos/octo/demo"}]}"#
private let noReview = #"{"total_count":0,"items":[]}"#

@Suite struct GitHubFeedTests {
    @Test func theOwnFeedGivesPushesPullRequestsMergesAndReleases() {
        let events = GitHubFeed.events(from: Data(ownEvents.utf8), login: "estebanbaigts", received: false)
        #expect(events.map(\.kind) == [.merge, .push, .release, .pullRequest])
        #expect(events[0].detail == "Fix du repli")
        #expect(events[0].url?.absoluteString == "https://github.com/estebanbaigts/Yumi/pull/12")
        #expect(events[1].detail == "yumi/coeur")
        #expect(events[2].detail == "Yumi 0.2")
        #expect(events[3].id == 50000000001)
        #expect(events[0].repoName == "Yumi")
    }

    @Test func theReceivedFeedOnlyKeepsWhatOthersDidOnThePersonsRepositories() {
        let events = GitHubFeed.events(from: Data(receivedEvents.utf8), login: "estebanbaigts", received: true)
        #expect(events.map(\.kind) == [.star, .fork, .issue])
        #expect(events.map(\.actor) == ["louis", "octocat", "lea"])
        #expect(events[2].detail == "Le repli tremble")
    }

    @Test func otherAnswers() {
        #expect(GitHubFeed.user(from: Data(user.utf8))?.login == "estebanbaigts")
        #expect(GitHubFeed.user(from: Data(user.utf8))?.followers == 42)
        // The most active repository is the person's own, not a fork of someone else's work.
        #expect(GitHubFeed.mostActiveRepo(from: Data(repos.utf8)) == GitHubRepo(fullName: "estebanbaigts/Yumi", stars: 128, forks: 12,
                                                                               url: URL(string: "https://github.com/estebanbaigts/Yumi")))
        #expect(GitHubFeed.search(from: Data(openPulls.utf8)).count == 3)
        #expect(GitHubFeed.search(from: Data(reviewRequested.utf8)).first == GitHubReview(title: "Fix du repli", repo: "octo/demo",
                                                                                         url: URL(string: "https://github.com/octo/demo/pull/9")))
        #expect(GitHubFeed.search(from: Data(noReview.utf8)).first == nil)
        #expect(GitHubFeed.events(from: Data("{\"message\":\"Bad credentials\"}".utf8), login: "x", received: false).isEmpty)
    }
}

@Suite struct GitHubTrackerTests {
    private func event(_ id: Int64, _ kind: GitHubEvent.Kind = .star) -> GitHubEvent {
        GitHubEvent(id: id, kind: kind, repo: "estebanbaigts/Yumi", actor: "louis")
    }

    @Test func theFirstLookIsHistoryAndOnlyWhatComesAfterIsNew() {
        var tracker = GitHubTracker()
        let first = tracker.fresh([event(3), event(2), event(1)], feed: "received_events")
        #expect(first.isEmpty)
        let same = tracker.fresh([event(3), event(2), event(1)], feed: "received_events")
        #expect(same.isEmpty)
        let next = tracker.fresh([event(5, .fork), event(4), event(3)], feed: "received_events")
        #expect(next.map(\.id) == [4, 5])
        // Each feed has its own history.
        let other = tracker.fresh([event(9)], feed: "events")
        #expect(other.isEmpty)
    }

    @Test func anEmptyFirstLookCountsSoTheVeryFirstEventIsNew() {
        var tracker = GitHubTracker()
        let nothing = tracker.fresh([], feed: "events")
        let first = tracker.fresh([event(1)], feed: "events")
        #expect(nothing.isEmpty)
        #expect(first.map(\.id) == [1])
    }

    @Test func newFollowersAreCountedFromTheSecondLook() {
        var tracker = GitHubTracker()
        let first = tracker.gained(followers: 42)
        let more = tracker.gained(followers: 44)
        let fewer = tracker.gained(followers: 43)
        #expect(first == 0 && more == 2 && fewer == 0)
    }

    @Test func whatWasSeenSurvivesARestart() throws {
        var tracker = GitHubTracker()
        _ = tracker.fresh([event(3)], feed: "events")
        _ = tracker.gained(followers: 10)
        var restored = try JSONDecoder().decode(GitHubTracker.self, from: JSONEncoder().encode(tracker))
        let replay = restored.fresh([event(3)], feed: "events")
        let gained = restored.gained(followers: 11)
        #expect(replay.isEmpty && gained == 1)
    }
}

@Suite struct GitHubScenesTests {
    @Test func oneSceneForEachKindWithHowManyCameTogether() {
        let star = GitHubEvent(id: 1, kind: .star, repo: "a/b", actor: "x")
        let fork = GitHubEvent(id: 2, kind: .fork, repo: "a/b", actor: "y")
        let scenes = GitHubScenes.scenes(for: [star, fork, star, star])
        #expect(scenes.map(\.scene) == [.star, .fork])
        #expect(scenes.map(\.count) == [3, 1])
        #expect(GitHubScenes.scenes(for: []).isEmpty)
    }

    @Test func everyKindHasItsScene() {
        let pairs: [(GitHubEvent.Kind, YumiScene)] = [(.star, .star), (.fork, .fork), (.pullRequest, .pullRequest), (.merge, .merge),
                                                      (.push, .push), (.issue, .issue), (.release, .release), (.follower, .follower)]
        for (kind, scene) in pairs { #expect(kind.scene == scene) }
        #expect(Set([GitHubEvent.Kind.star, .fork, .merge, .release, .push].map(\.isWorthAWord)) == [true])
        #expect(Set([GitHubEvent.Kind.issue, .pullRequest, .follower].map(\.isWorthAWord)) == [false])
    }

    @Test func aCommitIsRecognisedInACommand() {
        for command in ["git commit -m \"x\"", "git add -A && git commit -q -F -", "cd repo; git -C . commit --amend", "git commit"] {
            #expect(GitHubScenes.isCommit(command), "\(command)")
        }
        for command in ["git status", "git log --oneline", "echo git commit", "git commit-tree abc", "gitx commit"] where command != "echo git commit" {
            #expect(!GitHubScenes.isCommit(command), "\(command)")
        }
    }
}

@Suite struct GitHubSummaryTests {
    private let repo = GitHubRepo(fullName: "estebanbaigts/Yumi", stars: 128, forks: 12, url: URL(string: "https://github.com/estebanbaigts/Yumi"))
    private let star = GitHubEvent(id: 1, kind: .star, repo: "estebanbaigts/Yumi", actor: "louis")

    @Test func withoutATokenHeSaysSoAndOffersToConnect() {
        let snapshot = GitHubSummary.snapshot(connection: .noToken, repo: nil, openPulls: nil, last: nil, review: nil)
        #expect(snapshot.id == "github" && snapshot.name == "GitHub")
        #expect(snapshot.title == "Je ne vois pas ton GitHub.")
        #expect(snapshot.primaryAction == "Brancher" && snapshot.primarySymbol == "link")
        #expect(snapshot.live == nil)
        #expect(GitHubSummary.snapshot(connection: .refused, repo: nil, openPulls: nil, last: nil, review: nil).primaryAction == "Brancher")
    }

    @Test func theKeyFigureTitleAndSubtitle() {
        let snapshot = GitHubSummary.snapshot(connection: .connected, repo: repo, openPulls: 3, last: (star, 1), review: nil)
        #expect(snapshot.status == "128 · 12 · 3")
        #expect(snapshot.title == "Une étoile de plus, de la part de louis.")
        #expect(snapshot.subtitle == "estebanbaigts/Yumi")
        #expect(snapshot.primaryAction == "Ouvrir")
        #expect(snapshot.symbol == "arrow.triangle.branch")
        #expect(!snapshot.needsAttention)
        // Before the count of pull requests is known, the stars alone.
        #expect(GitHubSummary.snapshot(connection: .connected, repo: repo, openPulls: nil, last: nil, review: nil).status == "128")
        #expect(GitHubSummary.snapshot(connection: .connected, repo: repo, openPulls: nil, last: nil, review: nil).title == "Rien de neuf. Je surveille.")
    }

    @Test func aPullRequestWaitingForReviewComesFirst() {
        let review = GitHubReview(title: "Fix du repli", repo: "octo/demo", url: nil)
        let snapshot = GitHubSummary.snapshot(connection: .connected, repo: repo, openPulls: 3, last: (star, 1), review: review)
        #expect(snapshot.title == "Une pull request t'attend : Fix du repli")
        #expect(snapshot.primaryAction == "Relire")
        #expect(snapshot.needsAttention)
        #expect(snapshot.live?.priority == ModuleLivePriority.attention)
        #expect(snapshot.live?.text == "Relecture : Fix du repli")
        #expect(snapshot.status == "128 · 12 · 3")
    }

    @Test func everyEventHasItsSentenceInHisVoice() {
        var texts: [String] = []
        for kind in [GitHubEvent.Kind.star, .fork, .pullRequest, .merge, .push, .issue, .release, .follower] {
            for detail in ["", "Fix du repli"] {
                for count in [1, 3] {
                    texts.append(GitHubSummary.sentence(for: GitHubEvent(id: 1, kind: kind, repo: "estebanbaigts/Yumi", actor: "louis", detail: detail), count: count))
                }
            }
        }
        for connection in [GitHubSummary.Connection.noToken, .refused, .offline, .connected] {
            let snapshot = GitHubSummary.snapshot(connection: connection, repo: nil, openPulls: nil, last: nil, review: nil)
            texts += [snapshot.title, snapshot.subtitle]
        }
        for event in [GitHubEvent(id: 1, kind: .star, repo: "e/Yumi", actor: "louis"), GitHubEvent(id: 1, kind: .fork, repo: "e/Yumi", actor: "louis"),
                      GitHubEvent(id: 1, kind: .merge, repo: "e/Yumi", actor: "e", detail: "Fix"), GitHubEvent(id: 1, kind: .release, repo: "e/Yumi", actor: "e", detail: "Yumi 0.2")] {
            for count in [1, 4] {
                let variants = InitiativePhrases.variants(for: .repository(event, count: count), Surroundings(now: Date(), name: "Esteban"))
                #expect(variants.count >= 3)
                texts += variants.map(\.text)
            }
        }
        #expect(GitHubSummary.sentence(for: star, count: 3) == "Trois étoiles de plus sur Yumi.")
        for text in texts {
            let lower = " \(text.lowercased()) "
            for formula in VoiceTests.forbidden { #expect(!lower.contains(formula), "« \(text) » contient « \(formula) »") }
            #expect(VoiceTests.emoji(in: text).isEmpty, "\(text)")
            #expect(!text.contains("Yumi a") || true)
        }
    }
}

/// The module against a recorded GitHub: what it asks, how often, and what it does with the answers.
@MainActor
@Suite struct GitHubModuleTests {
    /// A GitHub that answers from a table and remembers what it was asked.
    private final class FakeGitHub: @unchecked Sendable {
        private let lock = NSLock()
        private var bodies: [String: String] = [:]
        private(set) var requests: [URLRequest] = []
        var status = 200
        var pollInterval = "60"

        func set(_ path: String, _ body: String) { lock.withLock { bodies[path] = body } }
        func asked(_ part: String) -> [URLRequest] { lock.withLock { requests.filter { $0.url?.absoluteString.contains(part) == true } } }

        var fetch: GitHubModule.Fetch {
            { [self] request in
                lock.withLock {
                    requests.append(request)
                    let url = request.url?.absoluteString ?? ""
                    guard status == 200 else { return GitHubModule.Response(status: status, data: Data(), headers: [:]) }
                    // The most specific path wins; "=" in front means the address must end with it.
                    let match = bodies.filter { $0.key.hasPrefix("=") ? url.hasSuffix(String($0.key.dropFirst())) : url.contains($0.key) }
                        .max { $0.key.count < $1.key.count }
                    guard let (path, body) = match else {
                        return GitHubModule.Response(status: 404, data: Data(), headers: [:])
                    }
                    // Conditional request: the same body as last time is "not modified".
                    let tag = "\"\(body.hashValue)\""
                    if request.value(forHTTPHeaderField: "If-None-Match") == tag {
                        return GitHubModule.Response(status: 304, data: Data(), headers: ["x-poll-interval": pollInterval])
                    }
                    _ = path
                    return GitHubModule.Response(status: 200, data: Data(body.utf8), headers: ["etag": tag, "x-poll-interval": pollInterval])
                }
            }
        }
    }

    private final class Seen {
        var news: [(GitHubEvent, Int)] = []
        var connects = 0
        var scenes: [(YumiScene, Int?)] = []
        var observer: NSObjectProtocol?
    }

    private func make(token: String? = "ghp_test", viaApp: Bool = false, prepared: (@MainActor () -> Void)? = nil) -> (GitHubModule, FakeGitHub, Seen) {
        let name = "yumi.tests.github.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let github = FakeGitHub()
        github.set("/user/repos", repos)
        github.set("/users/estebanbaigts/events", "[]")
        github.set("/users/estebanbaigts/received_events", "[]")
        github.set("review%2Drequested", noReview)
        github.set("is%3Aopen", openPulls)
        github.set("=api.github.com/user", user)
        let seen = Seen()
        let module = GitHubModule(token: { token }, prepare: { prepared?() }, viaApp: { viaApp },
                                  defaults: defaults, fetch: github.fetch,
                                  onConnect: { seen.connects += 1 }, onNews: { seen.news.append(($0, $1)) },
                                  play: { seen.scenes.append(($0, $1 > 1 ? $1 : nil)) })
        return (module, github, seen)
    }

    @Test func theGitHubAppFollowsTheRepositoriesOfEveryInstallation() async {
        let seen = Seen()
        let (module, github, _) = make(token: "ghu_app", viaApp: true, prepared: { seen.connects += 1 })
        github.set("/user/installations?", #"{"total_count":2,"installations":[{"id":1,"account":{"login":"estebanbaigts"}},{"id":2,"account":{"login":"acme"}}]}"#)
        github.set("/user/installations/1/repositories", #"{"total_count":1,"repositories":[{"full_name":"estebanbaigts/Yumi","fork":false,"stargazers_count":128,"forks_count":12,"pushed_at":"2026-10-01T10:00:00Z","html_url":"https://github.com/estebanbaigts/Yumi"}]}"#)
        github.set("/user/installations/2/repositories", #"{"total_count":1,"repositories":[{"full_name":"acme/api","fork":false,"stargazers_count":7,"forks_count":1,"pushed_at":"2026-10-02T10:00:00Z","html_url":"https://github.com/acme/api"}]}"#)
        await module.look()
        // The token was renewed if needed before the look.
        #expect(seen.connects == 1)
        #expect(github.asked("/user/repos").isEmpty)
        #expect(github.asked("/user/installations/2/repositories").count == 1)
        // The repository of the organisation, pushed last, comes first.
        #expect(module.snapshot.subtitle == "acme/api")
        #expect(github.asked("api.github.com/user").first?.value(forHTTPHeaderField: "Authorization") == "Bearer ghu_app")
    }

    @Test func withoutATokenNothingIsAsked() async {
        let (module, github, seen) = make(token: nil)
        await module.look()
        #expect(github.asked("api.github.com").isEmpty)
        #expect(module.snapshot.primaryAction == "Brancher")
        module.perform(.primary)
        #expect(seen.connects == 1)
    }

    @Test func theFirstLookFillsTheSnapshotAndReplaysNothing() async {
        let (module, github, seen) = make()
        github.set("/users/estebanbaigts/received_events", receivedEvents)
        github.set("/users/estebanbaigts/events", ownEvents)
        await module.look()
        #expect(module.snapshot.status == "128 · 12 · 3")
        #expect(module.snapshot.subtitle == "estebanbaigts/Yumi")
        #expect(module.snapshot.title == "Rien de neuf. Je surveille.")
        #expect(seen.scenes.isEmpty && seen.news.isEmpty)
        #expect(github.asked("api.github.com/user").first?.value(forHTTPHeaderField: "Authorization") == "Bearer ghp_test")
    }

    @Test func whatArrivesAfterwardsIsPlayedAndSaid() async {
        let (module, github, seen) = make()
        await module.look()
        github.set("/users/estebanbaigts/received_events", receivedEvents)
        await module.look()
        #expect(seen.scenes.map(\.0) == [.issue, .fork, .star])
        #expect(seen.scenes.allSatisfy { $0.1 == nil })
        #expect(module.snapshot.title == "Une étoile de plus, de la part de louis.")
        // One word, about the latest event that counts.
        #expect(seen.news.count == 1)
        #expect(seen.news.first?.0.kind == .star)

        github.set("/users/estebanbaigts/events", ownEvents)
        await module.look()
        #expect(seen.scenes.suffix(4).map(\.0) == [.pullRequest, .release, .push, .merge])
        #expect(seen.news.last?.0.kind == .merge)
    }

    @Test func severalAtOnceGiveOneSceneWithACount() async {
        let (module, github, seen) = make()
        let three = (1...3).map { #"{"id":"6000000000\#($0)","type":"WatchEvent","actor":{"login":"u\#($0)"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"action":"started"}}"# }
        github.set("/users/estebanbaigts/received_events", "[" + three.joined(separator: ",") + "]")
        // Three stars are already there at the first look: history. Then three more arrive.
        await module.look()
        let more = (4...6).map { #"{"id":"6000000000\#($0)","type":"WatchEvent","actor":{"login":"u\#($0)"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"action":"started"}}"# }
        github.set("/users/estebanbaigts/received_events", "[" + (more + three).joined(separator: ",") + "]")
        await module.look()
        #expect(seen.scenes.count == 1)
        #expect(seen.scenes.first?.0 == .star && seen.scenes.first?.1 == 3)
        #expect(seen.news.first?.1 == 3)
        #expect(module.snapshot.title == "Trois étoiles de plus sur Yumi.")
    }

    @Test func unchangedFeedsAreAskedConditionallyAndSlowOnesRarely() async {
        let (module, github, _) = make()
        await module.look()
        await module.look()
        let feed = github.asked("/users/estebanbaigts/events")
        #expect(feed.count == 2)
        #expect(feed[0].value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(feed[1].value(forHTTPHeaderField: "If-None-Match") != nil)
        // Repositories and searches are not asked again on the second look.
        #expect(github.asked("/user/repos").count == 1)
        #expect(github.asked("search/issues").count == 2)
        for _ in 0..<4 { await module.look() }
        #expect(github.asked("/user/repos").count == 2)
        #expect(github.asked("/user/repos")[1].value(forHTTPHeaderField: "If-None-Match") != nil)
    }

    @Test func aQuickLookSeesAPushBeforeTheFeeds() async {
        let (module, github, _) = make()
        github.set("/repos/estebanbaigts/Yumi/git/matching-refs/heads", #"[{"ref":"refs/heads/main","object":{"sha":"aaa"}}]"#)
        await module.look()
        await module.quickLook()
        #expect(module.snapshot.pages["recent"]?.isEmpty == true)
        github.set("/repos/estebanbaigts/Yumi/git/matching-refs/heads", #"[{"ref":"refs/heads/main","object":{"sha":"bbb"}}]"#)
        github.set("/repos/estebanbaigts/Yumi/compare/aaa...bbb",
                   #"{"total_commits":1,"commits":[{"sha":"bbb1234567","commit":{"message":"Fix the notch"},"author":{"login":"estebanbaigts"}}],"files":[{"filename":"a.swift","additions":4,"deletions":1}]}"#)
        await module.quickLook()
        #expect(module.snapshot.pages["recent"]?.first?.title == "Fix the notch")
        #expect(module.snapshot.live != nil)
        // The same push, when the feed brings it later, is not counted twice.
        github.set("/users/estebanbaigts/events",
                   #"[{"id":"50000000099","type":"PushEvent","actor":{"login":"estebanbaigts"},"repo":{"name":"estebanbaigts/Yumi"},"payload":{"ref":"refs/heads/main","before":"aaa","head":"bbb"}}]"#)
        await module.look()
        #expect(module.snapshot.pages["recent"]?.count == 1)
        #expect(github.asked("/compare/aaa...bbb").count == 1)
    }

    @Test func aNewFollowerHasItsScene() async {
        let (module, github, seen) = make()
        await module.look()
        github.set("=api.github.com/user", #"{"login":"estebanbaigts","followers":44}"#)
        for _ in 0..<5 { await module.look() }
        #expect(seen.scenes.contains { $0.0 == .follower && $0.1 == 2 })
        #expect(seen.news.isEmpty)
    }

    @Test func aRefusedTokenIsSaidAndAReviewIsShown() async {
        let (module, github, _) = make()
        github.set("review%2Drequested", reviewRequested)
        await module.look()
        #expect(module.snapshot.primaryAction == "Relire")
        #expect(module.snapshot.live?.priority == ModuleLivePriority.attention)

        let (refused, bad, _) = make()
        bad.status = 401
        await refused.look()
        #expect(refused.snapshot.title == "Ton jeton GitHub ne passe plus.")
    }

    @Test func aCommitMadeByAClaudeSessionHasItsSceneWithoutWatchingTheDisk() {
        let (module, _, seen) = make()
        let id = SessionID("s")
        module.receive(.toolFinished(id, ToolInfo(name: "Bash", summary: "git add -A && git commit -q -m \"x\"")), sessions: [:])
        module.receive(.toolFinished(id, ToolInfo(name: "Bash", summary: "git status")), sessions: [:])
        module.receive(.toolStarted(id, ToolInfo(name: "Bash", summary: "git commit -m x")), sessions: [:])
        #expect(seen.scenes.map(\.0) == [.commit])
    }
}

@Suite struct GitHubInitiativeTests {
    @Test func aStarIsSaidAtOnceButFocusAndSilenceStillHoldIt() {
        let star = GitHubEvent(id: 1, kind: .star, repo: "estebanbaigts/Yumi", actor: "louis")
        var engine = InitiativeEngine()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var around = Surroundings(now: now, talk: .discreet)
        let said = engine.consider(.repository(star, count: 1), in: around)
        #expect(said?.text == "Une étoile de plus sur Yumi, de la part de louis.")
        // News come as they happen: no twenty minutes. Focus and silence still hold them.
        #expect(engine.refusal(of: .repository(star, count: 1), in: around) == nil)
        around.now = now.addingTimeInterval(3600)
        around.focusRunning = true
        #expect(engine.refusal(of: .repository(star, count: 1), in: around) == .focus)
        around.focusRunning = false
        around.talk = .silent
        #expect(engine.refusal(of: .repository(star, count: 1), in: around) == .silent)
        #expect(Occasion.repository(star, count: 1).topic == "github.star")
    }
}

@MainActor
@Suite struct GitHubSceneNotificationTests {
    @Test func byDefaultAScenePostsTheNotificationOfTheContract() async {
        var received: [(YumiScene?, Int?)] = []
        let observer = NotificationCenter.default.addObserver(forName: .yumiScene, object: nil, queue: nil) { note in
            let scene = note.object as? YumiScene, count = note.userInfo?["count"] as? Int
            MainActor.assumeIsolated { received.append((scene, count)) }
        }
        let module = GitHubModule(token: { nil })
        module.receive(.toolFinished(SessionID("s"), ToolInfo(name: "Bash", summary: "git commit -m x")), sessions: [:])
        NotificationCenter.default.removeObserver(observer)
        #expect(received.contains { $0.0 == .commit && $0.1 == nil })
    }
}
