import CoreLocation
import EventKit
import Foundation
import Observation

/// The day on the iPhone: calendar, reminders, notes and weather, read only after the person
/// taps the matching button (never at launch). Uses the same summaries as the Mac's modules.
@MainActor
@Observable
final class PhoneToday {
    private(set) var events: [AgendaEvent] = []
    /// The days ahead that have something, today first, a week at most.
    private(set) var week: [(day: Date, events: [AgendaEvent])] = []
    private(set) var calendarAccess: PermissionState = .notDetermined
    private(set) var reminders: [ReminderItem] = []
    private(set) var remindersAccess: PermissionState = .notDetermined
    private(set) var notes: [String] = []
    private(set) var weather: WeatherState = .needsLocation(.notDetermined)

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let notesStore: NotesStore?
    @ObservationIgnored private let live: Bool

    init(live: Bool, notesURL: URL?) {
        self.live = live
        notesStore = notesURL.map { NotesStore(fileURL: $0) }
    }

    static func studio() -> PhoneToday {
        let today = PhoneToday(live: false, notesURL: nil)
        today.events = PhoneStudio.events
        today.week = PhoneStudio.week
        today.calendarAccess = .granted
        today.reminders = PhoneStudio.reminders
        today.remindersAccess = .granted
        today.notes = PhoneStudio.notes
        today.weather = .ready(PhoneStudio.weather)
        return today
    }

    var featuredEvent: AgendaEvent? { AgendaSummary.featured(events, now: Date()) }

    /// What was already allowed is read again; nothing is asked.
    func refresh() async {
        guard live else { return }
        calendarAccess = Self.state(EKEventStore.authorizationStatus(for: .event))
        remindersAccess = Self.state(EKEventStore.authorizationStatus(for: .reminder))
        if calendarAccess == .granted { loadEvents() }
        if remindersAccess == .granted { await loadReminders() }
        notes = notesStore?.load() ?? []
        if CLLocationManager().authorizationStatus.isAllowed { await loadWeather() }
    }

    // MARK: - Asked from a button

    func askCalendar() async {
        guard live else { return }
        calendarAccess = ((try? await store.requestFullAccessToEvents()) ?? false) ? .granted : .denied
        if calendarAccess == .granted { loadEvents() }
    }

    func askReminders() async {
        guard live else { return }
        remindersAccess = ((try? await store.requestFullAccessToReminders()) ?? false) ? .granted : .denied
        if remindersAccess == .granted { await loadReminders() }
    }

