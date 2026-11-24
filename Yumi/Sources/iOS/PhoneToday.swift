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
    /// The town of the weather, found by the system from the place (nothing more is kept).
    private(set) var placeName = ""

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private let notesStore: NotesStore?
    @ObservationIgnored private let live: Bool

    /// Called when the day changed (another app, a tap, the clock): the widgets and the island follow.
    @ObservationIgnored var changed: (() -> Void)?
    @ObservationIgnored private var watching: Task<Void, Never>?
    @ObservationIgnored private var ticking: Task<Void, Never>?

    init(live: Bool, notesURL: URL?) {
        self.live = live
        notesStore = notesURL.map { NotesStore(fileURL: $0) }
    }

    /// Keeps the day current: read again when the calendar or the reminders change (here or in
    /// another app), and each minute so that what is over leaves the list.
    func watch() {
        guard watching == nil else { return }
        watching = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                await self?.refresh()
                self?.changed?()
            }
        }
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.tick()
            }
        }
    }

    /// A minute passed: events that are over leave today's list.
    private func tick() {
        let before = events.map(\.id)
        if live, calendarAccess == .granted { loadEvents() } else { dropPast() }
        if events.map(\.id) != before { changed?() }
    }

    private func dropPast(now: Date = Date()) {
        events = events.filter { $0.isAllDay || $0.end > now }
        week = week.compactMap { day in
            let list = day.events.filter { $0.isAllDay || $0.end > now }
            return list.isEmpty ? nil : (day.day, list)
        }
    }

    // MARK: - Changes, from a tap of the person

    /// Ticks a reminder off: it leaves the list.
    func complete(_ reminder: ReminderItem) {
        reminders.removeAll { $0.id == reminder.id }
        guard live, let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        item.isCompleted = true
        try? store.save(item, commit: true)
    }

    /// Deletes a reminder (after the person confirmed it).
    func delete(_ reminder: ReminderItem) {
        reminders.removeAll { $0.id == reminder.id }
        guard live, let item = store.calendarItem(withIdentifier: reminder.id) as? EKReminder else { return }
        try? store.remove(item, commit: true)
    }

    /// Deletes an event (after the person confirmed it). Only this occurrence of a repeating one.
    func delete(_ event: AgendaEvent) {
        events.removeAll { $0.id == event.id }
        week = week.compactMap { day in
            let list = day.events.filter { $0.id != event.id }
            return list.isEmpty ? nil : (day.day, list)
        }
        guard live, let item = store.event(withIdentifier: event.id) else { return }
        try? store.remove(item, span: .thisEvent, commit: true)
        loadEvents()
    }

    /// Adds a reminder, with a due date when one was chosen.
    func addReminder(title: String, due: Date?, hasTime: Bool) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard live else {
            reminders = NotesSummary.ordered(reminders + [ReminderItem(id: UUID().uuidString, title: title, due: due, hasTime: hasTime)])
            return
        }
        guard remindersAccess == .granted, let list = store.defaultCalendarForNewReminders() else { return }
        let item = EKReminder(eventStore: store)
        item.title = title
        item.calendar = list
        if let due {
            let parts: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            item.dueDateComponents = Calendar.current.dateComponents(parts, from: due)
            if hasTime { item.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        try? store.save(item, commit: true)
        Task { await loadReminders() }
    }

    /// Adds an event to the default calendar. Never with guests.
    func addEvent(title: String, start: Date, minutes: Int, allDay: Bool) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let end = allDay ? start : start.addingTimeInterval(Double(minutes) * 60)
        guard live else {
            let event = AgendaEvent(id: UUID().uuidString, title: title, start: start, end: end, isAllDay: allDay,
                                    location: "", joinURL: nil)
            if Calendar.current.isDateInToday(start) { events = (events + [event]).sorted { $0.start < $1.start } }
            var days = week
            if let index = days.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: start) }) {
                days[index].events = (days[index].events + [event]).sorted { $0.start < $1.start }
            } else {
                days.append((Calendar.current.startOfDay(for: start), [event]))
                days.sort { $0.day < $1.day }
            }
            week = days
            return
        }
        guard calendarAccess == .granted, let calendar = store.defaultCalendarForNewEvents else { return }
        let item = EKEvent(eventStore: store)
        item.title = title
        item.calendar = calendar
        item.isAllDay = allDay
        item.startDate = allDay ? Calendar.current.startOfDay(for: start) : start
        item.endDate = allDay ? Calendar.current.startOfDay(for: start) : end
        try? store.save(item, span: .thisEvent, commit: true)
        loadEvents()
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
        today.placeName = "Paris"
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
        // The weather waits for the place and the network: it comes on its own, the rest does not wait for it
        if CLLocationManager().authorizationStatus.isAllowed {
            Task { await loadWeather(); changed?() }
        }
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
        // A weather already shown stays while the new one comes
        if case .ready = weather {} else { weather = .loading }
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
        if let town = try? await CLGeocoder().reverseGeocodeLocation(place).first?.locality { placeName = town }
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
        let now = Date()
        // What is over leaves today's list (a day-long event stays the whole day)
        events = events(on: now).filter { $0.isAllDay || $0.end > now }
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
