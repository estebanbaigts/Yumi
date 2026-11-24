import ActivityKit
import Foundation

/// Keeps Yumi in the Dynamic Island while the person wants him there (on by default, a switch in
/// Réglages). One activity at a time; iOS ends it after a few hours, the app starts it again.
@MainActor
enum PhoneDayActivity {
    static let key = "phoneDayActivity"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if !newValue { Task { await endAll() } }
        }
    }

    /// What the island shows now, from the day and the Mac.
    static func state(today: PhoneToday, mac: LinkSnapshot?, now: Date = Date()) -> YumiDayActivity.ContentState {
        var state = dayState(today: today, mac: mac, now: now)
        if !state.urgent, let session = mac?.sessions.first(where: { PhoneAgentLook.state($0, waiting: false) == .working }) {
            state.working = session.updatedAt
        }
        if case .ready(let report) = today.weather { state.degrees = PhoneWeather.degrees(report) }
        return state
    }

    private static func dayState(today: PhoneToday, mac: LinkSnapshot?, now: Date) -> YumiDayActivity.ContentState {
        if let approval = mac?.approvals.first(where: { $0.expiresAt > now }) {
            return .init(face: "asking", title: approval.summary, detail: loc("Ton Mac attend ton accord"),
                         at: nil, urgent: true, symbol: "hand.raised.fill")
        }
        if let late = today.reminders.first(where: { PhoneToday.dueLabel($0, now: now)?.late == true }) {
            return .init(face: "surprised", title: late.title, detail: loc("Rappel en retard"),
                         at: nil, urgent: true, symbol: "checklist")
        }
        if let next = today.events.first(where: { !$0.isAllDay && $0.end > now }) {
            let time = next.start.formatted(date: .omitted, time: .shortened)
            let detail = next.start <= now ? loc("En cours") : (next.location.isEmpty ? time : "\(time) · \(next.location)")
            return .init(face: "happy", title: next.title, detail: detail,
                         at: next.start > now ? next.start : nil, urgent: false, symbol: "calendar")
        }
        if let due = today.reminders.first(where: { $0.due.map { Calendar.current.isDateInToday($0) } ?? false }) {
            return .init(face: "calm", title: due.title, detail: PhoneToday.dueLabel(due, now: now)?.text ?? loc("Aujourd'hui"),
                         at: due.hasTime ? due.due : nil, urgent: false, symbol: "checklist")
        }
        let hour = Calendar.current.component(.hour, from: now)
        return .init(face: hour >= 22 || hour < 7 ? "asleep" : "calm", title: loc("Rien d'autre aujourd'hui"), detail: loc("Je reste là."),
                     at: nil, urgent: false, symbol: "sun.max")
    }

    /// Starts or updates the activity. Nothing when it is off or when iOS refuses activities.
    static func update(today: PhoneToday, mac: LinkSnapshot?) async {
        guard isOn, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = state(today: today, mac: mac)
        // Nothing to say at all: Yumi leaves the island rather than sit there doing nothing
        if state.symbol == "sun.max", state.working == nil, state.degrees == nil {
            await endAll()
            return
        }
        // Stale when the shown thing starts: iOS dims it until the app runs again
        let content = ActivityContent(state: state, staleDate: state.at.map { $0.addingTimeInterval(60) })
        if let activity = Activity<YumiDayActivity>.activities.first {
            guard activity.content.state != state else { return }
            await activity.update(content)
        } else {
            _ = try? Activity.request(attributes: YumiDayActivity(), content: content)
        }
    }

    static func endAll() async {
        for activity in Activity<YumiDayActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