    func loadWeather() async {
        guard live else { return }
        weather = .loading
        // A session asks for "when in use" once, from this tap, and lasts as long as it is kept
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        var place: CLLocation?
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if update.authorizationDenied || update.authorizationDeniedGlobally {
                    weather = .needsLocation(.denied)
                    return
                }
                if let location = update.location { place = location; break }
            }
        } catch {
            weather = .unavailable
            return
        }
        guard let place else { weather = .unavailable; return }
        // Open-Meteo, as on the Mac: no key, no account, the place rounded by the API itself
        let url = OpenMeteo.forecastURL(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            weather = .ready(try OpenMeteo.decodeForecast(data))
        } catch {
            weather = .unavailable
        }
    }

    func addNote(_ text: String) {
        guard let notesStore, notesStore.add(text) != nil else { return }
        notes = notesStore.load()
    }

    // MARK: - Reading

    private func loadEvents() {
        events = events(on: Date())
        week = Self.days(from: Date()).compactMap { day in
            let list = Calendar.current.isDateInToday(day) ? events : events(on: day)
            return list.isEmpty ? nil : (day, list)
        }
    }

    /// The events of a day, read again from the calendar (empty without access, or in filming
    /// mode for any day but today).
    func events(on day: Date) -> [AgendaEvent] {
        guard live else { return Calendar.current.isDateInToday(day) ? events : [] }
        guard calendarAccess == .granted else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }.map { event in
            AgendaEvent(id: event.eventIdentifier ?? UUID().uuidString, title: event.title ?? "",
                        start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                        location: event.location ?? "",
                        joinURL: AgendaSummary.joinURL(in: [event.location, event.notes, event.url?.absoluteString]))
        }
    }

    /// When a reminder is due, short: « 18:00 », « Demain 9:00 », « lun. 23 nov. », « En retard ».
    static func dueLabel(_ reminder: ReminderItem, now: Date = Date()) -> (text: String, late: Bool)? {
        guard let due = reminder.due else { return nil }
        let calendar = Calendar.current
        let time = due.formatted(.dateTime.hour().minute().locale(AppLanguage.locale))
        let late = reminder.hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
        if late { return (loc("En retard"), true) }
        if calendar.isDateInToday(due) { return (reminder.hasTime ? time : loc("Aujourd'hui"), false) }
        if calendar.isDateInTomorrow(due) { return (reminder.hasTime ? loc("Demain \(time)") : loc("Demain"), false) }
        let day = due.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLanguage.locale))
        return (reminder.hasTime ? "\(day) \(time)" : day, false)
    }

    /// Today and the six days after it.
    static func days(from now: Date) -> [Date] {
        let start = Calendar.current.startOfDay(for: now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    /// « Aujourd'hui », « Demain », « lundi 23 novembre ».
    static func dayName(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return loc("Aujourd'hui") }
        if Calendar.current.isDateInTomorrow(day) { return loc("Demain") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))
    }

    /// The day told plainly, from the real data only: what Yumi answers when asked « qu'est-ce
    /// que j'ai aujourd'hui ? », and what Apple's model reads through its tool.
    func told(tomorrow: Bool = false, now: Date = Date()) -> String {
        let day = tomorrow ? (Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now) : now
        var parts: [String] = []
        switch calendarAccess {
        case .granted:
            let upcoming = events(on: day).filter { tomorrow || $0.isAllDay || $0.end > now }
            if upcoming.isEmpty {
                parts.append(tomorrow ? loc("Rien de prévu demain.") : loc("Plus rien de prévu aujourd'hui."))
            } else {
                let list = upcoming.map { event in
                    event.isAllDay ? event.title
                                   : "\(event.start.formatted(date: .omitted, time: .shortened)) \(event.title)"
                }.joined(separator: ", ")
                parts.append(tomorrow ? loc("Demain : \(list).") : loc("Aujourd'hui : \(list)."))
            }
        default:
            parts.append(loc("Je ne vois pas encore ton agenda : touche « Voir mon agenda » sur l'accueil."))
        }
        if remindersAccess == .granted, !reminders.isEmpty {
            let names = reminders.prefix(4).map(\.title).joined(separator: ", ")
            parts.append(loc("Rappels : \(names)."))
        }
        if !tomorrow, case .ready(let report) = weather {
            parts.append(WeatherSummary.advice(report, now: now))
        }
        return parts.joined(separator: "\n")
    }

    private func loadReminders() async {
        reminders = NotesSummary.ordered(await Self.fetchReminders())
    }

    /// EventKit answers on a queue of its own: this closure must not belong to the main actor.
    /// EKReminder is not Sendable either: it becomes plain values before leaving that queue.
    /// A store of its own: EKEventStore is not Sendable, and the access is the app's, not the store's.
    private nonisolated static func fetchReminders() async -> [ReminderItem] {
        let store = EKEventStore()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { @Sendable found in
                let items = (found ?? []).map { reminder in
                    ReminderItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                                 due: reminder.dueDateComponents?.date,
                                 hasTime: reminder.dueDateComponents?.hour != nil)
                }
                continuation.resume(returning: items)
            }
        }
    }

    private static func state(_ status: EKAuthorizationStatus) -> PermissionState {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}

private extension CLAuthorizationStatus {
    var isAllowed: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}
