import AppKit
import SwiftUI

// What the island knows about Yumi himself: his version, a newer one on GitHub, and the
// "Envoyer un retour" link. Never downloads or installs anything: it only says it.

@MainActor
final class YumiUpdates: ObservableObject {
    static let shared = YumiUpdates()

    static let enabledKey = "updateCheckEnabled"
    private static let lastCheckKey = "updateLastCheck"
    private static let announcedKey = "updateAnnounced"
    /// The newer release found, kept between launches: ["tag": …, "page": …].
    private static let foundKey = "updateFound"
    nonisolated private static let remarkPrefix = "update-"

    /// "0.1.0-alpha", from the Info.plist.
    static var installed: String {
        Bundle.main.object(forInfoDictionaryKey: "YumiDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// A newer release: its tag and its page.
    @Published private(set) var newer: (tag: String, page: URL)?

    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    /// At launch, then once a day at most. Nothing while filming or when switched off.
    func start() {
        guard !StudioMode.isOn else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .remarkAccepted, object: nil, queue: .main) { note in
            guard let id = note.userInfo?["id"] as? String, id.hasPrefix(Self.remarkPrefix) else { return }
            MainActor.assumeIsolated {
                YumiUpdates.shared.openRelease()
                YumiUpdates.shared.clear(id)
            }
        })
        observers.append(center.addObserver(forName: .remarkDismissed, object: nil, queue: .main) { note in
            guard let id = note.userInfo?["id"] as? String, id.hasPrefix(Self.remarkPrefix) else { return }
            MainActor.assumeIsolated { YumiUpdates.shared.clear(id) }
        })
        restore()
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { YumiUpdates.shared.checkIfDue() }
        }
        timer?.tolerance = 600
    }

    var enabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: Self.enabledKey)
            objectWillChange.send()
            if newValue { checkIfDue() } else { newer = nil }
        }
    }

    /// The word about the new version is said: it leaves the place to the core's remarks.
    private func clear(_ id: String) {
        if AppState.shared.remark?.id == id { AppState.shared.remark = nil }
    }

    func openRelease() {
        if let page = newer?.page { NSWorkspace.shared.open(page) }
    }

    /// What was found on an earlier day, as long as it is still newer than what runs.
    private func restore() {
        guard enabled, let found = defaults.dictionary(forKey: Self.foundKey) as? [String: String],
              let tag = found["tag"], let page = found["page"].flatMap(URL.init(string:)),
              let version = YumiVersion(tag), let mine = YumiVersion(Self.installed), mine < version else { return }
        newer = (tag, page)
    }

    private func checkIfDue() {
        guard enabled, !StudioMode.isOn else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) >= 86_400 else { return }
        defaults.set(Date.now, forKey: Self.lastCheckKey)
        Task { await check() }
    }

    /// `/releases?per_page=1` gives the newest release, pre-releases included, which
    /// `/releases/latest` leaves out. No token: the public quota is plenty for once a day.
    private func check() async {
        guard let url = URL(string: "https://api.github.com/repos/estebanbaigts/Yumi/releases?per_page=1") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let release = list.first(where: { $0["draft"] as? Bool != true }),
              let tag = release["tag_name"] as? String,
              let page = (release["html_url"] as? String).flatMap(URL.init(string:)),
              let found = YumiVersion(tag), let mine = YumiVersion(Self.installed), mine < found else { return }
        guard enabled else { return }
        newer = (tag, page)
        defaults.set(["tag": tag, "page": page.absoluteString], forKey: Self.foundKey)
        announce(tag)
    }

    /// Once per version, in the folded island, if he has nothing else to say.
    private func announce(_ tag: String) {
        guard defaults.string(forKey: Self.announcedKey) != tag, AppState.shared.remark == nil else { return }
        defaults.set(tag, forKey: Self.announcedKey)
        AppState.shared.remark = YumiRemark(id: Self.remarkPrefix + tag, text: loc("Une nouvelle version de Yumi est là"),
                                            mood: .happy, action: "Voir", duration: 12)
    }

    // MARK: Feedback

    /// "Envoyer un retour": the form that needs no account, with the version of Yumi filled in.
    static func feedbackURL() -> URL? { Feedback.formURL(version: installed) }

    /// The same, as a GitHub issue, for those who have an account.
    static func githubFeedbackURL() -> URL? {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let notch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }
        return Feedback.url(version: installed, macOS: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                            model: model(), notch: notch)
    }

    /// "Mac15,3": the hardware model, nothing about the person.
    private static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "inconnu" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
