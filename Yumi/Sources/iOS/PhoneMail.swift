import Foundation
import Observation
import Security
import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The app password of the mail account, in the iPhone's Keychain only.
enum PhoneKeychain {
    private static let service = AppIdentity.keychainService

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key, kSecReturnData as String: true]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ key: String, _ value: String?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// The person's Gmail on the iPhone, the same way as on the Mac: an app password, IMAP to read
/// without marking anything read, SMTP to send an answer only from the « Envoyer » button.
/// No server of Yumi, nothing leaves the iPhone except to Gmail.
@MainActor
@Observable
final class PhoneMail {
    static let addressKey = "phoneGmailAddress"
    static let passwordKey = "phone-gmail-app-password"

    enum State: Equatable { case off, loading, ready, failed(String) }

    private(set) var mails: [GmailMail] = []
    private(set) var state: State = .off
    private(set) var address = UserDefaults.standard.string(forKey: addressKey) ?? ""
    @ObservationIgnored private let studio: Bool

    init(studio: Bool) {
        self.studio = studio
        if studio {
            address = "esteban@gmail.com"
            mails = PhoneStudio.mails
            state = .ready
        } else if isConnected {
            state = .loading
        }
    }

    var isConnected: Bool { studio || (!address.isEmpty && PhoneKeychain.get(Self.passwordKey) != nil) }

    /// What matters first: unread, then the rest; newsletters at the end.
    var shown: [GmailMail] {
        mails.sorted { a, b in
            if a.bulk != b.bulk { return !a.bulk }
            if a.unread != b.unread { return a.unread }
            return (a.date ?? .distantPast) > (b.date ?? .distantPast)
        }
    }

    var unreadCount: Int { mails.filter { $0.unread && !$0.bulk }.count }

    func connect(address: String, password: String) async {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let password = password.replacingOccurrences(of: " ", with: "")
        state = .loading
        do {
            mails = try await GmailIMAP.latest(address: address, password: password, count: 12)
            UserDefaults.standard.set(address, forKey: Self.addressKey)
            PhoneKeychain.set(Self.passwordKey, password)
            self.address = address
            state = .ready
        } catch {
            state = .failed(Self.why(error))
        }
    }

    func disconnect() {
        PhoneKeychain.set(Self.passwordKey, nil)
        UserDefaults.standard.removeObject(forKey: Self.addressKey)
        address = ""
        mails = []
        state = .off
    }

    func refresh() async {
        guard !studio, isConnected, let password = PhoneKeychain.get(Self.passwordKey) else { return }
        do {
            mails = try await GmailIMAP.latest(address: address, password: password, count: 12)
            state = .ready
        } catch {
            state = .failed(Self.why(error))
        }
    }

    func text(of mail: GmailMail) async -> String {
        if studio { return PhoneStudio.mailText }
        guard let password = PhoneKeychain.get(Self.passwordKey) else { return "" }
        return (try? await GmailIMAP.text(of: mail.uid, address: address, password: password)) ?? ""
    }

    /// Sends the answer the person read and edited. Only called by the « Envoyer » button.
    func send(reply body: String, to mail: GmailMail) async throws {
        guard !studio else { return }
        guard let password = PhoneKeychain.get(Self.passwordKey) else { throw GmailSMTP.Failure.refused }
        try await GmailSMTP.send(from: address, password: password, to: mail.replyAddress,
                                 subject: GmailCompose.replySubject(mail.subject),
                                 inReplyTo: mail.messageID, body: body)
    }

    private static func why(_ error: Error) -> String {
        if (error as? GmailIMAP.Failure) == .refused {
            return loc("Gmail refuse l'adresse ou le mot de passe d'application.")
        }
        return loc("Je n'arrive pas à joindre Gmail.")
    }

    // MARK: - Apple's model, on this iPhone

    /// A short summary of the mail, by Apple's model on the iPhone. Nil without the model.
    static func summary(of text: String, subject: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: AppLanguage.isEnglish
                ? "Summarise the mail in one or two short sentences. Say what is asked, if anything. Never make anything up."
                : "Résume le mail en une ou deux phrases courtes, en français. Dis ce qui est demandé, s'il y a une demande. N'invente rien.")
            let answer = try? await session.respond(to: "Objet : \(subject)\n\n\(text.prefix(4000))",
                                                    options: GenerationOptions(maximumResponseTokens: 120))
            return answer?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        return nil
    }

    /// An answer to edit, by Apple's model. Nil without the model: the person writes it.
    static func draft(for text: String, subject: String, name: String?) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), case .available = SystemLanguageModel.default.availability {
            let signature = name.map { "\n\n\($0)" } ?? ""
            let session = LanguageModelSession(instructions: AppLanguage.isEnglish
                ? "Write a short, polite reply to this mail, three sentences at most. No subject line. Never promise anything the mail does not ask."
                : "Écris une réponse courte et polie à ce mail, en français, trois phrases au plus. Pas d'objet. Ne promets rien que le mail ne demande pas.")
            let answer = try? await session.respond(to: "Objet : \(subject)\n\n\(text.prefix(4000))",
                                                    options: GenerationOptions(maximumResponseTokens: 200))
            return answer.map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) + signature }
        }
        #endif
        return nil
    }
}

