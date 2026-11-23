import AppKit
import Network

/// The mails the island can answer: the module keeps it up to date, the sheet reads it.
@MainActor
final class GmailInbox: ObservableObject {
    static let shared = GmailInbox()
    @Published private(set) var mails: [GmailMail] = []
    /// Every account seen in the inbox, filtered or not: the settings list them.
    @Published private(set) var accounts: [String] = []
    func show(_ mails: [GmailMail]) { if mails != self.mails { self.mails = mails } }
    func showAccounts(_ accounts: [String]) { if accounts != self.accounts { self.accounts = accounts } }
}

/// The mails module: the latest mails of the inbox, unread ones first in the figures. Read from
/// Apple's Mail app (every account set up there, no password), or from Gmail with an app
/// password kept in the Keychain; asked every two minutes while the module is selected.
/// Its id stays "gmail" so the settings and the place of the module carry over.
@MainActor
final class GmailModule: YumiModule {
    let id = "gmail"
    var category: ModuleCategory { .day }

    static let pollInterval: TimeInterval = 120
    static let addressKey = "gmail.address"
    static let passwordKey = "gmail-app-password"

    enum Connection: Equatable {
        case notSet, connected, refused, offline
        /// The first look is under way (Mail can take a minute on a large inbox).
        case reading
        /// Mail is the source but is not open, has no account, or the person refused the access.
        case mailClosed, mailNoAccount, mailDenied
    }

    private let credentials: @MainActor () -> (address: String, password: String)?
    private let source: @MainActor () -> MailSource
    private let hiddenAccounts: @MainActor () -> Set<String>
    private let fetch: @Sendable (String, String) async throws -> [GmailMail]
    private let fetchMailApp: @Sendable () async throws -> [GmailMail]
    private let onNewMail: @MainActor (GmailMail, Int) -> Void
    /// Opens the settings, where the address and the app password go.
    private let onConnect: @MainActor () -> Void
    private var onChange: (@MainActor () -> Void)?
    private var polling: Task<Void, Never>?
    private var rowObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var mails: [GmailMail] = []
    private var connection = Connection.reading
    /// The mails already seen, to notice the ones that arrive. nil until the first look.
    private var seen: Set<Int>?
    private var currentSource = MailSource.mailApp

    init(credentials: @escaping @MainActor () -> (address: String, password: String)?,
         source: @escaping @MainActor () -> MailSource = { .gmail },
         hiddenAccounts: @escaping @MainActor () -> Set<String> = { [] },
         fetch: @escaping @Sendable (String, String) async throws -> [GmailMail] = { try await GmailIMAP.latest(address: $0, password: $1) },
         fetchMailApp: @escaping @Sendable () async throws -> [GmailMail] = { try await MailAppScript.latest() },
         onNewMail: @escaping @MainActor (GmailMail, Int) -> Void = { _, _ in },
         onConnect: @escaping @MainActor () -> Void = {}) {
        self.credentials = credentials
        self.source = source
        self.hiddenAccounts = hiddenAccounts
        self.fetchMailApp = fetchMailApp
        self.onConnect = onConnect
        self.fetch = fetch
        self.onNewMail = onNewMail
    }

    var snapshot: ModuleSnapshot {
        GmailSummary.snapshot(mails: mails, connection: connection, now: Date(), source: currentSource)
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        rowObserver = NotificationCenter.default.addObserver(forName: .moduleRowAction, object: nil, queue: .main) { [weak self] note in
            guard note.userInfo?["module"] as? String == "gmail", let row = note.userInfo?["row"] as? String else { return }
            MainActor.assumeIsolated { self?.open(row) }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: .gmailSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        restart()
    }

    func stop() {
        onChange = nil
        polling?.cancel()
        polling = nil
        for observer in [rowObserver, settingsObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        rowObserver = nil
        settingsObserver = nil
    }

    private func restart() {
        polling?.cancel()
        seen = nil
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.look()
                try? await Task.sleep(for: .seconds(GmailModule.pollInterval), tolerance: .seconds(10))
            }
        }
    }

    /// One look at the inbox. Internal so tests can drive it.
    /// A look still running (Mail can take a minute on a large inbox): the next one waits for it.
    private var looking = false

    func look() async {
        guard !looking else { return }
        looking = true
        defer { looking = false }
        let source = source()
        if source != currentSource {
            currentSource = source
            seen = nil
            mails = []
            connection = .reading
            onChange?()
        }
        do {
            let all: [GmailMail]
            switch source {
            case .mailApp:
                all = try await fetchMailApp()
            case .gmail:
                guard let credentials = credentials() else {
                    connection = .notSet
                    show([])
                    onChange?()
                    return
                }
                all = try await fetch(credentials.address, credentials.password)
            }
            connection = .connected
            GmailInbox.shared.showAccounts(MailAccounts.names(in: all))
            let latest = MailAccounts.visible(all, hidden: hiddenAccounts())
            if let seen {
                // Only what matters gets a word: the important mails, never a newsletter
                let arrived = latest.filter { !seen.contains($0.uid) && $0.unread && $0.important }
                if let first = arrived.first { onNewMail(first, arrived.count) }
            }
            seen = (seen ?? []).union(all.map(\.uid))
            show(latest)
        } catch GmailIMAP.Failure.refused {
            connection = .refused
        } catch MailAppScript.Failure.closed {
            connection = .mailClosed
            show([])
        } catch MailAppScript.Failure.noAccount {
            connection = .mailNoAccount
            show([])
        } catch MailAppScript.Failure.denied {
            connection = .mailDenied
            show([])
        } catch {
            if mails.isEmpty { connection = .offline }
        }
        onChange?()
    }

