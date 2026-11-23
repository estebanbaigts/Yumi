import AppKit
import EventKit

/// The Mac's calendars through EventKit: what is on now, what comes next.
@MainActor
final class AgendaModule: YumiModule {
    let id = "agenda"

    private let eventStore = EKEventStore()
    private var events: [AgendaEvent] = []
    private var onChange: (@MainActor () -> Void)?
    private var storeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var ticking: Task<Void, Never>?

    var snapshot: ModuleSnapshot {
        AgendaSummary.withDays(AgendaSummary.snapshot(events: events, access: access, now: Date()),
                               events: week, now: Date())
    }
    /// The next seven days, for the day and week columns of the island's agenda page.
    private var week: [AgendaEvent] = []

    /// Today's appointments still to come (not the all-day ones), for whoever needs more than the snapshot.
    /// nil when the calendar cannot be read.
    var upcomingToday: [AgendaEvent]? {
        guard access == .granted else { return nil }
        let now = Date()
        return events.filter { !$0.isAllDay && $0.start > now && Calendar.current.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }
    }

    /// On, but macOS does not let Yumi read the calendar.
    var runsWithoutAccess: Bool { onChange != nil && access != .granted }

    /// Today's appointments still to come, nil while the module is stopped or without access.
    var upcomingTodayIfRunning: [AgendaEvent]? { onChange == nil ? nil : upcomingToday }

    private var access: PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:    return .granted
        case .notDetermined: return .notDetermined
        default:             return .denied
        }
    }

    // MARK: Lifecycle

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .agendaCalendarsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        // "dans 12 min" changes every minute. Without the permission a tick costs nothing.
        ticking = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.reload()
                let wait = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
                try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(1))
            }
        }
    }

    func stop() {
        onChange = nil
        ticking?.cancel()
        ticking = nil
        for observer in [storeObserver, settingsObserver].compactMap({ $0 }) { NotificationCenter.default.removeObserver(observer) }
        storeObserver = nil
        settingsObserver = nil
        events = []
    }

    // MARK: Actions

    func perform(_ action: ModuleAction) {
        switch access {
        case .notDetermined:
            guard action == .primary else { return }
            eventStore.requestFullAccessToEvents { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.reload() }
            }
        case .denied:
            if action == .primary { NSWorkspace.shared.open(PrivacySettings.calendars) }
        case .granted:
            if action == .primary, let url = AgendaSummary.featured(events, now: Date())?.joinURL {
                NSWorkspace.shared.open(url)
            } else {
                openCalendar()
            }
        }
    }

    private func openCalendar() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    // MARK: Events

    /// Every appointment of one day, cancelled ones aside, for the agent. nil while the module is
    /// stopped or without access.
    func events(on day: Date, calendar: Calendar = .current) -> [AgendaEvent]? {
        guard onChange != nil, access == .granted else { return nil }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return read(from: start, to: end).sorted { $0.start < $1.start }
    }

    private func read(from start: Date, to end: Date) -> [AgendaEvent] {
        // Only the calendars chosen in the settings; an empty choice reads nothing.
        let all = eventStore.calendars(for: .event)
        let calendars = AgendaCalendars.shown(among: all.map(\.calendarIdentifier)).map { ids in all.filter { ids.contains($0.calendarIdentifier) } }
        if calendars?.isEmpty == true { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                AgendaEvent(id: event.eventIdentifier ?? UUID().uuidString,
                            title: event.title ?? loc("Événement"),
                            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
                            location: event.location ?? "",
                            joinURL: AgendaSummary.joinURL(in: [event.url?.absoluteString, event.location, event.notes]))
            }
    }

    /// Reads today's and tomorrow's events, then reports. Does nothing without the permission.
    private func reload() {
        if access == .granted {
            let calendar = Calendar.current
            let start = Date()
            let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: start)) ?? start
            events = read(from: start, to: end)
            let dayStart = calendar.startOfDay(for: start)
            week = read(from: dayStart, to: calendar.date(byAdding: .day, value: 7, to: dayStart) ?? end)
        } else {
            events = []
            week = []
        }
        onChange?()
    }
}
