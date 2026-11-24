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
    var mood: YumiMood? = nil
    @State private var engine = BotEngine()

    var body: some View {
        YumiStage(engine: engine, followsPointer: false)
            .onAppear {
                engine.setLook(accent: .current(), costume: .current())
                engine.setState(state, force: true)
                if let mood { engine.setMood(mood) }
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

extension String {
    /// « vendredi 20 novembre » → « Vendredi 20 novembre »: only the first letter, as French writes it.
    var firstCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
