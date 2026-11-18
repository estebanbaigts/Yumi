import Foundation

// MARK: - What happens on all of the person's repositories
// Pushes with their exact commits, read through GitHub's compare (the events feed no longer
// lists the commits of a push), grouped by repository, with how many commits today and this
// week. Pure: data in, values out.

/// One commit of a push.
struct GitHubCommit: Equatable, Sendable, Codable {
    var sha: String
    /// The first line of the message.
    var message: String
    var author: String
    var url: URL?

    var shortSHA: String { String(sha.prefix(7)) }
}

/// A push, once its commits are known.
struct GitHubPush: Equatable, Sendable, Codable {
    var eventID: Int64
    var repo: String
    var branch: String
    var actor: String
    var date: Date?
    /// How many commits it carried (compare's `total_commits`), even beyond those listed.
    var total: Int
    /// The newest first, a few at most.
    var commits: [GitHubCommit]
    /// The files the push touched, with lines added and removed (from compare).
    var files: [GitHubFile] = []
    /// The commit the branch points to after the push, to know a push seen twice.
    var head: String = ""
    /// The commit the branch pointed to before it; empty for a new branch.
    var before: String = ""

    var repoName: String { repo.split(separator: "/").last.map(String.init) ?? repo }
}

/// A file a push touched.
struct GitHubFile: Equatable, Sendable, Codable {
    var name: String
    var additions: Int
    var deletions: Int
}

/// The repositories the person chose not to see. Everything else is followed.
enum GitHubRepos {
    static let hiddenKey = "github.hiddenRepos"
    static let knownKey = "github.knownRepos"
    static let loginKey = "github.login"

    static func hidden(in defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    }

    static func setHidden(_ repos: Set<String>, in defaults: UserDefaults = .standard) {
        defaults.set(repos.sorted(), forKey: hiddenKey)
    }

    /// The repositories the module found, for the settings' list.
    static func known(in defaults: UserDefaults = .standard) -> [String] { defaults.stringArray(forKey: knownKey) ?? [] }
}

extension GitHubFeed {
    /// Every repository of `/user/repos`, archived ones aside, most recently pushed first.
    static func repoNames(from data: Data) -> [String] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return items.filter { $0["archived"] as? Bool != true }.compactMap { $0["full_name"] as? String }
    }

    /// The commits of `/repos/{repo}/compare/{before}...{head}` (or of one commit), newest first.
    static func commits(fromCompare data: Data, limit: Int = 5) -> (total: Int, commits: [GitHubCommit])? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let items: [[String: Any]]
        if let list = object["commits"] as? [[String: Any]] {
            items = list
        } else if object["sha"] != nil {
            items = [object]
        } else {
            return nil
        }
        let commits = items.reversed().prefix(limit).compactMap { item -> GitHubCommit? in
            guard let sha = item["sha"] as? String else { return nil }
            let commit = item["commit"] as? [String: Any] ?? [:]
            let message = (commit["message"] as? String ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            let author = (item["author"] as? [String: Any])?["login"] as? String
                ?? (commit["author"] as? [String: Any])?["name"] as? String ?? ""
            return GitHubCommit(sha: sha, message: message, author: author,
                                url: (item["html_url"] as? String).flatMap(URL.init(string:)))
        }
        return (object["total_commits"] as? Int ?? items.count, Array(commits))
    }

    /// The files of a comparison (or of one commit), most changed first.
    static func files(fromCompare data: Data, limit: Int = 8) -> [GitHubFile] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = object["files"] as? [[String: Any]] else { return [] }
        let files = items.compactMap { item -> GitHubFile? in
            guard let name = item["filename"] as? String else { return nil }
            return GitHubFile(name: name, additions: item["additions"] as? Int ?? 0, deletions: item["deletions"] as? Int ?? 0)
        }
        return Array(files.sorted { $0.additions + $0.deletions > $1.additions + $1.deletions }.prefix(limit))
    }

    /// Branch name → commit, from `/repos/{repo}/git/matching-refs/heads`.
    static func heads(from data: Data) -> [String: String] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var heads: [String: String] = [:]
        for item in items {
            guard let ref = item["ref"] as? String, let sha = (item["object"] as? [String: Any])?["sha"] as? String else { continue }
            heads[ref.replacingOccurrences(of: "refs/heads/", with: "")] = sha
        }
        return heads
    }

    /// What to ask for the commits of a push: the comparison, or the head alone for a new branch.
    static func comparePath(repo: String, before: String, head: String) -> String? {
        guard !head.isEmpty else { return nil }
        if before.isEmpty || before.allSatisfy({ $0 == "0" }) { return "/repos/\(repo)/commits/\(head)" }
        return "/repos/\(repo)/compare/\(before)...\(head)"
    }
}

