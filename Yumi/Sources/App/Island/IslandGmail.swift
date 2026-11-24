import AppKit
import SwiftUI

// The mail sheet: the important mails first, the rest under them. A mail chosen, Yumi reads it
// and suggests an answer the person can change. From Apple's Mail, "Ouvrir dans Mail" opens it as
// a draft the person sends from Mail; from Gmail, "Envoyer" sends it from their address.
// "Annuler" drops it. Nothing leaves without the person's own click.

struct GmailSheet: View {
    @ObservedObject private var inbox = GmailInbox.shared
    @State private var chosen: GmailMail?
    @State private var draft = ""
    @State private var step = Step.reading
    /// The text of the mail opened, read when it is opened. nil while it is read.
    @State private var text: String?

    enum Step: Equatable { case reading, thinking, editing, sending, sent, failed(String) }

    private var credentials: (address: String, password: String)? {
        guard let address = UserDefaults.standard.string(forKey: GmailModule.addressKey), !address.isEmpty,
              let password = KeychainStore.shared.get(GmailModule.passwordKey), !password.isEmpty else { return nil }
        return (address, password)
    }

    private var source: MailSource { MailSource.current(gmailConnected: credentials != nil) }
    private var mailApp: Bool { source == .mailApp }
    private var severalAccounts: Bool { MailAccounts.names(in: inbox.mails).count > 1 }

    /// When the inbox is empty: what the module says (Mail closed, access refused, no account).
    private var emptyText: String {
        if let module = AppState.shared.modules.first(where: { $0.id == "gmail" }), !module.subtitle.isEmpty, module.status.isEmpty {
            return module.title + ". " + module.subtitle
        }
        if mailApp { return loc("Rien de neuf dans ta boîte.") }
        return credentials == nil ? loc("Branche Gmail dans Réglages, Modules.") : loc("Rien de neuf dans ta boîte.")
    }

    var body: some View {
        Group {
            if let chosen {
                reply(to: chosen)
            } else {
                list
            }
        }
        // An answer being written keeps the island open when the person clicks elsewhere
        .onChange(of: step) { _, step in
            IslandModel.shared.hasDraft = [.thinking, .editing, .sending].contains(step)
        }
        .onDisappear { IslandModel.shared.hasDraft = false }
        // The filming mode plays the sheet's steps with example mails, without reading or sending
        .onReceive(NotificationCenter.default.publisher(for: .yumiStudioGmail)) { note in
            guard IslandStudio.isOn, let step = note.object as? StudioGmail else { return }
            switch step {
            case .choose(let uid): if let mail = inbox.mails.first(where: { $0.uid == uid }) { choose(mail) }
            case .think: withAnimation(.islandSpring(0.4)) { self.step = .thinking }
            case .draft(let text): draft = text; if self.step != .editing { withAnimation(.islandSpring(0.4)) { self.step = .editing } }
            }
        }
    }

    // MARK: The inbox

