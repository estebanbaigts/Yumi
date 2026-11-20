import SwiftUI

struct PhoneRootView: View {
    @Bindable var phone: Phone

    var body: some View {
        TabView {
            Tab(loc("Aujourd'hui"), systemImage: "sun.max") { PhoneHomeView(phone: phone) }
            Tab(loc("Parler"), systemImage: "bubble.left.and.bubble.right") { PhoneChatView(phone: phone) }
            Tab(loc("Réglages"), systemImage: "gearshape") { PhoneSettingsView(phone: phone) }
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
}

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

// MARK: - Today

struct PhoneHomeView: View {
    let phone: Phone

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PhoneYumi(character: phone.character, size: 160, showsRemark: true)
                        .padding(.top, 16)
                    Text(greeting).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                        .phoneReveal(phone.revealed, step: 0)
                    agenda.phoneReveal(phone.revealed, step: 1)
                    reminders.phoneReveal(phone.revealed, step: 2)
                    weather.phoneReveal(phone.revealed, step: 3)
                    if phone.linkOn, let mac = phone.mac { PhoneMacCard(mac: mac).phoneReveal(phone.revealed, step: 4) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .phoneScreen()
            .refreshable { await phone.today.refresh(); phone.updateRemarks() }
            .onAppear { phone.updateRemarks() }
            .navigationTitle(loc("Aujourd'hui"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let hello = hour < 18 ? loc("Bonjour") : loc("Bonsoir")
        guard let name = phone.memoryBook.name ?? (phone.studio ? "Esteban" : nil) else { return hello + " !" }
        return hello + " " + name + " !"
    }

    @ViewBuilder private var agenda: some View {
        PhoneCard(title: loc("Agenda"), symbol: "calendar",
                  opens: phone.today.calendarAccess == .granted ? PhoneApps.calendar : nil) {
            switch phone.today.calendarAccess {
            case .granted:
                // Today's date first, then the days of the week that have something
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale)).firstCapitalized)
                    .font(.headline)
                if phone.today.week.isEmpty {
                    Text(loc("Rien de prévu cette semaine.")).foregroundStyle(.secondary)
                } else {
                    if !phone.today.week.contains(where: { Calendar.current.isDateInToday($0.day) }) {
                        Text(loc("Rien de prévu aujourd'hui.")).foregroundStyle(.secondary)
                    }
                    ForEach(phone.today.week, id: \.day) { day in
                        VStack(alignment: .leading, spacing: 4) {
                            if !Calendar.current.isDateInToday(day.day) {
                                Text(PhoneToday.dayName(day.day).firstCapitalized)
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(PhoneTheme.rim)
                                    .padding(.top, 6)
                            }
                            ForEach(day.events, id: \.id) { event in
                                HStack {
                                    Text(event.isAllDay ? loc("Journée") : event.start.formatted(date: .omitted, time: .shortened))
                                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                                    Text(event.title)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
            case .notDetermined:
                Button(loc("Voir mon agenda")) { Task { await phone.today.askCalendar() } }
            case .denied:
                Text(loc("L'accès au calendrier est refusé. Tu peux le rendre dans Réglages.")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var reminders: some View {
        PhoneCard(title: loc("Rappels et notes"), symbol: "checklist",
                  opens: phone.today.remindersAccess == .granted ? PhoneApps.reminders : nil) {
            switch phone.today.remindersAccess {
            case .granted:
                if phone.today.reminders.isEmpty { Text(loc("Aucun rappel en cours.")).foregroundStyle(.secondary) }
                ForEach(phone.today.reminders.prefix(5), id: \.id) { reminder in
                    HStack(alignment: .firstTextBaseline) {
                        Label(reminder.title, systemImage: "circle")
                        Spacer(minLength: 8)
                        if let due = PhoneToday.dueLabel(reminder) {
                            Text(due.text)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(due.late ? Color.red : Color.secondary)
                        }
                    }
                }
            case .notDetermined:
                Button(loc("Voir mes rappels")) { Task { await phone.today.askReminders() } }
            case .denied:
                Text(loc("L'accès aux rappels est refusé. Tu peux le rendre dans Réglages.")).foregroundStyle(.secondary)
            }
            ForEach(phone.today.notes.prefix(3), id: \.self) { note in
                Label(note, systemImage: "note.text").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var weather: some View {
        PhoneCard(title: loc("Météo"), symbol: WeatherSummary.symbol(for: phone.today.weather),
                  opens: { if case .ready = phone.today.weather { return PhoneApps.weather }; return nil }()) {
            switch phone.today.weather {
            case .ready(let report):
                Text("\(Int(report.temperature.rounded())) °C · \(WeatherSummary.sky(report.code))").font(.headline)
                Text(WeatherSummary.advice(report, now: Date())).foregroundStyle(.secondary)
            case .loading:
                ProgressView()
            case .unavailable:
                Text(loc("Je n'arrive pas à avoir la météo.")).foregroundStyle(.secondary)
            case .needsLocation(.denied):
                Text(loc("La localisation est refusée. Tu peux la rendre dans Réglages.")).foregroundStyle(.secondary)
            case .needsLocation:
                Button(loc("Voir le ciel d'ici")) { Task { await phone.today.loadWeather() } }
            }
        }
    }
}

/// What the Mac follows, when the link is on and a Mac answered.
struct PhoneMacCard: View {
    let mac: LinkSnapshot

    var body: some View {
        PhoneCard(title: mac.deviceName, symbol: "laptopcomputer") {
            ForEach(mac.approvals.filter { $0.expiresAt > Date() }) { approval in
                VStack(alignment: .leading, spacing: 8) {
                    Label(approval.summary, systemImage: "hand.raised.fill").font(.headline)
                    HStack {
                        Button(loc("Refuser"), role: .destructive) { Task { await PhoneLink.shared.answer(approval, allow: false) } }
                            .buttonStyle(.bordered)
                        Button(loc("Autoriser")) { Task { await PhoneLink.shared.answer(approval, allow: true) } }
                            .buttonStyle(.borderedProminent)
                    }
                    Text(loc("Le Mac vérifie ta réponse avant d'agir.")).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            ForEach(mac.sessions) { session in
                HStack {
                    Text("\(session.agent) · \(session.project)")
                    Spacer()
                    Text(session.status).foregroundStyle(.secondary)
                }
            }
            ForEach(mac.github, id: \.self) { line in
                Label(line, systemImage: "arrow.triangle.branch").foregroundStyle(.secondary)
            }
        }
    }
}

struct PhoneCard<Content: View>: View {
    let title: String
    let symbol: String
    /// The app a tap on the card opens (Calendar, Reminders, Weather), when there is one.
    var opens: URL? = nil
    @ViewBuilder var content: Content
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.subheadline.weight(.semibold))
                    .foregroundStyle(PhoneTheme.rim)
                Spacer()
                if opens != nil {
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
        NavigationStack {
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
            .navigationTitle(AppIdentity.characterName)
            .navigationBarTitleDisplayMode(.inline)
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
        NavigationStack {
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
                if YumiLinks.isBuiltIn || phone.studio {
                Section {
                    Toggle(loc("Retrouver mon Mac"), isOn: $phone.linkOn)
                    if let error = PhoneLink.shared.lastError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text(loc("Mac"))
                } footer: {
                    Text(loc("Par ton iCloud uniquement, jamais par un serveur de Yumi. Une réponse donnée ici est toujours vérifiée par le Mac avant d'agir."))
                }
                }
                Section(loc("Yumi")) {
                    NavigationLink(loc("Son apparence")) { PhoneLookView(phone: phone) }
                    Toggle(loc("Sons"), isOn: $phone.soundOn)
                    Toggle(loc("Mode tournage au prochain lancement"), isOn: $phone.studioNextLaunch)
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
            .navigationTitle(loc("Réglages"))
        }
    }
}

extension String {
    /// « vendredi 20 novembre » → « Vendredi 20 novembre »: only the first letter, as French writes it.
    var firstCapitalized: String { prefix(1).uppercased() + dropFirst() }
}
