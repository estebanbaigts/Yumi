import SwiftUI

// The screens reached from the menu or a card: Agents, Modules, Agenda, Météo, Mon Mac.

// MARK: - Agents

/// What the agents of the Mac do, then what they wait for. « Autoriser » asks for Face ID first,
/// and the Mac checks the answer again before acting.
struct PhoneAgentsView: View {
    let phone: Phone

    var body: some View {
        let mac = phone.linkOn ? phone.mac : nil
        let sessions = mac?.sessions ?? []
        let requests = mac.map(PhoneMacRequests.live) ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if mac == nil {
                    PhoneEmpty(state: .sleeping, text: loc("Relie ton Mac pour voir tes agents."),
                               action: loc("Relier mon Mac")) { phone.go(.mac) }
                } else {
                    let active = sessions.filter { PhoneAgentLook.state($0, waiting: false) != .sleeping }.count
                    Text(loc("Activité · \(active) actifs")).phoneEyebrow(PhoneTheme.blue).padding(.bottom, u(8))
                    if sessions.isEmpty {
                        Text(loc("Aucun agent en cours.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                    }
                    ForEach(sessions) { session in
                        row(session, waiting: requests.contains { $0.sessionID == session.id })
                            .padding(.bottom, u(8))
                    }
                    if !requests.isEmpty, let mac {
                        Text(loc("Demandes · \(requests.count)")).phoneEyebrow(PhoneTheme.amber)
                            .padding(.top, u(16)).padding(.bottom, u(8))
                        ForEach(requests) { approval in
                            PhoneRequestCard(mac: mac, approval: approval).padding(.bottom, u(12))
                        }
                    }
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .refreshable { await PhoneLink.shared.refresh() }
    }

    private func row(_ session: LinkSession, waiting: Bool) -> some View {
        let state = PhoneAgentLook.state(session, waiting: waiting)
        let color = state == .working ? PhoneTheme.blue : state == .approval ? PhoneTheme.amber : PhoneTheme.gray
        return HStack(spacing: u(10)) {
            PhoneMiniYumi(state: state).frame(width: u(34), height: u(34))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.agent).font(.system(size: u(14), weight: .bold))
                Text(session.project).font(.system(size: u(12))).foregroundStyle(PhoneTheme.soft)
                Text(state == .sleeping ? loc("dort") : session.status).font(.system(size: u(12))).foregroundStyle(color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(session.updatedAt, style: .relative).font(.system(size: u(12))).monospacedDigit()
                .foregroundStyle(PhoneTheme.gray).fixedSize()
        }
        .phoneTile(waiting ? PhoneTheme.amber : nil)
        .opacity(state == .sleeping ? 0.55 : 1)
    }
}

/// A request of the Mac: what it wants to run, then Refuser, Yumi, Autoriser.
struct PhoneRequestCard: View {
    let mac: LinkSnapshot
    let approval: LinkApproval

    var body: some View {
        let session = mac.sessions.first { $0.id == approval.sessionID }
        let answered = PhoneLink.shared.answered[approval.id]
        VStack(spacing: 0) {
            Text(session?.agent ?? mac.deviceName).phoneEyebrow(PhoneTheme.amber)
            Text("\(session?.project ?? mac.deviceName) · \(loc("expire")) \(approval.expiresAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray).padding(.top, 2)
            Text(approval.summary).font(.system(size: u(16), design: .monospaced)).foregroundStyle(PhoneTheme.code)
                .multilineTextAlignment(.center)
                .padding(.top, u(12)).padding(.bottom, u(6))
            if let answered {
                Label(answered ? loc("Autorisé, le Mac vérifie") : loc("Refusé"),
                      systemImage: answered ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: u(14), weight: .semibold))
                    .foregroundStyle(answered ? PhoneTheme.allow : PhoneTheme.refuse)
                    .padding(.vertical, u(18))
            } else {
                HStack(spacing: u(26)) {
                    pin("xmark", loc("Refuser"), PhoneTheme.refuse) { Task { await PhoneLink.shared.answer(approval, allow: false) } }
                    PhoneMiniYumi(state: .approval).frame(width: u(58), height: u(58))
                    pin("checkmark", loc("Autoriser"), PhoneTheme.allow) { Task { await PhoneLink.shared.answer(approval, allow: true) } }
                }
                .padding(.top, u(18)).padding(.bottom, u(4))
            }
        }
        .frame(maxWidth: .infinity)
        .phoneTile(PhoneTheme.amber, padding: u(17))
        .animation(.spring(duration: 0.35), value: answered)
    }

    private func pin(_ symbol: String, _ label: String, _ color: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: u(7)) {
                Image(systemName: symbol).font(.system(size: u(22), weight: .heavy)).foregroundStyle(.white)
                    .frame(width: u(60), height: u(60))
                    .background(color, in: Circle())
                    .shadow(color: color.opacity(0.47), radius: u(12))
                Text(label).font(.system(size: u(12), weight: .semibold)).foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
    }
}

/// An empty screen: Yumi, one sentence, one button.
struct PhoneEmpty: View {
    var state: BotState = .idle
    var mood: YumiMood? = nil
    let text: String
    var action: String?
    var run: () -> Void = {}

    var body: some View {
        VStack(spacing: u(14)) {
            PhoneMiniYumi(state: state, mood: mood).frame(width: u(80), height: u(80))
            Text(text).font(.system(size: u(14))).foregroundStyle(PhoneTheme.gray).multilineTextAlignment(.center)
            if let action {
                Button(action: run) {
                    Text(action).font(.system(size: u(14), weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: u(46))
                        .overlay(Capsule().strokeBorder(Color(white: 0.96), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, u(40))
    }
}

// MARK: - Modules

/// What Yumi follows on the iPhone, one row each; a row opens its page.
struct PhoneModulesView: View {
    let phone: Phone

    private struct Row: Identifiable {
        let id: String, name: String, symbol: String, color: Color, detail: String, value: String
        let page: PhonePage?
    }

    private var rows: [Row] {
        var rows: [Row] = []
        let mac = phone.linkOn ? phone.mac : nil
        let requests = mac.map(PhoneMacRequests.live) ?? []
        let sessions = mac?.sessions ?? []
        let working = sessions.filter { PhoneAgentLook.state($0, waiting: false) == .working }.count
        rows.append(Row(id: "agents", name: loc("Agents"), symbol: "terminal", color: YumiRGB(hex: 0x8B9CFF).color,
                        detail: mac == nil ? loc("Relie ton Mac") : requests.isEmpty ? loc("\(working) travaillent")
                            : loc("\(working) travaillent · \(requests.count) attend ta réponse"),
                        value: "\(sessions.count)", page: .agents))
        let next = phone.today.events.first { $0.end > Date() }
        rows.append(Row(id: "agenda", name: loc("Agenda"), symbol: "calendar", color: PhoneTheme.coral,
                        detail: next.map { $0.start > Date() ? "\($0.title) · \(PhoneTodayTile.until($0.start, now: Date()))" : $0.title } ?? loc("Rien de prévu aujourd'hui."),
                        value: next.map { $0.isAllDay ? "" : $0.start.formatted(date: .omitted, time: .shortened) } ?? "",
                        page: .agenda))
        let unread = phone.mail.mails.filter { $0.unread && ($0.date.map(Calendar.current.isDateInToday) ?? false) }
        rows.append(Row(id: "mail", name: loc("Mail"), symbol: "envelope", color: PhoneTheme.mail,
                        detail: phone.mail.isConnected ? unread.first?.subject ?? loc("Aucun mail.") : loc("Connecte Gmail dans Réglages."),
                        value: phone.mail.isConnected ? "\(unread.count)" : "", page: .mail))
        rows.append(Row(id: "github", name: loc("GitHub"), symbol: "arrow.triangle.branch", color: YumiRGB(hex: 0xC9D1D9).color,
                        detail: phone.github.lines.first ?? mac?.github.first ?? (phone.github.isConnected || mac != nil ? loc("Rien de neuf sur GitHub.") : loc("Connecte GitHub")),
                        value: phone.github.isConnected ? "\(phone.github.lines.count)" : mac.map { "\($0.github.count)" } ?? "", page: .github))
        rows.append(Row(id: "notes", name: loc("Notes"), symbol: "note.text", color: YumiRGB(hex: 0xFFD36B).color,
                        detail: phone.today.notes.first ?? loc("Aucune note."), value: "\(phone.today.notes.count)", page: .notes))
        var weather = loc("Je ne sais pas encore où tu es.")
        var degrees = ""
        if case .ready(let report) = phone.today.weather {
            degrees = PhoneWeather.degrees(report)
            weather = [phone.today.placeName, WeatherSummary.sky(report.code)].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        rows.append(Row(id: "weather", name: loc("Météo"), symbol: "sun.max", color: PhoneTheme.listen,
                        detail: weather, value: degrees, page: .weather))
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(spacing: u(8)) {
                ForEach(rows) { row in
                    Button { if let page = row.page { phone.go(page) } } label: {
                        HStack(spacing: u(12)) {
                            Image(systemName: row.symbol).font(.system(size: u(16), weight: .semibold)).foregroundStyle(row.color)
                                .frame(width: u(36), height: u(36))
                                .background(row.color.opacity(0.13), in: RoundedRectangle(cornerRadius: u(11), style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.system(size: u(14), weight: .semibold))
                                Text(row.detail).font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.value).font(.system(size: u(18), weight: .bold)).monospacedDigit()
                            Image(systemName: "chevron.right").font(.system(size: u(12), weight: .semibold))
                                .foregroundStyle(PhoneTheme.gray)
                        }
                        .phoneTile()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
    }
}

/// Today's mails, newest first; a touch opens one (Yumi's summary, the text, an answer).
struct PhoneMailPage: View {
    let phone: Phone
    @State private var open: GmailMail?
    @State private var connecting = false

    private var today: [GmailMail] {
        phone.mail.mails.filter { $0.date.map(Calendar.current.isDateInToday) ?? false }
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: u(8)) {
                if !phone.mail.isConnected {
                    PhoneEmpty(state: .idle, text: loc("Je peux lire tes derniers mails, te les résumer et t'aider à répondre."),
                               action: loc("Connecter Gmail")) { connecting = true }
                } else {
                    let unread = today.filter(\.unread).count
                    Text(loc("Aujourd'hui · \(today.count) mails · \(unread) non lus")).phoneEyebrow(PhoneTheme.mail)
                        .padding(.bottom, u(4))
                    if case .failed(let why) = phone.mail.state {
                        Text(why).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                    } else if phone.mail.state == .loading, phone.mail.mails.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, u(30))
                    } else if today.isEmpty {
                        PhoneEmpty(state: .idle, mood: .happy, text: loc("Aucun mail aujourd'hui."))
                    }
                    ForEach(today) { mail in
                        Button { open = mail } label: { row(mail) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .refreshable { await phone.mail.refresh() }
        .sheet(item: $open) { mail in PhoneMailSheet(phone: phone, mail: mail) }
        .sheet(isPresented: $connecting) { PhoneMailConnect(mail: phone.mail) }
    }

    private func row(_ mail: GmailMail) -> some View {
        HStack(alignment: .top, spacing: u(10)) {
            Circle().fill(mail.unread ? PhoneTheme.mail : .clear).frame(width: u(8), height: u(8)).padding(.top, u(6))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(mail.from).font(.system(size: u(14), weight: mail.unread ? .bold : .regular)).lineLimit(1)
                    Spacer()
                    if let date = mail.date {
                        Text(date.formatted(date: .omitted, time: .shortened)).font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
                    }
                }
                Text(mail.subject).font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.soft).lineLimit(2)
            }
        }
        .phoneTile()
        .opacity(mail.bulk ? 0.6 : 1)
    }
}

/// What Yumi keeps in notes (« note : … » in the conversation).
struct PhoneNotesPage: View {
    let phone: Phone

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: u(8)) {
                Text(loc("Notes · \(phone.today.notes.count)")).phoneEyebrow(YumiRGB(hex: 0xFFD36B).color).padding(.bottom, u(4))
                if phone.today.notes.isEmpty {
                    PhoneEmpty(state: .idle, text: loc("Aucune note. Dis à Yumi « note : … » pour en garder une."))
                }
                ForEach(phone.today.notes, id: \.self) { note in
                    Text(note).font(.system(size: u(14))).phoneTile()
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
    }
}

/// What happened on GitHub: from the iPhone's own token, or as the Mac tells it.
struct PhoneGitHubPage: View {
    let phone: Phone
    @State private var token = ""

    var body: some View {
        let github = phone.github
        let lines = github.isConnected ? github.lines : (phone.linkOn ? phone.mac?.github ?? [] : [])
        ScrollView {
            VStack(alignment: .leading, spacing: u(8)) {
                if github.isConnected || (phone.linkOn && phone.mac != nil) {
                    Text(github.login.map { "GitHub · \($0)" } ?? loc("GitHub · par ton Mac")).phoneEyebrow(YumiRGB(hex: 0xC9D1D9).color)
                        .padding(.bottom, u(4))
                    if let failed = github.failed { Text(failed).font(.system(size: u(13))).foregroundStyle(PhoneTheme.amber) }
                    if lines.isEmpty, !github.loading { PhoneEmpty(state: .idle, text: loc("Rien de neuf sur GitHub.")) }
                    if github.loading, lines.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(.top, u(30)) }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Label(line, systemImage: "arrow.triangle.branch").font(.system(size: u(14))).phoneTile()
                    }
                    if github.isConnected {
                        Button(loc("Déconnecter GitHub"), role: .destructive) { github.disconnect() }
                            .font(.system(size: u(13))).padding(.top, u(12))
                    }
                } else {
                    PhoneEmpty(state: .idle, text: loc("Colle un jeton GitHub pour suivre tes pushs, tes PR et tes étoiles, sans Mac."))
                    SecureField("ghp_… / github_pat_…", text: $token)
                        .font(.system(size: u(14)))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, u(14)).frame(height: u(44))
                        .background(PhoneTheme.ink, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                        .padding(.top, u(12))
                    PhoneHoldButton(label: loc("Maintenir pour connecter")) { Task { await github.connect(token: token) } }
                        .padding(.top, u(8))
                    Text(loc("Crée-le sur github.com › Settings › Developer settings › Personal access tokens (lecture seule suffit). Il reste dans le trousseau de cet iPhone."))
                        .font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
                    Text(loc("Ou relie ton Mac : il partage ce qu'il voit de GitHub.")).font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
                        .padding(.top, u(6))
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .refreshable { await github.refresh() }
    }
}

// MARK: - Agenda

/// The strip of the days, the line of the time, the reminders, and what Yumi can do.
struct PhoneAgendaView: View {
    let phone: Phone
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var adding: PhoneAddKind?

    private static let colors: [Color] = [0x8B9CFF, 0xFF8A7A, 0xF2B36B, 0x3DDC97, 0x7FD8FF].map { YumiRGB(hex: $0).color }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                strip.padding(.bottom, u(14))
                timeline
                reminders.padding(.top, u(4))
                ScrollView(.horizontal) {
                    HStack(spacing: u(6)) {
                        chip(loc("+ Rappel")) { adding = .reminder }
                        chip(loc("+ Événement")) { adding = .event }
                        chip(loc("Ma semaine")) { ask(loc("Qu'est-ce que j'ai cette semaine ?")) }
                        chip(loc("Demain")) { ask(loc("Qu'est-ce que j'ai demain ?")) }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.top, u(10))
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .sheet(item: $adding) { kind in PhoneAddSheet(kind: kind, today: phone.today) { phone.updateRemarks() } }
    }

    private var strip: some View {
        HStack(spacing: u(6)) {
            ForEach(PhoneToday.days(from: Date()).prefix(5), id: \.self) { date in
                let on = Calendar.current.isDate(date, inSameDayAs: day)
                Button { withAnimation(.spring(duration: 0.3)) { day = date } } label: {
                    VStack(spacing: 1) {
                        Text(date.formatted(.dateTime.weekday(.narrow).locale(AppLanguage.locale)))
                        Text(date.formatted(.dateTime.day()))
                    }
                    .font(.system(size: u(12), weight: .semibold))
                    .foregroundStyle(on ? .black : PhoneTheme.gray)
                    .frame(maxWidth: .infinity).padding(.vertical, u(8))
                    .background(on ? Color(white: 0.96) : PhoneTheme.ink, in: RoundedRectangle(cornerRadius: u(14), style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var timeline: some View {
        let now = Date()
        let events = phone.today.events(on: day)
        let today = Calendar.current.isDateInToday(day)
        let nowIndex = today ? events.firstIndex { $0.start > now } ?? events.count : -1
        return VStack(alignment: .leading, spacing: 0) {
            if phone.today.calendarAccess != .granted {
                Text(loc("Je n'ai pas accès à ton agenda.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                    .padding(.bottom, u(12))
            } else if events.isEmpty {
                Text(loc("Rien de prévu ce jour-là.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                    .padding(.bottom, u(12))
            }
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                if index == nowIndex { nowLine(now) }
                HStack(alignment: .top, spacing: 0) {
                    Text(event.isAllDay ? loc("Journée") : event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: u(12))).monospacedDigit().foregroundStyle(PhoneTheme.gray)
                        .frame(width: u(56), alignment: .leading)
                        .padding(.top, 2)
                    Text(event.title).font(.system(size: u(14), weight: .semibold))
                        .padding(.leading, u(12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Self.colors[index % Self.colors.count]).frame(width: 2)
                        }
                }
                .frame(height: u(50), alignment: .top)
                .opacity(today && event.end < now ? 0.4 : 1)
            }
            if nowIndex == events.count, !events.isEmpty { nowLine(now) }
        }
    }

    private func nowLine(_ now: Date) -> some View {
        Rectangle().fill(PhoneTheme.refuse).frame(height: 1.5)
            .padding(.leading, u(56))
            .overlay(alignment: .leading) {
                Text(now.formatted(date: .omitted, time: .shortened)).font(.system(size: u(11), weight: .bold))
                    .foregroundStyle(PhoneTheme.refuse)
            }
            .padding(.top, u(4)).padding(.bottom, u(12))
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: u(6)) {
            Text(loc("Rappels")).phoneEyebrow(PhoneTheme.mint)
            Text(phone.today.reminders.isEmpty ? loc("Aucun rappel en cours.")
                 : phone.today.reminders.prefix(4).map(\.title).joined(separator: " · "))
                .font(.system(size: u(13.5)))
            ForEach(phone.today.notes.prefix(2), id: \.self) { note in
                Label(note, systemImage: "note.text").font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray)
            }
        }
        .phoneTile()
    }

    private func chip(_ text: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: u(12.5))).foregroundStyle(YumiRGB(hex: 0xCFC6FF).color)
                .padding(.horizontal, u(12)).frame(height: u(30))
                .overlay(Capsule().strokeBorder(YumiRGB(hex: 0x9D8BFF).color, lineWidth: 1.4))
        }
        .buttonStyle(.plain)
    }

    private func ask(_ text: String) {
        phone.go(.talk)
        Task { await phone.chat.send(text) }
    }
}

// MARK: - Weather

/// The weather as the Mac's island shows it: the same seven moods and their animated ground.
enum PhoneWeather {
    /// Chosen by hand on the weather screen, until the app is closed.
    @MainActor static var chosen: WeatherAmbiance?

    @MainActor static func ambiance(_ state: WeatherState) -> WeatherAmbiance? {
        guard case .ready(let report) = state else { return nil }
        if let chosen { return chosen }
        return WeatherAmbiance.pick(symbol: WeatherSummary.symbol(for: state), status: degrees(report))
    }

    static func degrees(_ report: WeatherReport) -> String { "\(Int(report.temperature.rounded()))°" }
}

/// Yumi as the weather makes him: what he holds, his face, the beanie over no costume.
struct PhoneWeatherYumi: View {
    let ambiance: WeatherAmbiance?
    @State private var engine = BotEngine()

    var body: some View {
        YumiStage(engine: engine, followsPointer: false)
            .onAppear(perform: dress)
            .onChange(of: ambiance) { dress() }
            .accessibilityHidden(true)
    }

    private func dress() {
        let costume = YumiCostume.current()
        engine.setLook(accent: .current(), costume: ambiance?.wearsBeanie == true && costume == .none ? .beanie : costume)
        engine.setState(.idle, force: true)
        engine.setHabit(ambiance?.habit)
        engine.setMood(ambiance?.mood)
    }
}

/// The weather card of « Aujourd'hui »: its ambiance behind, Yumi in it.
struct PhoneWeatherTile: View {
    let phone: Phone

    var body: some View {
        let state = phone.today.weather
        let mood = PhoneWeather.ambiance(state)
        HStack(spacing: u(12)) {
            PhoneWeatherYumi(ambiance: mood).frame(width: u(40), height: u(40))
            VStack(alignment: .leading, spacing: 2) {
                Text(phone.today.placeName.isEmpty ? loc("Météo") : loc("Météo · \(phone.today.placeName)"))
                    .phoneEyebrow(mood?.color ?? PhoneTheme.listen)
                switch state {
                case .ready(let report):
                    HStack(alignment: .firstTextBaseline, spacing: u(8)) {
                        Text(PhoneWeather.degrees(report)).font(.system(size: u(24), weight: .bold)).monospacedDigit()
                        Text("\(mood?.name ?? "") · \(WeatherSummary.sky(report.code))")
                            .font(.system(size: u(12))).foregroundStyle(YumiRGB(hex: 0xD6D8E0).color).lineLimit(1)
                    }
                case .loading:
                    ProgressView().padding(.top, 4)
                case .unavailable:
                    Text(loc("Je n'arrive pas à avoir la météo.")).font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.gray)
                case .needsLocation:
                    Text(loc("Je ne sais pas encore où tu es.")).font(.system(size: u(12.5))).foregroundStyle(PhoneTheme.gray)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: u(52))
        .padding(u(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                PhoneTheme.ink
                if let mood { WeatherEffects(ambiance: mood).opacity(0.7).allowsHitTesting(false) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: u(20), style: .continuous))
    }
}

/// The ground of the weather screen, under its title: the whole screen is the weather.
struct PhoneWeatherBackdrop: View {
    let phone: Phone

    var body: some View {
        ZStack {
            Color.black
            if let mood = PhoneWeather.ambiance(phone.today.weather) { WeatherEffects(ambiance: mood) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct PhoneWeatherView: View {
    @Bindable var phone: Phone
    @State private var chosen = PhoneWeather.chosen

    var body: some View {
        ScrollView {
            switch phone.today.weather {
            case .ready(let report): ready(report)
            case .loading: ProgressView().padding(.top, u(80))
            case .unavailable:
                PhoneEmpty(text: loc("Je n'arrive pas à avoir la météo."), action: loc("Réessayer")) {
                    Task { await phone.today.loadWeather() }
                }
                .padding(.horizontal, u(14))
            case .needsLocation:
                PhoneEmpty(text: loc("Je ne sais pas encore où tu es."), action: loc("Voir le ciel d'ici")) {
                    Task { await phone.today.loadWeather() }
                }
                .padding(.horizontal, u(14))
            }
        }
        .scrollIndicators(.hidden)
    }

    private func ready(_ report: WeatherReport) -> some View {
        let auto = WeatherAmbiance.pick(symbol: WeatherSummary.symbol(for: phone.today.weather), status: PhoneWeather.degrees(report))
        let mood = chosen ?? auto
        return VStack(spacing: 0) {
            Text(phone.today.placeName).font(.system(size: u(14))).foregroundStyle(YumiRGB(hex: 0xD6D8E0).color)
            Text(PhoneWeather.degrees(report)).font(.system(size: u(84), weight: .ultraLight)).monospacedDigit()
            Text(mood.name).font(.system(size: u(17), weight: .semibold))
            Text(WeatherSummary.advice(report, now: Date())).font(.system(size: u(13))).foregroundStyle(PhoneTheme.soft)
                .multilineTextAlignment(.center).padding(.top, 2)
            PhoneWeatherYumi(ambiance: mood).frame(width: u(110), height: u(110))
                .padding(.top, u(18)).padding(.bottom, u(8))
            HStack(spacing: 0) {
                ForEach(Array(report.hours.prefix(6).enumerated()), id: \.offset) { index, hour in
                    VStack(spacing: 2) {
                        Text(index == 0 ? loc("Maint.") : hour.time.formatted(.dateTime.hour()))
                            .font(.system(size: u(12))).foregroundStyle(PhoneTheme.soft)
                        Text("\(hour.rainChance) %").font(.system(size: u(14), weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(u(12))
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: u(20), style: .continuous))
            .background(.ultraThinMaterial.opacity(0.4), in: RoundedRectangle(cornerRadius: u(20), style: .continuous))
            (Text(loc("Ambiance choisie toute seule : ")) + Text(auto.name).bold().foregroundColor(.white) + Text(loc(" (météo, heure et saison)")))
                .font(.system(size: u(11.5))).foregroundStyle(PhoneTheme.soft).multilineTextAlignment(.center)
                .padding(.top, u(12))
            PhoneFlow(spacing: u(5)) {
                ForEach(WeatherAmbiance.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            chosen = item == auto ? nil : item
                            PhoneWeather.chosen = chosen
                            phone.weatherChanged.toggle()
                        }
                    } label: {
                        Text(item.name).font(.system(size: u(11.5), weight: item == mood ? .semibold : .regular))
                            .foregroundStyle(item == mood ? .black : .white)
                            .padding(.horizontal, u(10)).frame(height: u(26))
                            .background(item == mood ? item.color : .white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, u(8))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, u(20))
        .padding(.horizontal, u(14))
        .padding(.bottom, u(110))
    }
}

// MARK: - Mon Mac

/// The link with the Mac, through the person's iCloud. Held down to turn it on.
struct PhoneLinkView: View {
    @Bindable var phone: Phone
    @State private var pulse = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: u(14)) {
                    Image(systemName: "iphone").font(.system(size: u(36), weight: .light))
                    Capsule().fill(LinearGradient(colors: [PhoneTheme.blue, PhoneTheme.pink], startPoint: .leading, endPoint: .trailing))
                        .frame(width: u(70), height: 2)
                        .shadow(color: YumiRGB(hex: 0xC77DFF).color, radius: 5)
                        .opacity(phone.linkOn ? (pulse ? 1 : 0.35) : 0.25)
                    Image(systemName: "laptopcomputer").font(.system(size: u(46), weight: .light))
                }
                .foregroundStyle(Color(white: 0.96))
                .padding(.top, u(34)).padding(.bottom, u(24))
                PhoneMiniYumi(state: .idle, mood: phone.linkOn && phone.mac != nil ? .happy : .curious)
                    .frame(width: u(80), height: u(80))
                if phone.linkOn, let mac = phone.mac {
                    Text(mac.deviceName).font(.system(size: u(21), weight: .semibold)).padding(.top, u(14)).padding(.bottom, u(6))
                    Text(loc("Relié par ton iCloud. Une réponse donnée ici est toujours vérifiée par le Mac avant d'agir."))
                        .font(.system(size: u(14))).foregroundStyle(PhoneTheme.gray).multilineTextAlignment(.center)
                        .padding(.horizontal, u(10)).padding(.bottom, u(22))
                    PhoneHoldButton(label: loc("Maintenir pour délier"), color: PhoneTheme.refuse) { phone.linkOn = false }
                    Label(PhoneSessionsCard.presence(mac), systemImage: "circle.fill")
                        .font(.system(size: u(12))).foregroundStyle(PhoneTheme.allow).labelStyle(PhoneDotLabel())
                        .padding(.top, u(14))
                } else {
                    Text(phone.linkOn ? loc("En attente du Mac") : loc("Relie ton Mac"))
                        .font(.system(size: u(21), weight: .semibold)).padding(.top, u(14)).padding(.bottom, u(6))
                    Text(loc("Sur le Mac : clic droit sur l'île › Réglages › Général › iPhone, et allume « Retrouver mon iPhone » avec le même compte iCloud."))
                        .font(.system(size: u(14))).foregroundStyle(PhoneTheme.gray).multilineTextAlignment(.center)
                        .padding(.horizontal, u(10)).padding(.bottom, u(22))
                    if !phone.linkOn {
                        PhoneHoldButton(label: loc("Maintenir pour relier"), color: Color(white: 0.96)) { phone.linkOn = true }
                    }
                    if let error = PhoneLink.shared.lastError {
                        Text(error).font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray).padding(.top, u(14))
                    }
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever()) { pulse = true } }
    }
}

struct PhoneDotLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 7)); configuration.title }
    }
}

/// « Maintenir pour… »: the outline fills while the finger stays, the action runs when it is full.
struct PhoneHoldButton: View {
    let label: String
    var color: Color = Color(white: 0.96)
    let action: () -> Void
    @State private var holding = false

    var body: some View {
        Text(label).font(.system(size: u(14), weight: .semibold))
            .frame(maxWidth: .infinity).frame(height: u(46))
            .background(alignment: .leading) {
                GeometryReader { geo in
                    color.opacity(0.25).frame(width: holding ? geo.size.width : 0)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.5))
            .contentShape(Capsule())
            .onLongPressGesture(minimumDuration: 0.9) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                action()
            } onPressingChanged: { on in
                withAnimation(on ? .linear(duration: 0.9) : .easeOut(duration: 0.2)) { holding = on }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
