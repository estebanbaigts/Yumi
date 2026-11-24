import SwiftUI

// MARK: - Yumi

/// Yumi himself, drawn by the same engine and renderer as in the notch of the Mac. The same
/// character on every screen (`PhoneCharacter`): a tap makes him jump and say the next thing,
/// the finger is followed by his eyes.
struct PhoneYumi: View {
    let character: PhoneCharacter
    var size: CGFloat = 160
    var showsRemark = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                YumiStage(engine: character.engine, paused: !character.onScreen, followsPointer: false)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let x = (drag.location.x - geo.size.width / 2) / max(geo.size.width, 1)
                            let y = (drag.location.y - geo.size.height / 2) / max(geo.size.height, 1)
                            character.look(at: CGPoint(x: tanh(x * 3), y: tanh(y * 3)))
                        }
                        .onEnded { drag in
                            character.look(at: nil)
                            // A touch that did not travel is a tap
                            if hypot(drag.translation.width, drag.translation.height) < 8 { character.tapped() }
                        })
            }
            .frame(width: size, height: size)
            .background {
                // The home screen tells the opening where he lives
                if showsRemark {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { character.homeFrame = geo.frame(in: .global) }
                            .onChange(of: geo.frame(in: .global)) { _, frame in character.homeFrame = frame }
                    }
                }
            }
            if showsRemark, !character.remark.isEmpty {
                Text(character.remark)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(PhoneTheme.rim.opacity(0.5), lineWidth: 0.8))
                    .id(character.remarkID)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: character.remarkID)
        .onAppear { character.appear() }
        .onReceive(NotificationCenter.default.publisher(for: .botDizzy)) { _ in character.dizzy() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(AppIdentity.characterName))
        .accessibilityAddTraits(.isButton)
    }
}

extension View {
    /// After the opening, the home screen's content comes in under him, one piece after the other.
    func phoneReveal(_ shown: Bool, step: Int) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.86).delay(Double(step) * 0.06), value: shown)
    }
}

/// A Yumi of his own for a sheet: no greeting, no sound, only the state he shows.
struct PhoneMiniYumi: View {
    var state: BotState
    @State private var engine = BotEngine()

    var body: some View {
        YumiStage(engine: engine, followsPointer: false)
            .onAppear {
                engine.setLook(accent: .current(), costume: .current())
                engine.setState(state, force: true)
            }
            .accessibilityHidden(true)
    }
}

/// The Mac's requests waiting for an answer, at the top of the home screen. « Autoriser » asks
/// for Face ID first; the answer then shows a big ✓ while the Mac checks it.
struct PhoneMacRequests: View {
    let mac: LinkSnapshot

    static func live(_ mac: LinkSnapshot) -> [LinkApproval] { mac.approvals.filter { $0.expiresAt > Date() } }

