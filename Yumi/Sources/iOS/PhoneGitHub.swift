import Foundation
import Observation

/// GitHub on the iPhone, without a Mac: the person's own token (kept in this iPhone's keychain),
/// only api.github.com is asked. The same reading of the events as the Mac's module.
@MainActor
@Observable
final class PhoneGitHub {
    static let keyName = "github-token"

    private(set) var login: String?
    private(set) var events: [GitHubEvent] = []
    private(set) var failed: String?
    private(set) var loading = false

    var isConnected: Bool { PhoneKeychain.get(Self.keyName)?.nonEmptyTrimmed != nil }

    func connect(token: String) async {
        PhoneKeychain.set(Self.keyName, token.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty)
        await refresh()
    }

    func disconnect() {
        PhoneKeychain.set(Self.keyName, nil)
        login = nil
        events = []
    }

    func refresh() async {
        guard let token = PhoneKeychain.get(Self.keyName)?.nonEmptyTrimmed else { return }
        loading = true
        defer { loading = false }
        guard let user = await get("/user", token), let me = GitHubFeed.user(from: user) else {
            failed = loc("GitHub refuse ce jeton. Vérifie-le, ou crée-en un nouveau.")
            return
        }
        failed = nil
        login = me.login
        var all: [GitHubEvent] = []
        for (feed, received) in [("events", false), ("received_events", true)] {
            if let data = await get("/users/\(me.login)/\(feed)?per_page=40", token) {
                all += GitHubFeed.events(from: data, login: me.login, received: received)
            }
        }
        var seen = Set<Int64>()
        events = all.filter { seen.insert($0.id).inserted }.sorted { $0.id > $1.id }
    }

    /// One line per event, as Yumi says it.
    var lines: [String] { events.prefix(20).map { GitHubSummary.sentence(for: $0) } }

    private func get(_ path: String, _ token: String) async -> Data? {
        guard let url = URL(string: "https://api.github.com" + path) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