    private func show(_ latest: [GmailMail]) {
        mails = latest
        GmailInbox.shared.show(latest)
    }

    func perform(_ action: ModuleAction) {
        switch connection {
        case .notSet, .refused, .mailDenied, .mailNoAccount:
            onConnect()
        case .mailClosed:
            MailAppScript.openMail()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                await self?.look()
            }
        default:
            if currentSource == .mailApp { MailAppScript.openMail() }
            else if let url = URL(string: "https://mail.google.com/mail/u/0/#inbox") { NSWorkspace.shared.open(url) }
        }
    }

    private func open(_ row: String) {
        guard let uid = Int(row), let mail = mails.first(where: { $0.uid == uid }) else { return }
        if mail.source == .mailApp {
            // message:// opens the mail itself in Mail
            let id = mail.messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            if let url = URL(string: "message://%3C" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) + "%3E") {
                NSWorkspace.shared.open(url)
            }
        } else if let url = mail.url {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notification.Name {
    /// The source, the accounts shown, or Gmail's address or app password changed in the settings.
    static let gmailSettingsChanged = AppIdentity.notification("gmailSettingsChanged")
}

/// What the island shows of the inbox.
enum GmailSummary {
    static func snapshot(mails: [GmailMail], connection: GmailModule.Connection, now: Date,
                         source: MailSource = .gmail) -> ModuleSnapshot {
        let mailApp = source == .mailApp
        var snapshot = ModuleSnapshot(id: "gmail", name: mailApp ? "Mail" : "Gmail", colorHex: mailApp ? "#3E8BFF" : "#EA4335",
                                      status: "", title: "", subtitle: "",
                                      primaryAction: mailApp ? loc("Ouvrir Mail") : loc("Ouvrir Gmail"), secondaryAction: nil)
        snapshot.symbol = "envelope.fill"
        snapshot.primarySymbol = "arrow.up.forward"
        switch connection {
        case .notSet:
            snapshot.title = loc("Branche ta boîte Gmail")
            snapshot.subtitle = loc("Dans Réglages, Modules : ton adresse et un mot de passe d'application.")
            snapshot.primaryAction = loc("Brancher")
            snapshot.primarySymbol = "link"
            return snapshot
        case .refused:
            snapshot.title = loc("Gmail refuse le mot de passe")
            snapshot.subtitle = loc("Il faut un mot de passe d'application de 16 lettres, pas ton mot de passe Google : Réglages, Modules.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .reading:
            snapshot.title = loc("Je lis ta boîte…")
            snapshot.subtitle = mailApp ? loc("Mail met parfois une minute à répondre sur une grosse boîte.") : ""
            return snapshot
        case .mailClosed:
            snapshot.title = loc("Mail est fermé")
            snapshot.subtitle = loc("Ouvre l'app Mail et je lis ta boîte de réception, sans rien y toucher.")
            snapshot.primaryAction = loc("Ouvrir Mail")
            return snapshot
        case .mailNoAccount:
            snapshot.title = loc("Aucun compte dans Mail")
            snapshot.subtitle = loc("Ajoute ton compte dans l'app Mail, ou choisis Gmail dans Réglages, Modules.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .mailDenied:
            snapshot.title = loc("Je n'ai pas accès à Mail")
            snapshot.subtitle = loc("Réglages Système, Confidentialité, Automatisation : autorise Yumi à contrôler Mail.")
            snapshot.primaryAction = loc("Réglages")
            return snapshot
        case .offline where mails.isEmpty:
            snapshot.title = mailApp ? loc("Mail ne répond pas") : loc("Gmail ne répond pas")
            snapshot.subtitle = loc("Je réessaie dans deux minutes.")
            return snapshot
        case .connected, .offline:
            break
        }
        let unread = mails.filter(\.unread).count
        let important = mails.filter { $0.important && $0.unread }.count
        if connection == .reading { return snapshot }
        snapshot.status = important > 0 ? loc("\(important) importants") : unread == 0 ? loc("à jour") : loc("\(unread) non lus")
        snapshot.needsAttention = important > 0
        // The important ones first, then the others, newest first in each
        let mails = mails.filter(\.important) + mails.filter { !$0.important }
        if let latest = mails.first {
            snapshot.title = latest.subject.isEmpty ? loc("(sans objet)") : latest.subject
            snapshot.subtitle = latest.from
        } else {
            snapshot.title = loc("Boîte vide")
        }
        let several = MailAccounts.names(in: mails).count > 1
        snapshot.rows = mails.map { mail in
            ModuleRow(id: String(mail.uid), title: mail.subject.isEmpty ? loc("(sans objet)") : mail.subject,
                      detail: several && !mail.account.isEmpty ? "\(mail.from) · \(mail.account)" : mail.from,
                      state: mail.important && mail.unread ? .waiting : mail.unread ? .busy : .neutral,
                      label: mail.date.map { when($0, now: now) } ?? "",
                      date: mail.date, action: String(mail.uid))
        }
        return snapshot
    }

    /// "14:02" today, "hier", or "13 oct.".
    static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return FrenchText.clock(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return loc("hier") }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
