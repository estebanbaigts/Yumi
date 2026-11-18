import AppKit

/// GitHub, as a module: the person's repositories, what happens on them, and a small scene of
/// Yumi for each event (Contracts/EventAnimations.swift).
///
/// It asks GitHub the way GitHub wants to be asked: every request carries the `ETag` of the last
/// answer, so an unchanged feed costs nothing of the quota, and the event feeds are never asked
/// more often than their `X-Poll-Interval` header says (one minute or more).
@MainActor
final class GitHubModule: YumiModule {
    let id = "github"

    /// One answer of the API.
    struct Response: Sendable {
        var status: Int
        var data: Data
        var headers: [String: String]
    }
    typealias Fetch = @Sendable (URLRequest) async throws -> Response

    /// Seconds between two looks at the event feeds, unless GitHub asks for more.
    static let pollInterval: TimeInterval = 60
    /// Repositories, followers and reviews change slowly: asked every fifth look.
    static let slowEvery = 5
    private static let trackerKey = "githubTracker"

    private let token: @MainActor () -> String?
    /// Renews a token about to expire (the GitHub App's) before each look.
    private let prepare: @MainActor () async -> Void
    /// True when signed in with the GitHub App: the repositories come from its installations.
    private let viaApp: @MainActor () -> Bool
    private let fetch: Fetch
    private let defaults: UserDefaults
    private let onConnect: @MainActor () -> Void
    /// Events worth a word of Yumi (a star, a fork, a merge, a release), with how many came together.
    private let onNews: @MainActor (GitHubEvent, Int) -> Void
    /// Plays a scene: by default, the notification of the contract.
    private let play: @MainActor (YumiScene, Int) -> Void

    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var tracker: GitHubTracker
    /// Stars, forks and latest commits of the followed repositories, every look.
    private var quick = GitHubQuickWatch()
    /// Repositories watched closely each look; the others wait for the event feeds.
    static let quickRepos = 8
    private var etags: [String: String] = [:]
    /// The last answer of the installations' lists, for "not modified".
    private var pageCache: [String: Data] = [:]
    private var login: String?
    private var connection = GitHubSummary.Connection.noToken
    private var repo: GitHubRepo?
    private var openPulls: Int?
    private var review: GitHubReview?
    private var last: (event: GitHubEvent, count: Int)?
    /// Open pull requests of the followed repositories, with their checks.
    private var pulls: [GitHubPull] = []
    /// The last answer for each repository and each commit, kept for "not modified".
    private var pullCache: [String: [GitHubPull]] = [:]
    private var checkCache: [String: GitHubChecks?] = [:]
    /// nil until the pull requests were read once.
    private var pullsSeen = false
    /// A pull request whose checks just turned red, until it is looked at or turns green.
    private var red: GitHubPull?
    /// The latest events of both feeds, newest first.
    private var recent: [GitHubEvent] = []
    private var rowObserver: NSObjectProtocol?
    private var hiddenObserver: NSObjectProtocol?
    /// The person's repositories whose pull requests are listed.
    private var followed: [String] = []
    private var wait = GitHubModule.pollInterval
    private var looks = 0
    /// Where the contribution calendar goes (the island and the settings read it).
    var contributions = GitHubContributions.shared
    /// Every repository of the person: owned, shared with them, of their organisations.
    private var repos: Set<String> = []
    /// Pushes whose commits were read, newest first, and those already asked (once each).
    private var pushes: [GitHubPush] = []
    private var asked: Set<Int64> = []
    /// Commits of pushes read per look at most, so a burst never spends the quota.
    static let comparesPerLook = 6
    static let pushesKept = 60
    /// Seconds between two quick looks at the branches of the followed repositories: a push
    /// shows within these seconds instead of waiting for the event feeds, which GitHub serves late.
    static let quickInterval: TimeInterval = 15
    /// Lines of the activity feeds already read (compared once each, even after they leave the list).
    private var activitySeen: Set<Int64> = []
    /// Comparisons asked per look at the activity feeds, so the first look never spends the quota.
    static let comparesPerActivityLook = 8
    /// Lines asked to each repository's activity feed.
    static let activityPerRepo = 10
    /// No request before this moment: GitHub said the quota is spent.
    private var blockedUntil = Date.distantPast
    /// The repository opened in the "Dépôts" page, with its latest pushes once read.
    private var opened: String?
    private var openedLoading = false
    private var repoPushes: [String: [GitHubPush]] = [:]