    private var list: some View {
        let important = inbox.mails.filter(\.important)
        let others = inbox.mails.filter { !$0.important }
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                if inbox.mails.isEmpty {
                    ActSub(text: emptyText)
                }
                // Every mail of the inbox, scrolling: the important ones first
                if !important.isEmpty {
                    section(loc("Importants"), important[...], color: IslandTheme.amber)
                }
                if !others.isEmpty {
                    section(loc("Le reste"), others[...], color: IslandTheme.muted)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private func section(_ title: String, _ mails: ArraySlice<GmailMail>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(IslandTheme.text(9.5, .bold))
                .tracking(0.8)
                .foregroundStyle(color)
            ForEach(mails) { mail in
                Button { choose(mail) } label: { MailLine(mail: mail, showsAccount: severalAccounts) }
                    .buttonStyle(.plain)
            }
        }
    }

    // MARK: Answering one mail

    @ViewBuilder private func reply(to mail: GmailMail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button { withAnimation(.islandSpring(0.4)) { reset() } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(loc("Retour"))
                VStack(alignment: .leading, spacing: 1) {
                    Text(mail.subject.isEmpty ? loc("(sans objet)") : mail.subject)
                        .font(IslandTheme.text(12.5, .semibold)).lineLimit(1)
                    Text(loc("De \(mail.from)")).font(IslandTheme.text(11)).foregroundStyle(IslandTheme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                TextButton(label: mail.source == .mailApp ? loc("Ouvrir dans Mail") : loc("Ouvrir dans Gmail")) {
                    NotificationCenter.default.post(name: .moduleRowAction, object: nil,
                                                    userInfo: ["module": "gmail", "row": String(mail.uid)])
                }
                .fixedSize()
            }
            if step == .reading || step == .thinking {
                // What the mail says, scrolling
                ScrollView(.vertical, showsIndicators: true) {
                    Text(text ?? loc("Je lis le mail…"))
                        .font(IslandTheme.text(12.5))
                        .foregroundStyle(text == nil ? IslandTheme.muted : IslandTheme.fg)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 108)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
            }
            switch step {
            case .reading:
                HStack {
                    Button { suggest(for: mail) } label: {
                        Label(loc("Yumi propose une réponse"), systemImage: "sparkles")
                            .font(IslandTheme.text(12, .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(IslandTheme.violet))
                    }
                    .buttonStyle(RoundPress())
                    if mail.bulk {
                        ActSub(text: loc("Mail automatique : pas besoin de répondre."))
                    }
                }
            case .thinking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    ActSub(text: loc("Je lis le mail et j'écris une réponse…"))
                }
            case .editing, .sending, .failed:
                TextEditor(text: $draft)
                    .font(IslandTheme.text(12.5))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 104)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                    .disabled(step == .sending)
                HStack(spacing: 8) {
                    Text(recipientLine(mail)).font(IslandTheme.text(11))
                        .foregroundStyle(mail.replyElsewhere || mail.replyAddress.isEmpty ? IslandTheme.amber : IslandTheme.muted).lineLimit(1)
                        .help(mail.replyElsewhere ? loc("Ce mail demande qu'on réponde à une autre adresse que celle de l'expéditeur.") : "")
                    if case .failed(let reason) = step {
                        Text(reason).font(IslandTheme.text(11, .medium)).foregroundStyle(IslandTheme.red).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button(loc("Annuler")) { withAnimation(.islandSpring(0.4)) { reset() } }
                        .buttonStyle(.plain)
                        .font(IslandTheme.text(12, .medium))
                        .foregroundStyle(IslandTheme.muted)
                    Button { send(mail) } label: {
                        Label(mail.source == .mailApp ? loc("Ouvrir dans Mail")
                                : step == .sending ? loc("Envoi…") : loc("Envoyer"),
                              systemImage: mail.source == .mailApp ? "envelope.open.fill" : "paperplane.fill")
                            .font(IslandTheme.text(12, .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(IslandTheme.green))
                    }
                    .buttonStyle(RoundPress())
                    .disabled(step == .sending || mail.replyAddress.isEmpty || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .sent:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(IslandTheme.green)
                    ActSub(text: mail.source == .mailApp
                           ? loc("Brouillon ouvert dans Mail : relis-le et envoie-le toi-même.")
                           : loc("Envoyé à \(mail.replyAddress)."))
                }
            }
        }
    }

    private func choose(_ mail: GmailMail) {
        withAnimation(.islandSpring(0.4)) {
            chosen = mail
            step = .reading
            draft = ""
            text = nil
        }
        IslandActions.tap()
        read(mail)
    }

    /// Reads the mail's text from where it lives: Apple's Mail or Gmail.
    private func read(_ mail: GmailMail) {
        let credentials = credentials
        Task {
            var body = ""
            if mail.source == .mailApp {
                body = (try? await MailAppScript.text(of: mail)) ?? ""
            } else if let credentials {
                body = (try? await GmailIMAP.text(of: mail.uid, address: credentials.address, password: credentials.password)) ?? ""
            }
            guard chosen?.uid == mail.uid else { return }
            let clean = body.trimmingCharacters(in: .whitespacesAndNewlines)
            text = clean.isEmpty ? loc("Je n'arrive pas à lire ce mail. Ouvre-le dans ta boîte.") : clean
        }
    }

    private func reset() {
        chosen = nil
        draft = ""
        step = .reading
    }

    /// Reads the mail, then asks the model for a short answer in its language.
    /// Who the answer goes to, said before the click: a Reply-To that is not the sender is pointed out.
    private func recipientLine(_ mail: GmailMail) -> String {
        if mail.replyAddress.isEmpty { return loc("Pas d'adresse valide pour répondre.") }
        var line = mail.account.isEmpty ? loc("À \(mail.replyAddress)") : loc("À \(mail.replyAddress), depuis \(mail.account)")
        if mail.replyElsewhere { line += " " + loc("(pas l'adresse de l'expéditeur)") }
        return line
    }

    private func suggest(for mail: GmailMail) {
        let credentials = credentials
        guard mail.source == .mailApp || credentials != nil else { return }
        step = .thinking
        IslandModel.shared.setMood(.thinking)
        let name = AppState.shared.userName
        Task {
            let text: String
            if mail.source == .mailApp {
                text = (try? await MailAppScript.text(of: mail)) ?? ""
            } else if let credentials {
                text = (try? await GmailIMAP.text(of: mail.uid, address: credentials.address, password: credentials.password)) ?? ""
            } else {
                text = ""
            }
            let request = LLMRequest(
                system: """
                Tu es Yumi et tu aides la personne à répondre à un mail. Écris seulement le texte de la réponse, \
                sans objet ni explication : court, naturel, poli, dans la langue du mail, au ton du mail. \
                N'invente aucun fait, aucune date, aucun engagement : là où il faut une information que tu n'as pas, \
                écris [à compléter]. \(name.map { "Signe « \($0) »." } ?? "Ne signe pas.")
                """,
                messages: [LLMMessage(role: .user, content: """
                De : \(mail.from)
                Objet : \(mail.subject)

                \(String(text.prefix(5000)))
                """)],
                expectsJSON: false,
                maxOutputTokens: 700)
            do {
                let answer = try await EngineFactory.planner.complete(request)
                await MainActor.run {
                    draft = answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    step = .editing
                    IslandModel.shared.setMood(nil)
                    IslandModel.shared.pose(.pop)
                }
            } catch {
                await MainActor.run {
                    step = .failed(loc("Aucun moteur ne répond : écris ta réponse ici."))
                    IslandModel.shared.setMood(nil)
                }
            }
        }
    }

    /// The click on "Envoyer" (Gmail) or "Ouvrir dans Mail": the only way an answer leaves. Mail
    /// only gets a draft; the person sends it from there.
    private func send(_ mail: GmailMail) {
        guard !mail.replyAddress.isEmpty else { return }
        let body = draft
        if mail.source == .mailApp {
            step = .sending
            Task {
                do {
                    try await MailAppScript.openDraft(to: mail.replyAddress, subject: GmailCompose.replySubject(mail.subject), body: body)
                    await MainActor.run { step = .sent; IslandModel.shared.pose(.pop) }
                } catch MailAppScript.Failure.denied {
                    await MainActor.run { step = .failed(loc("Mail refuse : autorise Yumi dans Réglages Système, Automatisation.")) }
                } catch {
                    await MainActor.run { step = .failed(loc("Mail n'a pas ouvert le brouillon, rien n'est parti.")) }
                }
            }
            return
        }
        guard let credentials else { return }
        step = .sending
        Task {
            do {
                try await GmailSMTP.send(from: credentials.address, password: credentials.password, to: mail.replyAddress,
                                         subject: GmailCompose.replySubject(mail.subject), inReplyTo: mail.messageID, body: body)
                await MainActor.run {
                    step = .sent
                    SoundEngine.shared.play("send")
                    IslandModel.shared.pose(.celebrate)
                }
            } catch {
                await MainActor.run { step = .failed(loc("L'envoi a échoué, rien n'est parti.")) }
            }
        }
    }
}

/// One mail in the list: unread dot, sender, subject, account when there are several, time.
private struct MailLine: View {
    let mail: GmailMail
    var showsAccount = false
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(mail.unread ? (mail.important ? IslandTheme.amber : IslandTheme.blue) : Color.clear)
                .frame(width: 6, height: 6)
            Text(mail.from)
                .font(IslandTheme.text(12, mail.unread ? .semibold : .regular))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            Text(mail.subject.isEmpty ? loc("(sans objet)") : mail.subject)
                .font(IslandTheme.text(12))
                .foregroundStyle(mail.unread ? IslandTheme.fg : IslandTheme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsAccount, !mail.account.isEmpty {
                Text(mail.account)
                    .font(IslandTheme.text(9.5, .semibold))
                    .foregroundStyle(IslandTheme.muted)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .fixedSize()
            }
            Text(mail.date.map { GmailSummary.when($0, now: .now) } ?? "")
                .font(IslandTheme.text(10.5))
                .foregroundStyle(IslandTheme.muted)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