/// The activity view: per repository, a line of counts, then its latest pushes with their
/// commits and its other events, newest repository first.
enum GitHubActivity {
    static let repos = 5
    static let pushesPerRepo = 2
    static let commitsPerPush = 3

    /// Commits of the pushes made today and in the last seven days, per repository.
    static func counts(_ pushes: [GitHubPush], now: Date, calendar: Calendar) -> [String: (today: Int, week: Int)] {
        let startOfToday = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        var counts: [String: (today: Int, week: Int)] = [:]
        for push in pushes {
            guard let date = push.date, date >= weekAgo else { continue }
            var count = counts[push.repo] ?? (0, 0)
            count.week += push.total
            if date >= startOfToday { count.today += push.total }
            counts[push.repo] = count
        }
        return counts
    }

    static func rows(pushes: [GitHubPush], events: [GitHubEvent], hidden: Set<String>, now: Date,
                     calendar: Calendar = .current) -> [ModuleRow] {
        let shownPushes = pushes.filter { !hidden.contains($0.repo) }
        let others = events.filter { $0.kind != .push && !hidden.contains($0.repo) }
        let counts = counts(shownPushes, now: now, calendar: calendar)
        // Repositories by their latest activity.
        var latest: [String: Date] = [:]
        for push in shownPushes { latest[push.repo] = max(latest[push.repo] ?? .distantPast, push.date ?? .distantPast) }
        for event in others { latest[event.repo] = max(latest[event.repo] ?? .distantPast, event.date ?? .distantPast) }
        let order = latest.keys.sorted { latest[$0]! != latest[$1]! ? latest[$0]! > latest[$1]! : $0 < $1 }

        var rows: [ModuleRow] = []
        for repo in order.prefix(Self.repos) {
            let name = repo.split(separator: "/").last.map(String.init) ?? repo
            let count = counts[repo] ?? (0, 0)
            var section = name
            if count.week > 0 {
                section += " · " + loc("\(count.today) aujourd'hui, \(count.week) cette semaine")
            }
            var first = true
            for push in shownPushes.filter({ $0.repo == repo }).sorted(by: { $0.eventID > $1.eventID }).prefix(Self.pushesPerRepo) {
                let title = push.total == 1 ? loc("Un commit sur \(push.branch)") : loc("\(push.total) commits sur \(push.branch)")
                rows.append(ModuleRow(id: "push-\(push.eventID)", title: title, detail: push.actor, state: .busy, label: "push",
                                      date: push.date, section: first ? section : nil,
                                      action: "https://github.com/\(repo)/commits/\(push.branch)"))
                first = false
                for commit in push.commits.prefix(Self.commitsPerPush) {
                    rows.append(ModuleRow(id: "commit-\(push.eventID)-\(commit.sha)",
                                          title: "  " + (ApprovalRequest.oneLine(commit.message, limit: 70) ?? commit.shortSHA),
                                          detail: "\(commit.shortSHA) · \(commit.author)", state: .neutral, label: "",
                                          action: commit.url?.absoluteString))
                }
            }
            for event in others.filter({ $0.repo == repo }).prefix(2) {
                rows.append(ModuleRow(id: "event-\(event.id)", title: GitHubSummary.sentence(for: event), detail: event.actor,
                                      state: .neutral, label: "", date: event.date, section: first ? section : nil,
                                      action: event.url?.absoluteString))
                first = false
            }
        }
        return rows
    }

    /// A push of the last two minutes, for the folded island.
    static func livePush(_ pushes: [GitHubPush], hidden: Set<String>, now: Date) -> GitHubPush? {
        pushes.filter { !hidden.contains($0.repo) && ($0.date.map { now.timeIntervalSince($0) < 120 } ?? false) }
            .max { $0.eventID < $1.eventID }
    }
}

extension Notification.Name {
    /// Posted by the settings when repositories are hidden or shown again.
    static let githubReposChanged = AppIdentity.notification("githubReposChanged")
}