    init(token: @escaping @MainActor () -> String?,
         prepare: @escaping @MainActor () async -> Void = {},
         viaApp: @escaping @MainActor () -> Bool = { false },
         defaults: UserDefaults = .standard,
         fetch: @escaping Fetch = GitHubModule.network,
         onConnect: @escaping @MainActor () -> Void = {},
         onNews: @escaping @MainActor (GitHubEvent, Int) -> Void = { _, _ in },
         play: @escaping @MainActor (YumiScene, Int) -> Void = { scene, count in
             NotificationCenter.default.post(name: .yumiScene, object: scene, userInfo: count > 1 ? ["count": count] : nil)
         }) {
        self.play = play
        self.token = token
        self.prepare = prepare
        self.viaApp = viaApp
        self.defaults = defaults
        self.fetch = fetch
        self.onConnect = onConnect
        self.onNews = onNews
        tracker = defaults.data(forKey: Self.trackerKey).flatMap { try? JSONDecoder().decode(GitHubTracker.self, from: $0) } ?? GitHubTracker()
    }

    var snapshot: ModuleSnapshot {
        let hidden = GitHubRepos.hidden(in: defaults)
        let now = Date()
        var snapshot = GitHubSummary.snapshot(connection: connection, repo: repo, openPulls: openPulls, last: last, review: review,
                                              pulls: pulls.filter { !hidden.contains($0.repo) }, recent: [], red: red)
        guard connection == .connected else { return snapshot }
        // What happens, by repository, then the open pull requests and their checks.
        snapshot.rows = GitHubActivity.rows(pushes: pushes, events: recent, hidden: hidden, now: now) + snapshot.rows
        // The pages of the island: the latest commits, then the repositories one line each.
        snapshot.pages = ["recent": GitHubPages.recent(pushes: pushes, hidden: hidden),
                          "repos": opened.map { GitHubPages.repo($0, pushes: pushes(of: $0), loading: openedLoading) }
                            ?? GitHubPages.repos(followed: followed, pushes: pushes, pulls: pulls, hidden: hidden, now: now)]
        // A push of the last two minutes shows in the folded island, after a red check or a review.
        if snapshot.live == nil, let push = GitHubActivity.livePush(pushes, hidden: hidden, now: now) {
            let text = push.merge ? loc("\(push.repoName) · PR fusionnée sur \(push.branch)")
                : push.total == 1 ? loc("\(push.repoName) · un commit sur \(push.branch)") : loc("\(push.repoName) · \(push.total) commits sur \(push.branch)")
            snapshot.live = ModuleLive(text: text, priority: ModuleLivePriority.activity)
        }
        return snapshot
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        rowObserver = NotificationCenter.default.addObserver(forName: .moduleRowAction, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["module"] as? String == "github", let row = note.userInfo?["row"] as? String else { return }
            MainActor.assumeIsolated { self?.open(row) }
        }
        hiddenObserver = NotificationCenter.default.addObserver(forName: .githubReposChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
        restart()
    }

    func stop() {
        onChange = nil
        for observer in [rowObserver, hiddenObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        rowObserver = nil
        hiddenObserver = nil
        polling?.cancel()
        polling = nil
    }

    /// Looks now, then again at GitHub's pace. Without a token nothing is asked and nothing loops.
    private func restart() {
        polling?.cancel()
        polling = nil
        guard token() != nil else {
            set(.noToken)
            contributions.clear()
            return
        }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.look()
                // Between two looks at the feeds, quick looks at the branches and pull requests.
                var waited: TimeInterval = 0
                while waited < self.wait, !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(Self.quickInterval), tolerance: .seconds(2))
                    waited += Self.quickInterval
                    await self.quickLook()
                }
            }
        }
    }

    private func set(_ new: GitHubSummary.Connection) {
        guard new != connection else { return }
        connection = new
        onChange?()
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        switch action {
        case .primary:
            if connection == .noToken || connection == .refused {
                onConnect()
            } else if let shown = red {
                red = nil
                onChange?()
                if let url = shown.url { NSWorkspace.shared.open(url) }
            } else if let url = review?.url ?? repo?.url ?? URL(string: "https://github.com") {
                NSWorkspace.shared.open(url)
            }
        case .secondary:
            // The settings just saved a token: read it again without waiting.
            etags = [:]
            pageCache = [:]
            login = nil
            repos = []
            restart()
        case .previous:
            break
        }
    }

    /// A line of the list was clicked: its page opens.
    private func open(_ row: String) {
        if row == GitHubPages.backAction {
            opened = nil
            onChange?()
            return
        }
        if row.hasPrefix(GitHubPages.repoAction) {
            let repo = String(row.dropFirst(GitHubPages.repoAction.count))
            opened = repo
            openedLoading = true
            onChange?()
            Task { [weak self] in await self?.readRepo(repo) }
            return
        }
        guard let url = URL(string: row), url.host == "github.com" else { return }
        if red?.url == url {
            red = nil
            onChange?()
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: Local commits

    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        // A commit made by a Claude Code session is known the moment its command ends: nothing
        // watches the disk for it.
        guard case .toolFinished(_, let tool) = event, tool.name == "Bash", GitHubScenes.isCommit(tool.summary) else { return }
        play(.commit, 1)
    }

    // MARK: Asking GitHub

    /// One look at GitHub. Internal so tests can drive it without waiting.
    func look() async {
        await prepare()
        guard let token = token() else {
            set(.noToken)
            return
        }
        looks += 1
        let slow = looks % Self.slowEvery == 1 || login == nil

        if slow {
            switch await get("/user", token: token) {
            case .fresh(let data):
                guard let user = GitHubFeed.user(from: data) else { break }
                login = user.login
                let gained = tracker.gained(followers: user.followers)
                if gained > 0 {
                    let event = GitHubEvent(id: 0, kind: .follower, repo: "", actor: "")
                    announce([GitHubEvent](repeating: event, count: gained))
                }
            case .refused:
                set(.refused)
                return
            case .failed:
                if login == nil { set(.offline) }
                return
            case .unchanged:
                break
            }
        }
        guard let login else { return }
        set(.connected)
        if contributions.due() { await readContributions(token: token) }

        if slow || repos.isEmpty {
            // Every repository the token can see: owned, shared, of the person's organisations.
            if let data = await repoList(token: token) {
                repo = GitHubFeed.mostActiveRepo(from: data)
                let hidden = GitHubRepos.hidden(in: defaults)
                followed = GitHubFeed.followedRepos(from: data).filter { !hidden.contains($0) }
                let names = GitHubFeed.repoNames(from: data)
                repos = Set(names)
                defaults.set(names, forKey: GitHubRepos.knownKey)
                defaults.set(login, forKey: GitHubRepos.loginKey)
            }
        }
        await quickLook(token: token)
        for (feed, received) in [("events", false), ("received_events", true)] {
            if case .fresh(let data) = await get("/users/\(login)/\(feed)?per_page=50", token: token, paced: true) {
                let events = GitHubFeed.events(from: data, login: login, received: received, repos: repos)
                remember(events)
                await readCommits(of: events.filter { $0.kind == .push }, token: token)
                let hidden = GitHubRepos.hidden(in: defaults)
                announce(quick.swallow(tracker.fresh(events, feed: feed).filter { !hidden.contains($0.repo) }))
            }
        }
        _ = await readActivities(token: token)
        if slow {
            await readPulls(token: token, login: login)
            if let repo, case .fresh(let data) = await get("/search/issues?per_page=1&q=" + Self.query("repo:\(repo.fullName) is:pr is:open"), token: token) {
                openPulls = GitHubFeed.search(from: data).count
            }
            if case .fresh(let data) = await get("/search/issues?per_page=1&q=" + Self.query("is:pr is:open review-requested:\(login)"), token: token) {
                review = GitHubFeed.search(from: data).first
            }
        }
        if let data = try? JSONEncoder().encode(tracker) { defaults.set(data, forKey: Self.trackerKey) }
        onChange?()
    }

    /// Every repository to follow, shaped like `/user/repos?sort=pushed`. nil when unchanged or unreachable.
    private func repoList(token: String) async -> Data? {
        guard viaApp() else {
            // Every repository the token can see: owned, shared, of the person's organisations.
            guard case .fresh(let data) = await get("/user/repos?per_page=100&affiliation=owner,collaborator,organization_member&sort=pushed", token: token) else { return nil }
            return data
        }
        // The GitHub App: the repositories of each account where it is installed.
        guard let list = await kept("/user/installations?per_page=100", token: token) else { return nil }
        var pages: [Data] = []
        let installations = GitHubApp.installations(from: list)
        GitHubApp.saveAccounts(installations, in: defaults)
        for installation in installations.prefix(Self.installationsRead) {
            for page in 1...Self.pagesPerInstallation {
                guard let data = await kept("/user/installations/\(installation.id)/repositories?per_page=100&page=\(page)", token: token) else { break }
                pages.append(data)
                let count = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["repositories"] as? [Any])?.count ?? 0
                if count < 100 { break }
            }
        }
        return GitHubApp.mergedRepos(pages)
    }

    /// Accounts read per look, and pages of a hundred repositories read per account.
    static let installationsRead = 20
    static let pagesPerInstallation = 3

    /// A conditional request whose last answer is kept: "not modified" gives it back.
    private func kept(_ path: String, token: String) async -> Data? {
        switch await get(path, token: token) {
        case .fresh(let data):
            pageCache[path] = data
            return data
        case .unchanged:
            return pageCache[path]
        case .refused, .failed:
            return nil
        }
    }

    /// Stars, forks and the latest commit of the followed repositories: asked with their tag,
    /// they cost nothing while nothing changes, and they do not wait for the event feeds.
    private func quickLook(token: String) async {
        var found: [GitHubEvent] = []
        for name in followed.prefix(Self.quickRepos) {
            if case .fresh(let data) = await get("/repos/\(name)", token: token),
               let counts = GitHubQuickWatch.counts(from: data) {
                found += quick.counts(of: name, stars: counts.stars, forks: counts.forks)
            }
            if case .fresh(let data) = await get("/repos/\(name)/commits?per_page=1", token: token),
               let head = GitHubQuickWatch.head(from: data),
               let push = quick.head(of: name, sha: head.sha, message: head.message, author: head.author) {
                found.append(push)
            }
        }
        if !found.isEmpty { announce(found) }
    }

    /// The exact commits of the pushes not read yet, through compare: each push once, a few per look.
    private func readCommits(of events: [GitHubEvent], token: String) async {
        let hidden = GitHubRepos.hidden(in: defaults)
        var budget = Self.comparesPerLook
        for event in events.sorted(by: { $0.id > $1.id }) where !asked.contains(event.id) && !hidden.contains(event.repo) && budget > 0 {
            guard let path = GitHubFeed.comparePath(repo: event.repo, before: event.before, head: event.head) else { continue }
            asked.insert(event.id)
            // Already seen by a quick look: the event only brings its number and its author.
            if let known = pushes.firstIndex(where: { $0.repo == event.repo && !event.head.isEmpty && $0.head == event.head }) {
                pushes[known].eventID = event.id
                pushes[known].actor = event.actor
                continue
            }
            budget -= 1
            guard case .fresh(let data) = await get(path, token: token), let found = GitHubFeed.commits(fromCompare: data) else { continue }
            pushes.append(GitHubPush(eventID: event.id, repo: event.repo, branch: event.detail, actor: event.actor, date: event.date,
                                     total: found.total, commits: found.commits, files: GitHubFeed.files(fromCompare: data),
                                     head: event.head, before: event.before))
            // A comparison never changes: its tag is not worth keeping.
            etags[path] = nil
        }
        pushes = Array(pushes.sorted(by: GitHubPush.newestFirst).prefix(Self.pushesKept))
    }

    /// A quick look, between two looks at the feeds: the branches of the followed repositories
    /// (and of the one opened), then the pull requests. Conditional requests: an unchanged
    /// answer is free, so this can run every few seconds.
    func quickLook() async {
        await prepare()
        guard let token = token(), let login, connection == .connected, Date() >= blockedUntil else { return }
        let changed = await readActivities(token: token)
        let before = pulls
        await readPulls(token: token, login: login)
        #if DEBUG
        if ProcessInfo.processInfo.environment["YUMI_TRACE_GITHUB"] != nil {
            print("[github] pushes=\(pushes.sorted(by: GitHubPush.newestFirst).prefix(4).map { "\($0.repoName)@\($0.branch)\($0.merge ? " (merge)" : "")" }) changé=\(changed)")
            fflush(stdout)
        }
        #endif
        if changed || before != pulls { onChange?() }
    }

    /// The activity feed of each followed repository (and of the one opened): every push and
    /// merge as soon as it happens, where the event feeds can lag by hours. Returns whether
    /// something new was added.
    private func readActivities(token: String) async -> Bool {
        var names = followed
        if let opened, !names.contains(opened) { names.append(opened) }
        let hidden = GitHubRepos.hidden(in: defaults)
        var budget = Self.comparesPerActivityLook
        var added = false
        for repo in names where !hidden.contains(repo) {
            let found = await readActivity(of: repo, token: token, budget: &budget)
            guard !found.isEmpty else { continue }
            pushes = Array((pushes + found).sorted(by: GitHubPush.newestFirst).prefix(Self.pushesKept))
            if repo == opened { repoPushes[repo] = Array(((repoPushes[repo] ?? []) + found).sorted(by: GitHubPush.newestFirst).prefix(GitHubPages.repoPushes)) }
            added = true
        }
        return added
    }

    /// The pushes and merges of one repository's activity feed not read yet, with their commits
    /// and files (through compare, `budget` comparisons at most).
    /// - Parameter again: reads lines already seen too, unless their push is still known (the
    ///   opened repository's page may need pushes that left the main list).
    private func readActivity(of repo: String, token: String, budget: inout Int, again: Bool = false) async -> [GitHubPush] {
        guard case .fresh(let data) = await get("/repos/\(repo)/activity?per_page=\(Self.activityPerRepo)", token: token) else { return [] }
        var found: [GitHubPush] = []
        let known = Set(pushes(of: repo).map(\.eventID))
        for item in GitHubFeed.activity(from: data) where budget > 0 && !known.contains(item.id) && (again || !activitySeen.contains(item.id)) {
            if pushes.contains(where: { $0.repo == repo && !$0.merge && $0.head == item.after }) && !item.merge {
                activitySeen.insert(item.id)
                continue
            }
            guard let path = GitHubFeed.comparePath(repo: repo, before: item.before, head: item.after) else { continue }
            budget -= 1
            guard case .fresh(let compare) = await get(path, token: token), let commits = GitHubFeed.commits(fromCompare: compare) else { continue }
            etags[path] = nil
            activitySeen.insert(item.id)
            found.append(GitHubPush(eventID: item.id, repo: repo, branch: item.branch, actor: item.actor, date: item.date,
                                    total: commits.total, commits: commits.commits, files: GitHubFeed.files(fromCompare: compare),
                                    head: item.after, before: item.before, merge: item.merge))
        }
        // The feed was read but not all of it could be compared: ask it again next time.
        if budget == 0 { etags["/repos/\(repo)/activity?per_page=\(Self.activityPerRepo)"] = nil }
        return found
    }

    /// The latest pushes of one repository, for the "Dépôts" page: its event feed, then the
    /// commits and files of each push not read yet.
    private func readRepo(_ repo: String) async {
        defer {
            if opened == repo { openedLoading = false }
            onChange?()
        }
        await prepare()
        guard let token = token(), login != nil, Date() >= blockedUntil else { return }
        // Asked again even if the quick looks read it: the opened repository may not be followed.
        etags["/repos/\(repo)/activity?per_page=\(Self.activityPerRepo)"] = nil
        var budget = GitHubPages.repoPushes
        let found = await readActivity(of: repo, token: token, budget: &budget, again: true)
        repoPushes[repo] = Array(((repoPushes[repo] ?? []) + found).sorted(by: GitHubPush.newestFirst).prefix(GitHubPages.repoPushes))
    }

    /// The pushes known for a repository, from every source, each once.
    private func pushes(of repo: String) -> [GitHubPush] {
        var all = pushes.filter { $0.repo == repo }
        for push in repoPushes[repo] ?? [] where !all.contains(where: { $0.eventID == push.eventID || (!push.head.isEmpty && $0.head == push.head) }) {
            all.append(push)
        }
        return all
    }

    /// Keeps the latest events for the list.
    private func remember(_ events: [GitHubEvent]) {
        var byID = Dictionary(recent.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for event in events { byID[event.id] = event }
        recent = Array(byID.values.sorted { $0.id > $1.id }.prefix(30))
    }

    /// The open pull requests of the followed repositories and their checks, read with the
    /// slow looks (every five minutes): conditional requests, so an unchanged answer is free.
    private func readPulls(token: String, login: String) async {
        var all: [GitHubPull] = []
        for name in followed {
            var list = pullCache[name] ?? []
            switch await get("/repos/\(name)/pulls?state=open&per_page=\(GitHubBoard.pullsPerRepo)&sort=updated&direction=desc", token: token) {
            case .fresh(let data):
                list = GitHubFeed.pulls(from: data, repo: name, login: login)
                pullCache[name] = list
            case .refused, .failed:
                continue
            case .unchanged:
                break
            }
            for index in list.indices where !list[index].sha.isEmpty {
                let sha = list[index].sha
                switch await get("/repos/\(name)/commits/\(sha)/check-runs?per_page=50", token: token) {
                case .fresh(let data):
                    checkCache[sha] = .some(GitHubFeed.checks(from: data))
                default:
                    break
                }
                list[index].checks = checkCache[sha] ?? nil
            }
            all += list
        }
        let gone = GitHubBoard.turnedRed(before: pullsSeen ? pulls : nil, after: all)
        if let first = gone.first { red = first }
        if let shown = red, !all.contains(where: { $0.key == shown.key && $0.checks == .failed }) { red = nil }
        // A new request for the person's review gets the scene of a pull request.
        let asked = all.filter { pull in pull.asksMyReview && !pulls.contains { $0.key == pull.key && $0.asksMyReview } }
        if pullsSeen, !asked.isEmpty { play(.pullRequest, asked.count) }
        pulls = all
        pullsSeen = true
        let shas = Set(all.map(\.sha))
        checkCache = checkCache.filter { shas.contains($0.key) }
        etags = etags.filter { path, _ in !path.contains("/commits/") || shas.contains { path.contains("/commits/\($0)/") } }
    }

    /// Plays the scenes of new events and tells Yumi about the ones that count.
    private func announce(_ events: [GitHubEvent]) {
        guard let latest = events.last else { return }
        for (scene, count) in GitHubScenes.scenes(for: events) {
            play(scene, count)
        }
        last = (latest, events.filter { $0.kind == latest.kind }.count)
        // One word at most for a batch: about the latest event that counts.
        if var worth = events.last(where: { $0.kind.isWorthAWord }) {
            // A push read from the feed: its newest commit, when its commits were read
            if worth.kind == .push, worth.headline.isEmpty, let push = pushes.first(where: { $0.eventID == worth.id }) {
                worth.headline = push.commits.first?.message ?? ""
            }
            onNews(worth, events.filter { $0.kind == worth.kind }.count)
        }
        onChange?()
    }

    /// The calendar of the profile, by GraphQL: one request, at most every 30 minutes, or
    /// after the moment GitHub said to wait until.
    private func readContributions(token: String) async {
        guard let response = try? await fetch(GitHubContributionsFeed.request(token: token)) else {
            contributions.record(.failure(.unreachable))
            return
        }
        contributions.record(GitHubContributionsFeed.read(status: response.status, data: response.data, headers: response.headers))
        onChange?()
    }

    private enum Answer { case fresh(Data), unchanged, refused, failed }

    /// A conditional request: the tag of the last answer goes with it, and "not modified" costs nothing.
    private func get(_ path: String, token: String, paced: Bool = false) async -> Answer {
        guard let url = URL(string: "https://api.github.com" + path) else { return .failed }
        // GitHub says "max-age=60": the system's cache would serve the same answer for a minute
        // without asking. The tag below already makes an unchanged answer free.
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let tag = etags[path] { request.setValue(tag, forHTTPHeaderField: "If-None-Match") }
        guard let response = try? await fetch(request) else { return .failed }
        if paced, let asked = response.headers["x-poll-interval"].flatMap(Double.init) {
            wait = max(Self.pollInterval, asked)
        }
        switch response.status {
        case 200:
            if let tag = response.headers["etag"] { etags[path] = tag }
            return .fresh(response.data)
        case 304:
            return .unchanged
        case 401:
            return .refused
        case 403, 429:
            defer { blockedUntil = Date().addingTimeInterval(wait) }
            // Out of quota: wait until GitHub says it is back, an hour at most.
            if let reset = response.headers["x-ratelimit-reset"].flatMap(Double.init) {
                wait = min(3600, max(Self.pollInterval, reset - Date().timeIntervalSince1970))
            } else {
                wait = max(wait, 300)
            }
            return .failed
        default:
            return .failed
        }
    }

    private static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? text
    }

    /// The real network. Header names are lowercased so they can be read whatever their case.
    nonisolated static let network: Fetch = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (key, value) in http?.allHeaderFields ?? [:] {
            if let key = key as? String, let value = value as? String { headers[key.lowercased()] = value }
        }
        return Response(status: http?.statusCode ?? 0, data: data, headers: headers)
    }
}
