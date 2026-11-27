import ActivityKit
import Foundation

/// Keeps Yumi in the Dynamic Island while the person wants him there (on by default, a switch in
/// Réglages). One activity at a time; iOS ends it after a few hours, the app starts it again.
@MainActor
enum PhoneDayActivity {
    static let key = "phoneDayActivity"
    private static let startedKey = "phoneDayActivityStartedAt"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if !newValue { Task { await endAll() } }
        }
    }

    /// When each agent of the Mac was first seen at work, to say how long it took once done.
    private static var workStarts: [String: Date] = [:]

    /// What the island shows now, from the day, the Mac and the mail: one moment at a time, the
    /// most pressing first.
    static func state(today: PhoneToday, mac: LinkSnapshot?, mails: [GmailMail] = [], now: Date = Date()) -> YumiDayActivity.ContentState {
        var state = moment(today: today, mac: mac, mails: mails, now: now)
        if case .ready(let report) = today.weather { state.degrees = PhoneWeather.degrees(report) }
        return state
    }

    private static func moment(today: PhoneToday, mac: LinkSnapshot?, mails: [GmailMail], now: Date) -> YumiDayActivity.ContentState {
        // Only a recent picture of the Mac: a session it never closed must not count up forever
        let freshMac = mac.flatMap { now.timeIntervalSince($0.sentAt) < IslandClock.macFreshness ? $0 : nil }
        if let approval = freshMac?.approvals.first(where: { $0.expiresAt > now }) {
            return .init(face: "asking", title: approval.summary, detail: loc("Ton Mac attend ton accord"),
                         at: nil, urgent: true, symbol: "hand.raised.fill", accent: "warn",
                         kicker: loc("Ton Mac attend ton accord"), value: "✋")
        }
        let sessions = freshMac?.sessions ?? []
        for session in sessions where PhoneAgentLook.state(session, waiting: false) == .working {
            if workStarts[session.id] == nil { workStarts[session.id] = session.updatedAt }
        }
        if let session = sessions.first(where: { PhoneAgentLook.state($0, waiting: false) == .working }),
           let since = IslandClock.workingSince(sessionUpdatedAt: workStarts[session.id] ?? session.updatedAt,
                                                snapshotSentAt: freshMac?.sentAt ?? .distantPast, now: now) {
            return .init(face: "working", title: "\(session.agent) · \(session.project)", detail: session.status,
                         at: nil, urgent: false, symbol: "hammer.fill", working: since, accent: "work",
                         kicker: loc("Au travail"))
        }
        if let next = today.events.first(where: { !$0.isAllDay && IslandClock.isSoon($0.start, now: now) }) {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            return .init(face: "thinking", title: next.title, detail: next.location.isEmpty ? time : "\(time) · \(next.location)",
                         at: next.start, urgent: false, symbol: "calendar", accent: "think", kicker: loc("Bientôt"))
        }
        if let late = today.reminders.first(where: { PhoneToday.dueLabel($0, now: now)?.late == true }) {
            return .init(face: "surprised", title: late.title, detail: loc("Rappel en retard"),
                         at: nil, urgent: true, symbol: "checklist", accent: "warn", kicker: loc("Rappel en retard"))
        }
        let fresh = mails.filter { $0.unread && !$0.bulk && IslandClock.isFreshMail($0.date, now: now) }
        if let mail = fresh.first(where: \.important) ?? fresh.first {
            return .init(face: "surprised", title: mail.subject, detail: mail.from,
                         at: nil, urgent: false, symbol: "envelope.fill", accent: "joy",
                         kicker: loc("Nouveau mail") + " · " + mail.from, value: "✉︎ \(fresh.count)")
        }
        if let done = sessions.first(where: { $0.status.contains("termin") && IslandClock.isJustDone($0.updatedAt, now: now) }) {
            let took = workStarts[done.id].map { IslandClock.duration(done.updatedAt.timeIntervalSince($0)) }
            return .init(face: "done", title: "\(done.agent) · \(done.project)", detail: loc("Terminé"),
                         at: nil, urgent: false, symbol: "checkmark", accent: "done",
                         kicker: took.map { loc("Terminé en") + " " + $0 } ?? loc("Terminé"),
                         value: took.map { "✓ " + $0 } ?? "✓")
        }
        if let next = today.events.first(where: { !$0.isAllDay && $0.end > now }) {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            let detail = next.start <= now ? loc("En cours") : (next.location.isEmpty ? time : "\(time) · \(next.location)")
            return .init(face: "happy", title: next.title, detail: detail,
                         at: next.start > now ? next.start : nil, urgent: false, symbol: "calendar", kicker: loc("Ta journée"))
        }
        if let due = today.reminders.first(where: { $0.due.map { Calendar.current.isDateInToday($0) } ?? false }) {
            return .init(face: "calm", title: due.title, detail: PhoneToday.dueLabel(due, now: now)?.text ?? loc("Aujourd'hui"),
                         at: due.hasTime ? due.due : nil, urgent: false, symbol: "checklist", kicker: loc("Ta journée"))
        }
        let hour = Calendar.current.component(.hour, from: now)
        let asleep = hour >= 22 || hour < 7
        if case .ready(let report) = today.weather {
            let sky = WeatherSummary.sky(report.code)
            let rain = report.hours.first { $0.time > now && $0.time.timeIntervalSince(now) < 6 * 3600 && $0.rainChance >= 50 }
            return .init(face: asleep ? "dozing" : "happy", title: sky.prefix(1).uppercased() + sky.dropFirst(),
                         detail: rain.map { loc("pluie vers") + " " + $0.time.formatted(date: .omitted, time: .shortened) } ?? "",
                         at: nil, urgent: false, symbol: WeatherSummary.symbol(for: today.weather), kicker: loc("Météo"),
                         value: PhoneWeather.degrees(report))
        }
        return .init(face: asleep ? "dozing" : "calm", title: loc("Rien d'autre aujourd'hui"), detail: loc("Je reste là."),
                     at: nil, urgent: false, symbol: "sun.max")
    }

    /// Starts or updates the activity. Nothing when it is off or when iOS refuses activities.
    static func update(today: PhoneToday, mac: LinkSnapshot?, mails: [GmailMail] = []) async {
        guard isOn, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = state(today: today, mac: mac, mails: mails)
        // Nothing to say at all: Yumi leaves the island rather than sit there doing nothing
        if state.symbol == "sun.max", state.working == nil, state.degrees == nil {
            await endAll()
            return
        }
        // Always a stale date: iOS dims it when the shown thing starts, the counter stops or the
        // picture of the Mac grows old, until the app runs again
        let now = Date()
        let content = ActivityContent(state: state, staleDate: IslandClock.staleDate(at: state.at, working: state.working, now: now))
        let startedAt = UserDefaults.standard.object(forKey: startedKey) as? Date ?? .distantPast
        if let activity = Activity<YumiDayActivity>.activities.first, !IslandClock.isTooOld(startedAt: startedAt, now: now) {
            guard activity.content.state != state else { return }
            await activity.update(content)
        } else {
            // Too old (or none): a fresh one, never two
            await endAll()
            if (try? Activity.request(attributes: YumiDayActivity(), content: content)) != nil {
                UserDefaults.standard.set(now, forKey: startedKey)
            }
        }
    }

    static func endAll() async {
        for activity in Activity<YumiDayActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