    var body: some View {
        PhoneCard(title: loc("Ton accord"), symbol: "hand.raised.fill") {
            ForEach(Self.live(mac)) { approval in
                VStack(alignment: .leading, spacing: 10) {
                    Text(source(approval)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(approval.summary).font(.headline)
                    if let allowed = PhoneLink.shared.answered[approval.id] {
                        HStack(spacing: 10) {
                            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 34)).foregroundStyle(allowed ? .green : .secondary)
                                .transition(.scale.combined(with: .opacity))
                            Text(allowed ? loc("Envoyé. Le Mac vérifie avant d'agir.") : loc("Refusé."))
                                .font(.subheadline)
                        }
                    } else {
                        HStack {
                            Button(loc("Refuser"), role: .destructive) { Task { await PhoneLink.shared.answer(approval, allow: false) } }
                                .buttonStyle(.bordered)
                            Button { Task { await PhoneLink.shared.answer(approval, allow: true) } } label: {
                                Label(loc("Autoriser"), systemImage: "faceid")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Text(loc("Expire à \(approval.expiresAt.formatted(date: .omitted, time: .shortened)).")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                .animation(.spring(duration: 0.35), value: PhoneLink.shared.answered[approval.id])
            }
        }
    }

    private func source(_ approval: LinkApproval) -> String {
        guard let session = mac.sessions.first(where: { $0.id == approval.sessionID }) else { return mac.deviceName }
        return "\(session.agent) · \(session.project)"
    }
}

/// What the Mac follows: its sessions, then GitHub. Says when the Mac was last heard from.
struct PhoneSessionsCard: View {
    let mac: LinkSnapshot

    var body: some View {
        PhoneCard(title: mac.deviceName, symbol: "laptopcomputer") {
            Text(PhoneSessionsCard.presence(mac)).font(.caption).foregroundStyle(.secondary)
            if mac.sessions.isEmpty {
                Text(loc("Aucune session en cours.")).foregroundStyle(.secondary)
            }
            ForEach(mac.sessions) { session in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.project).font(.body.weight(.semibold))
                        Text(session.agent).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(session.status).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if !mac.github.isEmpty {
                Divider().opacity(0.4)
                ForEach(mac.github, id: \.self) { line in
                    Label(line, systemImage: "arrow.triangle.branch").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The Mac sends its picture at least once a minute while it runs.
    static func presence(_ mac: LinkSnapshot, now: Date = Date()) -> String {
        if now.timeIntervalSince(mac.sentAt) < 180 { return loc("En ligne") }
        return loc("Vu \(mac.sentAt.formatted(.relative(presentation: .named)))")
    }
}

struct PhoneCard<Content: View>: View {
    let title: String
    let symbol: String
    /// The app a tap on the card opens (Calendar, Reminders, Weather), when there is one.
    var opens: URL? = nil
    /// The « + » of the card (add an event, a reminder), when there is one.
    var add: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    .foregroundStyle(PhoneTheme.rim)
                Spacer()
                if let add {
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(PhoneTheme.violet)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(loc("Ajouter")))
                } else if opens != nil {
                    Image(systemName: "arrow.up.forward.app").font(.footnote).foregroundStyle(.secondary)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .phoneCard()
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture { if let opens { openURL(opens) } }
        .accessibilityAddTraits(opens == nil ? [] : .isButton)
    }
}

/// The apps of the iPhone the cards open.
enum PhoneApps {
    static let calendar = URL(string: "calshow:")
    static let reminders = URL(string: "x-apple-reminderkit://")
    static let weather = URL(string: "weather://")
}

// MARK: - Chat

struct PhoneChatView: View {
    let phone: Phone
    @State private var draft = ""
    @FocusState private var typing: Bool

    var body: some View {
        Group {
            VStack(spacing: 0) {
                // He stays at the top of the conversation: he listens, thinks, rejoices
                PhoneYumi(character: phone.character, size: 80)
                    .padding(.vertical, 4)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if phone.chat.messages.isEmpty {
                                Text(loc("Dis-moi ce dont tu as besoin.")).foregroundStyle(.secondary).padding(.top, 24)
                            }
                            ForEach(phone.chat.messages) { message in
                                PhoneBubble(message: message).id(message.id)
                            }
                            if phone.chat.isThinking {
                                HStack { ProgressView(); Spacer() }.padding(.horizontal, 4)
                            }
                        }
                        .padding(16)
                    }
                    // The keyboard goes away by dragging the conversation down or tapping it,
                    // so the tabs come back
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { typing = false }
                    .onChange(of: phone.chat.messages.count) {
                        if let last = phone.chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    }
                }
                HStack(spacing: 8) {
                    TextField(loc("Écris à Yumi"), text: $draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($typing)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(PhoneTheme.rim.opacity(0.4), lineWidth: 0.8))
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up.circle.fill").font(.title)
                            .foregroundStyle(PhoneTheme.rim)
                    }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || phone.chat.isThinking)
                        .accessibilityLabel(Text(loc("Envoyer")))
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .phoneScreen()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(loc("OK")) { typing = false }
                }
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await phone.chat.send(text) }
    }
}

struct PhoneBubble: View {
    let message: PhoneMessage

    var body: some View {
        HStack {
            if message.role == .person { Spacer(minLength: 48) }
            Text(message.text)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(message.role == .person ? AnyShapeStyle(PhoneTheme.rim) : AnyShapeStyle(.white.opacity(0.08)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if message.role == .yumi { Spacer(minLength: 48) }
        }
    }
}

// MARK: - First launch

/// Yumi asks the person's first name the first time, the way he does on the Mac.
struct PhoneNameSheet: View {
    let phone: Phone
    @State private var name = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 18) {
            PhoneMiniYumi(state: .idle).frame(width: 110, height: 110).padding(.top, 28)
            Text(loc("Comment tu t'appelles ?")).font(.title2.weight(.bold))
            Text(loc("Je le garde sur ton iPhone, pour te dire bonjour comme il faut."))
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TextField(loc("Ton prénom"), text: $name)
                .textContentType(.givenName)
                .submitLabel(.done)
                .focused($typing)
                .multilineTextAlignment(.center)
                .font(.title3)
                .padding(.vertical, 12)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(PhoneTheme.rim.opacity(0.5), lineWidth: 0.8))
                .onSubmit { phone.answerName(name) }
            Spacer()
            Button { phone.answerName(name) } label: {
                Text(loc("C'est moi")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(loc("Plus tard")) { phone.answerName(nil) }
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .presentationDetents([.medium, .large])
        .onAppear { typing = true }
    }
}

// MARK: - Approval

/// The only place an action of the agent is allowed on the iPhone: a tap on « Autoriser ».
struct PhoneApprovalSheet: View {
    let approval: ApprovalRequest
    let approvals: PhoneApprovals

    var body: some View {
        VStack(spacing: 16) {
            PhoneMiniYumi(state: .approval).frame(width: 90, height: 90).padding(.top, 24)
            Text(approval.goal).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
            if !approval.reason.isEmpty, approval.reason != approval.goal { Text(approval.reason).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            Spacer()
            Button { approvals.answer(.approveOnce) } label: {
                Text(loc("Autoriser")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Button(role: .cancel) { approvals.answer(.deny) } label: {
                Text(loc("Refuser")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
        .padding(24)
        .presentationDetents([.medium])
    }
}

// MARK: - Settings

struct PhoneSettingsView: View {
    @Bindable var phone: Phone
    @State private var confirmClear = false
    @State private var language = AppLanguage.stored()
    @State private var cleared = false

    var body: some View {
        Group {
            Form {
                Section {
                    Picker(loc("Langue"), selection: Binding(get: { language }, set: { language = $0; AppLanguage.choose($0) })) {
                        Text(loc("Automatique")).tag(AppLanguage.automatic)
                        Text(verbatim: "Français").tag(AppLanguage.french)
                        Text(verbatim: "English").tag(AppLanguage.english)
                    }
                } footer: {
                    if language.code.map({ $0 != AppLanguage.current }) ?? (AppLanguage.resolve(Locale.preferredLanguages.first) != AppLanguage.current) {
                        Text(loc("La nouvelle langue s'applique au prochain lancement de Yumi."))
                    }
                }
                Section(loc("Intelligence")) {
                    LabeledContent(loc("Modèle d'Apple"),
                                   value: PhoneChat.whyNoModel(AppleModelAvailability.current) == nil ? loc("Prêt, sur cet iPhone.") : loc("Indisponible"))
                    if let why = PhoneChat.whyNoModel(AppleModelAvailability.current) {
                        Text(why).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if Phone.linkReady || phone.studio {
                        Toggle(loc("Retrouver mon Mac"), isOn: $phone.linkOn)
                        if phone.linkOn {
                            LabeledContent(loc("État"), value: phone.mac.map { PhoneSessionsCard.presence($0) }
                                           ?? loc("En attente du Mac"))
                        }
                        if let error = PhoneLink.shared.lastError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                    } else {
                        // The Mac's side is not switched on yet: said plainly rather than a switch that does nothing
                        HStack {
                            Text(loc("Retrouver mon Mac")).foregroundStyle(.secondary)
                            Spacer()
                            Text(loc("Bientôt"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(PhoneTheme.rim.opacity(0.35), in: Capsule())
                        }
                    }
                } header: {
                    Text(loc("Mac"))
                } footer: {
                    if Phone.linkReady || phone.studio {
                        Text(loc("Allume aussi le lien dans les réglages de Yumi sur ton Mac, avec le même compte iCloud. Par ton iCloud uniquement, jamais par un serveur de Yumi. Une réponse donnée ici est toujours vérifiée par le Mac avant d'agir."))
                    } else {
                        Text(loc("La connexion avec ton Mac arrive bientôt : tes sessions Claude Code et les demandes d'accord, sur ton iPhone, par ton iCloud."))
                    }
                }
                Section {
                    if phone.mail.isConnected {
                        LabeledContent(loc("Gmail"), value: phone.mail.address)
                        Button(loc("Déconnecter Gmail"), role: .destructive) { phone.mail.disconnect() }
                    } else {
                        Text(loc("Aucun compte. Connecte Gmail depuis la carte Mails de l'accueil.")).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(loc("Mails"))
                } footer: {
                    Text(loc("Yumi lit tes mails sans les marquer comme lus, et n'envoie une réponse que quand tu touches « Envoyer »."))
                }
                Section(loc("Yumi")) {
                    NavigationLink(loc("Son apparence")) { PhoneLookView(phone: phone) }
                    Toggle(loc("Dans la Dynamic Island"), isOn: $phone.islandOn)
                    Toggle(loc("Sons"), isOn: $phone.soundOn)
                    #if DEBUG
                    Toggle(loc("Mode tournage au prochain lancement"), isOn: $phone.studioNextLaunch)
                    #endif
                }
                Section(loc("Ce que je sais de toi")) {
                    if phone.memoryBook.entries.isEmpty {
                        Text(loc("Rien pour l'instant.")).foregroundStyle(.secondary)
                    }
                    ForEach(phone.memoryBook.entries) { entry in
                        Text(entry.text)
                            .swipeActions { Button(loc("Oublier"), role: .destructive) { phone.forget(entry) } }
                    }
                }
                Section {
                    if cleared {
                        Label(loc("Conversation effacée"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .transition(.opacity)
                    } else {
                        Button(loc("Effacer la conversation"), role: .destructive) { confirmClear = true }
                            .disabled(phone.chat.messages.isEmpty)
                    }
                } footer: {
                    if !cleared, !phone.chat.messages.isEmpty {
                        Text(loc("\(phone.chat.messages.count) messages gardés sur cet iPhone."))
                    }
                }
                .confirmationDialog(loc("Effacer toute la conversation avec Yumi ?"), isPresented: $confirmClear,
                                    titleVisibility: .visible) {
                    Button(loc("Effacer"), role: .destructive) {
                        phone.chat.clear()
                        withAnimation { cleared = true }
                        Task {
                            try? await Task.sleep(for: .seconds(2.5))
                            withAnimation { cleared = false }
                        }
                    }
                }
            }
            .phoneScreen()
        }
    }
}

extension String {
    /// « vendredi 20 novembre » → « Vendredi 20 novembre »: only the first letter, as French writes it.
    var firstCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
