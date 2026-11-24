import SwiftUI

/// The cards of « Aujourd'hui », in the order the person chose.
enum PhoneTodayCard: String, CaseIterable, Identifiable {
    case agenda, meteo, rappels, agents, demande, mail, github

    var id: String { rawValue }
    static let standard: [PhoneTodayCard] = [.agenda, .meteo, .rappels, .agents, .demande]
    private static let key = "phoneTodayOrder"

    var name: String {
        switch self {
        case .agenda: loc("Agenda")
        case .meteo: loc("Météo")
        case .rappels: loc("Rappels")
        case .agents: loc("Agents")
        case .demande: loc("Demandes")
        case .mail: loc("Mail")
        case .github: loc("GitHub")
        }
    }

    /// The screen a touch on the card opens.
    var page: PhonePage {
        switch self {
        case .agenda, .rappels: .agenda
        case .meteo: .weather
        case .agents, .demande: .agents
        case .mail, .github: .modules
        }
    }

    static func stored(_ defaults: UserDefaults = .standard) -> [PhoneTodayCard] {
        guard let raw = defaults.array(forKey: key) as? [String] else { return standard }
        return raw.compactMap(PhoneTodayCard.init(rawValue:))
    }

    static func store(_ order: [PhoneTodayCard], _ defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: key)
    }
}

struct PhoneHomeView: View {
    @Bindable var phone: Phone
    @State private var order = PhoneTodayCard.stored()
    @State private var dragging: PhoneTodayCard?

    var body: some View {
        let editing = phone.editingToday
        ScrollView {
            VStack(alignment: .leading, spacing: u(0)) {
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale)).firstCapitalized)
                    .font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                    .padding(.bottom, u(12))
                if editing {
                    Text(loc("Glisse les cartes pour choisir l'ordre. ✕ pour en retirer une."))
                        .font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray)
                        .padding(.bottom, u(8))
                }
                VStack(spacing: u(10)) {
                    ForEach(order) { card in
                        tile(card, editing: editing)
                            .phoneReveal(phone.revealed, step: order.firstIndex(of: card) ?? 0)
                    }
                }
                let hidden = PhoneTodayCard.allCases.filter { !order.contains($0) }
                if editing, !hidden.isEmpty {
                    Text(loc("Ajouter")).phoneEyebrow(PhoneTheme.gray)
                        .padding(.top, u(16)).padding(.bottom, u(6))
                    PhoneFlow(spacing: u(6)) {
                        ForEach(hidden) { card in
                            Button {
                                withAnimation(.spring(duration: 0.3)) { order.append(card) }
                                PhoneTodayCard.store(order)
                            } label: {
                                Text("+ " + card.name).font(.system(size: u(12.5)))
                                    .padding(.horizontal, u(12)).frame(height: u(30))
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, u(18))
            .padding(.bottom, u(120))
        }
        .scrollIndicators(.hidden)
        .refreshable { await phone.today.refresh(); await phone.mail.refresh(); phone.updateRemarks() }
        .onAppear { phone.updateRemarks() }
    }

    @ViewBuilder private func tile(_ card: PhoneTodayCard, editing: Bool) -> some View {
        let content = PhoneTodayTile(phone: phone, card: card)
        if editing {
            content
                .overlay(alignment: .trailing) {
                    Image(systemName: "ellipsis").font(.system(size: u(16))).foregroundStyle(PhoneTheme.gray)
                        .padding(.trailing, u(10))
                }
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: u(22), style: .continuous)
                    .strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .overlay(alignment: .topLeading) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { order.removeAll { $0 == card } }
                        PhoneTodayCard.store(order)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: u(10), weight: .heavy)).foregroundStyle(.white)
                            .frame(width: u(22), height: u(22))
                            .background(Color(white: 0.23), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: u(-6), y: u(-6))
                    .accessibilityLabel(Text(loc("Retirer \(card.name)")))
                }
                .opacity(dragging == card ? 0.4 : 1)
                .draggable(card.rawValue) {
                    PhoneTodayTile(phone: phone, card: card).frame(width: 340).onAppear { dragging = card }
                }
                .dropDestination(for: String.self) { _, _ in
                    dragging = nil
                    PhoneTodayCard.store(order)
                    return true
                } isTargeted: { over in
                    guard over, let moving = dragging, moving != card,
                          let from = order.firstIndex(of: moving), let to = order.firstIndex(of: card) else { return }
                    withAnimation(.spring(duration: 0.3)) {
                        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    }
                }
        } else {
            Button { phone.go(card.page) } label: { content }
                .buttonStyle(.plain)
        }
    }
}