// MARK: - Views

/// The mails card of the home screen.
struct PhoneMailCard: View {
    let phone: Phone
    @State private var open: GmailMail?
    @State private var connecting = false

    var body: some View {
        let mail = phone.mail
        PhoneCard(title: loc("Mails"), symbol: "envelope", opens: mail.isConnected ? URL(string: "googlegmail://") : nil) {
            if !mail.isConnected {
                Text(loc("Je peux lire tes derniers mails, te les résumer et t'aider à répondre.")).foregroundStyle(.secondary)
                Button(loc("Connecter Gmail")) { connecting = true }
            } else {
                switch mail.state {
                case .loading where mail.mails.isEmpty: ProgressView()
                case .failed(let why): Text(why).foregroundStyle(.secondary)
                default:
                    if mail.mails.isEmpty { Text(loc("Aucun mail.")).foregroundStyle(.secondary) }
                    ForEach(mail.shown.prefix(4)) { item in
                        Button { open = item } label: { PhoneMailRow(mail: item) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $open) { item in PhoneMailSheet(phone: phone, mail: item) }
        .sheet(isPresented: $connecting) { PhoneMailConnect(mail: phone.mail) }
    }
}

struct PhoneMailRow: View {
    let mail: GmailMail

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(mail.unread ? PhoneTheme.violet : .clear).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(mail.from).font(.subheadline.weight(mail.unread ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    if let date = mail.date {
                        Text(date.formatted(Calendar.current.isDateInToday(date) ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(mail.subject).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .contentShape(Rectangle())
    }
}

/// One mail: Yumi's summary, the text, and an answer that leaves only from « Envoyer ».
struct PhoneMailSheet: View {
    let phone: Phone
    let mail: GmailMail
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var summary: String?
    @State private var loading = true
    @State private var replying = false
    @State private var reply = ""
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(mail.subject).font(.title3.weight(.semibold))
                    Text(mail.from).font(.subheadline).foregroundStyle(.secondary)
                    if let summary {
                        Label(summary, systemImage: "sparkles")
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(PhoneTheme.violet.opacity(0.18), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if loading { ProgressView() } else { Text(text).font(.callout).textSelection(.enabled) }
                    if sent {
                        Label(loc("Réponse envoyée."), systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.headline)
                    } else if replying {
                        if mail.replyElsewhere {
                            Text(loc("La réponse partira à \(mail.replyAddress), pas à l'expéditeur.")).font(.footnote).foregroundStyle(.orange)
                        }
                        TextEditor(text: $reply).frame(minHeight: 140).scrollContentBackground(.hidden)
                            .padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        Button {
                            Task { await send() }
                        } label: {
                            Label(sending ? loc("Envoi…") : loc("Envoyer"), systemImage: "paperplane.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(sending || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else if !mail.replyAddress.isEmpty, !mail.bulk {
                        Button { Task { await startReply() } } label: {
                            Label(loc("Répondre"), systemImage: "arrowshape.turn.up.left").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .phoneScreen()
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(loc("Fermer")) { dismiss() } } }
            .task {
                text = await phone.mail.text(of: mail)
                loading = false
                summary = await PhoneMail.summary(of: text, subject: mail.subject)
            }
        }
    }

    private func startReply() async {
        withAnimation { replying = true }
        if let draft = await PhoneMail.draft(for: text, subject: mail.subject, name: phone.memoryBook.name), reply.isEmpty {
            reply = draft
        }
    }

    private func send() async {
        sending = true
        defer { sending = false }
        do {
            try await phone.mail.send(reply: reply, to: mail)
            withAnimation { sent = true }
        } catch {
            self.error = loc("L'envoi a échoué. Rien n'est parti.")
        }
    }
}

/// Connecting Gmail with an app password, explained step by step for anyone.
struct PhoneMailConnect: View {
    let mail: PhoneMail
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(loc("Adresse Gmail"), text: $address)
                        .textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    SecureField(loc("Mot de passe d'application"), text: $password)
                } footer: {
                    Text(loc("Google demande un mot de passe d'application, pas ton mot de passe habituel. Crée-le sur la page de ton compte Google (validation en deux étapes activée), puis colle-le ici. Il reste dans le trousseau de cet iPhone."))
                }
                Section {
                    Link(loc("Créer un mot de passe d'application"), destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                }
                if case .failed(let why) = mail.state {
                    Section { Text(why).foregroundStyle(.red) }
                }
            }
            .phoneScreen()
            .navigationTitle(loc("Connecter Gmail"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(loc("Annuler")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if mail.state == .loading { ProgressView() } else {
                        Button(loc("Connecter")) {
                            Task {
                                await mail.connect(address: address, password: password)
                                if mail.state == .ready { dismiss() }
                            }
                        }
                        .disabled(address.isEmpty || password.isEmpty)
                    }
                }
            }
        }
    }
}
