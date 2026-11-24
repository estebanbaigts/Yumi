import SwiftUI

/// The screens of the app. The menu of the title opens five of them; the others are reached from
/// a card or a row.
enum PhonePage: String, Hashable {
    case today, modules, yumi, settings, mac
    case talk, agents, agenda, weather, mail, notes, github

    static let menu: [PhonePage] = [.today, .modules, .yumi, .settings, .mac]

    var title: String {
        switch self {
        case .today: loc("Aujourd'hui")
        case .modules: loc("Modules")
        case .yumi: AppIdentity.characterName
        case .settings: loc("Réglages")
        case .mac: loc("Mon Mac")
        case .talk: loc("Parler")
        case .agents: loc("Agents")
        case .agenda: loc("Agenda")
        case .weather: loc("Météo")
        case .mail: loc("Mail")
        case .notes: loc("Notes")
        case .github: loc("GitHub")
        }
    }
}

/// No tab bar: a black screen, its title that opens the menu, and Yumi at the bottom, whom one
/// touches to talk to him.
struct PhoneRootView: View {
    @Bindable var phone: Phone
    @State private var menuOpen = false
    /// The connection already celebrated (once per connection).
    @State private var celebrated: Date?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                PhoneTheme.ground.ignoresSafeArea()
                if phone.page == .weather { PhoneWeatherBackdrop(phone: phone).id(phone.weatherChanged) }
                VStack(spacing: u(0)) {
                    header
                    page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .id(phone.page)
                        .transition(.asymmetric(insertion: .move(edge: phone.arrival).combined(with: .opacity),
                                                removal: .opacity))
                }
                if phone.page != .talk { PhoneOrb(phone: phone).opacity(phone.orbShown ? 1 : 0) }
                if menuOpen { menu }
                if let at = PhoneLink.shared.connectedAt, celebrated != at, let mac = phone.mac {
                    PhoneLinkCelebration(macName: mac.deviceName) { celebrated = at }
                        .zIndex(3)
                        .transition(.opacity)
                }
            }
            // Swipe right: the screen before; swipe left: back where one was
            .simultaneousGesture(DragGesture(minimumDistance: 24).onEnded { drag in
                guard !menuOpen, !phone.editingToday,
                      abs(drag.translation.width) > 80, abs(drag.translation.height) < abs(drag.translation.width) * 0.6 else { return }
                if drag.translation.width > 0 { phone.back() } else { phone.forward() }
            })
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: PhonePage.self) { _ in EmptyView() }
        }
        .tint(PhoneTheme.violet)
        .sheet(isPresented: Binding(get: { phone.asksName && !phone.nameAsked }, set: { if !$0 { phone.answerName(nil) } })) {
            PhoneNameSheet(phone: phone)
        }
        .sheet(item: Binding(get: { phone.approvals.current }, set: { _ in })) { approval in
            PhoneApprovalSheet(approval: approval, approvals: phone.approvals)
                .interactiveDismissDisabled()
        }
    }

    private var header: some View {
        HStack(spacing: u(4)) {
            if !phone.behind.isEmpty {
                Button { phone.back() } label: {
                    Image(systemName: "chevron.left").font(.system(size: u(20), weight: .semibold))
                        .foregroundStyle(PhoneTheme.gray)
                        .frame(width: u(26), height: u(34), alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(loc("Retour")))
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { menuOpen = true }
            } label: {
                HStack(spacing: u(6)) {
                    Text(phone.page.title).font(.system(size: u(26), weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: u(15), weight: .bold))
                        .foregroundStyle(PhoneTheme.gray)
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(loc("Ouvre le menu")))
            Spacer()
            if phone.page == .today {
                Button { withAnimation(.spring(duration: 0.3)) { phone.editingToday.toggle() } } label: {
                    Text(phone.editingToday ? loc("OK") : loc("Modifier"))
                        .font(.system(size: u(13), weight: .semibold))
                        .foregroundStyle(phone.editingToday ? .black : .white)
                        .padding(.horizontal, u(12)).frame(height: u(28))
                        .background(phone.editingToday ? Color(white: 0.96) : .white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, u(18))
        .padding(.top, u(2)).padding(.bottom, u(6))
    }

    @ViewBuilder private var page: some View {
        switch phone.page {
        case .today: PhoneHomeView(phone: phone)
        case .modules: PhoneModulesView(phone: phone)
        case .yumi: PhoneLookView(phone: phone)
        case .settings: PhoneSettingsView(phone: phone)
        case .mac: PhoneLinkView(phone: phone)
        case .talk: PhoneChatView(phone: phone)
        case .agents: PhoneAgentsView(phone: phone)
        case .agenda: PhoneAgendaView(phone: phone)
        case .weather: PhoneWeatherView(phone: phone)
        case .mail: PhoneMailPage(phone: phone)
        case .notes: PhoneNotesPage(phone: phone)
        case .github: PhoneGitHubPage(phone: phone)
        }
    }

    /// The menu comes up from the bottom: five large names, the screen one is on in white.
    private var menu: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { close() }
                .transition(.opacity)
            VStack(alignment: .leading, spacing: u(0)) {
                ForEach(PhonePage.menu, id: \.self) { item in
                    Button {
                        phone.go(item)
                        close()
                    } label: {
                        Text(item.title)
                            .font(.system(size: u(22), weight: .semibold))
                            .foregroundStyle(item == phone.page ? .white : PhoneTheme.dim)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, u(26)).padding(.top, u(20)).padding(.bottom, u(110))
            .background(PhoneTheme.ink, in: UnevenRoundedRectangle(topLeadingRadius: u(30), topTrailingRadius: u(30), style: .continuous))
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
        }
        .ignoresSafeArea(edges: .bottom)
        .zIndex(2)
    }

    private func close() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { menuOpen = false }
    }
}

/// Yumi at the bottom of every screen. A touch takes to the conversation and he listens.
struct PhoneOrb: View {
    let phone: Phone

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.6)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: u(120))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Button { phone.talk() } label: {
                PhoneFace(character: phone.character, size: u(46), ring: u(68), hidesYumi: !phone.character.onScreen)
                    .shadow(color: PhoneTheme.violet.opacity(0.33), radius: u(13))
            }
            .buttonStyle(.plain)
            .padding(.bottom, u(0))
            .accessibilityLabel(Text(loc("Touche Yumi pour parler")))
        }
    }
}

/// Yumi in his black circle: the orb at the bottom, the one of the conversation.
struct PhoneFace: View {
    let character: PhoneCharacter
    var size: CGFloat
    var ring: CGFloat
    var listening = false
    /// During the opening the falling Yumi is the opening's: the circle waits for him empty.
    var hidesYumi = false

    var body: some View {
        YumiStage(engine: character.engine, paused: !character.onScreen, followsPointer: false)
            .frame(width: size, height: size)
            .opacity(hidesYumi ? 0 : 1)
            .allowsHitTesting(false)
            .frame(width: ring, height: ring)
            .background(.black, in: Circle())
            .overlay(Circle().strokeBorder(listening ? PhoneTheme.listen : .white.opacity(0.13), lineWidth: listening ? 3 : 1))
            .shadow(color: listening ? PhoneTheme.listen : .clear, radius: u(15))
            .onAppear { character.appear() }
    }
}