/// One long card of « Aujourd'hui ».
struct PhoneTodayTile: View {
    let phone: Phone
    let card: PhoneTodayCard

    var body: some View {
        switch card {
        case .agenda: agenda
        case .meteo: PhoneWeatherTile(phone: phone)
        case .rappels: reminders
        case .agents: agents
        case .demande: request
        case .mail: mail
        case .github: github
        }
    }

    private var agenda: some View {
        let now = Date()
        let coming = phone.today.events.filter { $0.end > now }
        let first = coming.first
        return HStack(alignment: .top, spacing: u(14)) {
            VStack(alignment: .leading, spacing: u(0)) {
                Text(loc("Agenda")).phoneEyebrow(PhoneTheme.coral)
                if let first {
                    Text(first.isAllDay ? loc("Journée") : first.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: u(26), weight: .bold)).monospacedDigit()
                        .padding(.top, u(6))
                    if first.start > now {
                        Text(Self.until(first.start, now: now)).font(.system(size: u(11))).foregroundStyle(PhoneTheme.coral)
                    }
                } else {
                    Text(loc("Libre")).font(.system(size: u(22), weight: .bold)).padding(.top, u(6))
                }
            }
            VStack(alignment: .leading, spacing: u(2)) {
                if phone.today.calendarAccess != .granted {
                    Text(loc("Je n'ai pas accès à ton agenda.")).foregroundStyle(PhoneTheme.gray)
                } else if coming.isEmpty {
                    Text(loc("Rien de prévu aujourd'hui.")).foregroundStyle(PhoneTheme.gray)
                }
                ForEach(Array(coming.prefix(3).enumerated()), id: \.element.id) { index, event in
                    if index == 0 {
                        Text(event.title).fontWeight(.bold) + Text(event.location.isEmpty ? "" : " · " + event.location)
                    } else {
                        Text("\(event.isAllDay ? loc("Journée") : event.start.formatted(date: .omitted, time: .shortened)) \(event.title)")
                            .foregroundStyle(PhoneTheme.gray)
                    }
                }
            }
            .font(.system(size: u(12.5)))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, u(12))
            .overlay(alignment: .leading) { Rectangle().fill(Color(white: 0.11)).frame(width: 1) }
        }
        .phoneTile()
    }

    static func until(_ date: Date, now: Date) -> String {
        let minutes = Int(date.timeIntervalSince(now) / 60)
        if minutes < 60 { return loc("dans \(max(minutes, 1)) min") }
        return loc("dans \(minutes / 60) h \(String(format: "%02d", minutes % 60))")
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: u(0)) {
            HStack {
                Text(loc("Rappels · \(phone.today.reminders.count)")).phoneEyebrow(PhoneTheme.mint)
                Spacer()
                Text(loc("+ Ajouter")).font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
            }
            if phone.today.reminders.isEmpty {
                Text(loc("Aucun rappel en cours.")).font(.system(size: u(14))).foregroundStyle(PhoneTheme.gray).padding(.top, u(9))
            }
            ForEach(phone.today.reminders.prefix(3), id: \.id) { reminder in
                HStack(spacing: u(10)) {
                    Button {
                        withAnimation(.spring(duration: 0.35)) { phone.today.complete(reminder) }
                        phone.updateRemarks()
                    } label: {
                        Circle().strokeBorder(PhoneTheme.gray, lineWidth: 1.6).frame(width: u(18), height: u(18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(loc("Terminer « \(reminder.title) »")))
                    VStack(alignment: .leading, spacing: u(1)) {
                        Text(reminder.title).font(.system(size: u(14)))
                        if let due = PhoneToday.dueLabel(reminder) {
                            Text(due.text).font(.system(size: u(11))).foregroundStyle(due.late ? PhoneTheme.amber : PhoneTheme.gray)
                        }
                    }
                }
                .padding(.top, u(9))
            }
        }
        .phoneTile()
    }

    private var sessions: [LinkSession] { phone.linkOn ? phone.mac?.sessions ?? [] : [] }
    private var requests: [LinkApproval] { phone.linkOn ? phone.mac.map(PhoneMacRequests.live) ?? [] : [] }

    private var agents: some View {
        VStack(alignment: .leading, spacing: u(0)) {
            HStack {
                Text(loc("Agents · \(sessions.count)")).phoneEyebrow(PhoneTheme.blue)
                Spacer()
                if !requests.isEmpty {
                    Text(loc("\(requests.count) attend ta réponse")).font(.system(size: u(11))).foregroundStyle(PhoneTheme.amber)
                }
            }
            if sessions.isEmpty {
                Text(phone.linkOn ? loc("Aucun agent en cours.") : loc("Relie ton Mac pour voir tes agents."))
                    .font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.gray).padding(.top, u(7))
            }
            ForEach(sessions.prefix(3)) { session in
                HStack(spacing: u(8)) {
                    PhoneMiniYumi(state: PhoneAgentLook.state(session, waiting: waits(session)))
                        .frame(width: u(22), height: u(22))
                    (Text(session.agent).font(.system(size: u(12.5), weight: .semibold))
                     + Text(" " + session.project + " · " + session.status).font(.system(size: u(11.5))).foregroundStyle(PhoneTheme.gray))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(session.updatedAt, style: .relative).font(.system(size: u(11))).monospacedDigit()
                        .foregroundStyle(waits(session) ? PhoneTheme.amber : PhoneTheme.gray)
                        .lineLimit(1).fixedSize()
                }
                .padding(.top, u(7))
            }
        }
        .phoneTile()
    }

    private func waits(_ session: LinkSession) -> Bool { requests.contains { $0.sessionID == session.id } }

    private var request: some View {
        VStack(alignment: .leading, spacing: u(0)) {
            if let first = requests.first, let mac = phone.mac {
                let session = mac.sessions.first { $0.id == first.sessionID }
                HStack {
                    Text(loc("Demande · \(session?.agent ?? mac.deviceName)")).phoneEyebrow(PhoneTheme.amber)
                    Spacer()
                    Text(loc("1 sur \(requests.count)"))
                        .font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
                }
                if let session {
                    Text(session.project).font(.system(size: u(12))).foregroundStyle(PhoneTheme.soft).padding(.top, u(4))
                }
                Text(first.summary).font(.system(size: u(14), design: .monospaced)).foregroundStyle(PhoneTheme.code)
                    .padding(.top, u(8)).padding(.bottom, u(2))
                Text(loc("Touche pour décider.")).font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray)
            } else {
                Text(loc("Demandes")).phoneEyebrow(PhoneTheme.amber)
                Text(loc("Rien n'attend ta réponse.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray).padding(.top, u(6))
            }
        }
        .phoneTile(requests.isEmpty ? nil : PhoneTheme.amber)
    }

    private var mail: some View {
        let unread = phone.mail.mails.filter(\.unread)
        return VStack(alignment: .leading, spacing: u(0)) {
            Text(phone.mail.isConnected ? loc("Mail · \(unread.count) non lus") : loc("Mail")).phoneEyebrow(PhoneTheme.mail)
            if !phone.mail.isConnected {
                Text(loc("Connecte Gmail dans Réglages.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray).padding(.top, u(7))
            }
            ForEach(phone.mail.shown.prefix(2)) { item in
                (Text(item.from).bold() + Text(" " + item.subject).foregroundStyle(PhoneTheme.gray))
                    .font(.system(size: u(13))).lineLimit(1).padding(.top, u(7))
            }
        }
        .phoneTile()
    }

    private var github: some View {
        VStack(alignment: .leading, spacing: u(0)) {
            Text(loc("GitHub")).phoneEyebrow(YumiRGB(hex: 0xC9D1D9).color)
            Text((phone.linkOn ? phone.mac?.github ?? [] : []).prefix(2).joined(separator: " · ").nonEmpty
                 ?? loc("Rien de neuf sur GitHub."))
                .font(.system(size: u(13))).padding(.top, u(6))
        }
        .phoneTile()
    }
}

/// How Yumi looks for an agent: at work with his coffee, surprised when it waits, asleep when done.
enum PhoneAgentLook {
    static func state(_ session: LinkSession, waiting: Bool) -> BotState {
        if waiting || session.status.contains("attend") { return .approval }
        if session.status.contains("termin") || session.status.contains("dort") { return .sleeping }
        return .working
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Chips that go to the next line when the row is full.
struct PhoneFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
