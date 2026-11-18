import Foundation

// MARK: - The three pages of the island's GitHub view
// Activity (the contribution grid), recent (the latest commits of every repository) and
// repositories (one line each: commits, pull requests, checks). Pure: what the module
// already knows in, lines out. No request of its own.

/// A page of the GitHub view, remembered between openings.
enum GitHubPage: Int, CaseIterable, Sendable {
    case activity, recent, repos

    static let storageKey = "island.github.page"

    var title: String {
        switch self {
        case .activity: return loc("Activité")
        case .recent:   return loc("Récent")
        case .repos:    return loc("Dépôts")
        }
    }

    /// The row key of its lines in `ModuleSnapshot.pages`; nil for the grid.
    var rowsKey: String? {
        switch self {
        case .activity: return nil
        case .recent:   return "recent"
        case .repos:    return "repos"
        }
    }

    var hasPrevious: Bool { self != Self.allCases.first }
    var hasNext: Bool { self != Self.allCases.last }

    /// One page further or back; the first and the last pages stay where they are.
    func moved(by step: Int) -> GitHubPage {
        let index = min(max(rawValue + step, 0), Self.allCases.count - 1)
        return GitHubPage(rawValue: index) ?? self
    }

    /// The page kept in the defaults, the activity one when none or an unknown one.
    static func stored(in defaults: UserDefaults = .standard) -> GitHubPage {
        GitHubPage(rawValue: defaults.integer(forKey: storageKey)) ?? .activity
    }

    func store(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.storageKey) }
}

extension Notification.Name {
    /// Posted by the island's keyboard monitor: `userInfo["step"]` is -1 or 1.
    static let githubPageStep = AppIdentity.notification("githubPageStep")
}

enum GitHubPages {
    static let recentLimit = 12
    /// Pushes shown when a repository is opened.
    static let repoPushes = 5
    /// The action of a repository line: its latest pushes open in place.
    static let repoAction = "yumi-repo:"
    /// The action of the line that goes back to every repository.
    static let backAction = "yumi-repos"

    /// One repository opened: a line back, then its latest pushes. Each push unfolds into its
    /// commits and the files it touched; the button under them opens the comparison on GitHub.
    static func repo(_ repo: String, pushes: [GitHubPush], loading: Bool) -> [ModuleRow] {
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        var rows = [ModuleRow(id: "repo-back", title: loc("‹ Tous les dépôts"), detail: name, state: .neutral, label: "",
                              action: backAction)]
        let shown = pushes.filter { $0.repo == repo }.sorted { $0.eventID > $1.eventID }.prefix(repoPushes)
        if shown.isEmpty {
            rows.append(ModuleRow(id: "repo-empty", title: loading ? loc("Je regarde…") : loc("Aucun push récent."),
                                  detail: "", state: .neutral, label: ""))
            return rows
        }
        for push in shown {
            let title = push.total == 1 ? loc("Un commit sur \(push.branch)") : loc("\(push.total) commits sur \(push.branch)")
            var details = push.commits.map { commit in
                (ApprovalRequest.oneLine(commit.message, limit: 80) ?? commit.shortSHA) + " (\(commit.shortSHA))"
            }
            if push.total > push.commits.count {
                details.append("· " + loc("et \(push.total - push.commits.count) de plus"))
            }
            details += push.files.map { "· \($0.name)  +\($0.additions) −\($0.deletions)" }
            var row = ModuleRow(id: "repo-push-\(push.eventID)", title: title, detail: push.actor, state: .busy, label: "push",
                                date: push.date, action: compareURL(push))
            row.details = details
            row.actionLabel = loc("Ouvrir sur GitHub")
            rows.append(row)
        }
        return rows
    }

    /// Where the push reads on GitHub: its comparison, or its head, or the branch.
    static func compareURL(_ push: GitHubPush) -> String {
        if !push.head.isEmpty, !push.before.isEmpty, !push.before.allSatisfy({ $0 == "0" }) {
            return "https://github.com/\(push.repo)/compare/\(push.before.prefix(12))...\(push.head.prefix(12))"
        }
        if !push.head.isEmpty { return "https://github.com/\(push.repo)/commit/\(push.head)" }
        return "https://github.com/\(push.repo)/commits/\(push.branch)"
    }

    /// The latest commits, every repository mixed, newest first: repository, branch, message, when.
    static func recent(pushes: [GitHubPush], hidden: Set<String>, limit: Int = recentLimit) -> [ModuleRow] {
        var rows: [ModuleRow] = []
        for push in pushes.filter({ !hidden.contains($0.repo) }).sorted(by: { $0.eventID > $1.eventID }) {
            let place = "\(push.repoName) · \(push.branch)"
            if push.commits.isEmpty {
                let title = push.total == 1 ? loc("Un commit sur \(push.branch)") : loc("\(push.total) commits sur \(push.branch)")
                rows.append(ModuleRow(id: "recent-\(push.eventID)", title: title, detail: push.repoName, state: .busy,
                                      label: "push", date: push.date,
                                      action: "https://github.com/\(push.repo)/commits/\(push.branch)"))
            }
            for commit in push.commits {
                rows.append(ModuleRow(id: "recent-\(push.eventID)-\(commit.sha)",
                                      title: ApprovalRequest.oneLine(commit.message, limit: 70) ?? commit.shortSHA,
                                      detail: place, state: .busy, label: commit.shortSHA, date: push.date,
                                      action: commit.url?.absoluteString ?? "https://github.com/\(push.repo)/commit/\(commit.sha)"))
            }
            if rows.count >= limit { break }
        }
        return Array(rows.prefix(limit))
    }

    /// One line per followed repository (and per repository pushed to this week): commits of
    /// the day and of the week, open pull requests, the state of their checks.
    static func repos(followed: [String], pushes: [GitHubPush], pulls: [GitHubPull], hidden: Set<String>,
                      now: Date, calendar: Calendar = .current) -> [ModuleRow] {
        let shownPushes = pushes.filter { !hidden.contains($0.repo) }
        let shownPulls = pulls.filter { !hidden.contains($0.repo) }
        let counts = GitHubActivity.counts(shownPushes, now: now, calendar: calendar)
        var names: [String] = []
        for name in followed + shownPushes.sorted(by: { $0.eventID > $1.eventID }).map(\.repo) + shownPulls.map(\.repo)
            where !hidden.contains(name) && !names.contains(name) {
            names.append(name)
        }
        return names.map { repo in
            let name = repo.split(separator: "/").last.map(String.init) ?? repo
            let count = counts[repo] ?? (0, 0)
            let open = shownPulls.filter { $0.repo == repo }
            var parts = [count.week > 0 ? loc("\(count.today) aujourd'hui, \(count.week) cette semaine") : loc("rien cette semaine")]
            if !open.isEmpty { parts.append(open.count == 1 ? loc("une PR ouverte") : loc("\(open.count) PR ouvertes")) }
            var row = ModuleRow(id: "repo-\(repo)", title: name, detail: parts.joined(separator: " · "), state: .neutral,
                                label: "", action: repoAction + repo)
            let checks = open.compactMap(\.checks)
            if checks.contains(.failed) {
                row.state = .failure; row.label = loc("CI rouge")
            } else if checks.contains(.running) {
                row.state = .busy; row.label = loc("CI en cours")
            } else if checks.contains(.passed) {
                row.state = .success; row.label = loc("CI verte")
            }
            return row
        }
    }
}
