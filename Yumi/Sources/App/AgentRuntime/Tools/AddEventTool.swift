import Foundation

/// The calendar new events go to, as far as the tool needs to know it.
struct EventCalendarInfo: Equatable, Sendable {
    var title: String
    /// False for a subscription, a birthdays calendar, or one that is read only.
    var acceptsNewEvents: Bool
}

/// An event as the Calendar app keeps it, read back to check what was saved.
struct StoredEvent: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var location: String?
    var calendar: String
    var hasAttendees: Bool
}

/// The Calendar app, as far as the agent needs it: add one event to the default calendar, read
/// it back. The EventKit implementation lives with the Agenda module (`EventKitEventStore`).
protocol EventStore: Sendable {
    var access: PermissionState { get }
    /// Shows macOS's own question about the calendar, once, when nobody answered it yet. True when granted.
    func requestAccess() async -> Bool
    func defaultCalendar() -> EventCalendarInfo?
    /// Saves a new event, without attendees, in the default calendar. Returns its identifier.
    func add(title: String, start: Date, end: Date, location: String?) throws -> String
    func event(id: String) -> StoredEvent?
}

/// Adds one event to the person's default calendar: a title, a day, a start time, a duration,
/// and a place when given. Never invites anyone, never writes to a shared or subscribed
/// calendar, never changes an existing event.
struct AddEventTool: Tool {
    static let maxTitleLength = 120
    static let maxLocationLength = 120
    static let defaultMinutes = 60
    static let minutes = 5...720

    var store: any EventStore
    var calendar: Calendar
    var now: @Sendable () -> Date

    init(store: any EventStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "add_event",
            name: loc("Add an event"),
            description: "Adds one event to the person's default calendar, without inviting anyone; never changes an existing event. Needs a day and a start time.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "title", type: .string, required: true, description: "what it is, as the person said it (Réunion client)"),
                .init(name: "date", type: .string, required: true, description: "YYYY-MM-DD, worked out from <now>"),
                .init(name: "time", type: .string, required: true, description: "start, HH:mm, 24 hours"),
                .init(name: "duration_minutes", type: .number, required: false, description: "5 to 720, 60 when the person gives none"),
                .init(name: "location", type: .string, required: false, description: "only when the person names a place"),
            ]),
            risk: .write,
            outputKeys: ["id", "title", "reply"])
    }

    /// The approval shows the event itself: title, day and hours in words, calendar.
    func action(for arguments: ToolArguments) -> ToolAction? {
        guard let title = line(arguments["title"], limit: Self.maxTitleLength) else { return nil }
        var text = loc("l'événement « \(title) »")
        if let (start, end) = try? moment(arguments, allowingPast: true) { text += ", \(spoken(start, end))" }
        if let place = line(arguments["location"], limit: Self.maxLocationLength) { text += loc(", à \(place)") }
        text += loc(", dans le calendrier \(store.defaultCalendar()?.title ?? "par défaut")")
        return ToolAction(kind: .create, resources: [ResourceRef(.unknown, text)], reversible: true)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        if store.access == .notDetermined { _ = await store.requestAccess() }
        if let problem = accessProblem() { return problem }
        do { _ = try fields(arguments) } catch { return error.reason }
        guard let target = store.defaultCalendar() else { return loc("je ne trouve pas de calendrier par défaut") }
        if !target.acceptsNewEvents { return loc("ton calendrier par défaut, \(target.title), n'accepte pas de nouvel événement") }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        if let problem = accessProblem() { throw ToolError.failed(problem) }
        let (title, start, end, location) = try fields(arguments)
        guard let target = store.defaultCalendar(), target.acceptsNewEvents else {
            throw ToolError.failed(loc("ton calendrier par défaut n'accepte pas de nouvel événement"))
        }
        try Task.checkCancellation()
        let id: String
        do {
            id = try store.add(title: title, start: start, end: end, location: location)
        } catch {
            throw ToolError.failed(loc("Calendrier n'a pas enregistré l'événement (\((error as NSError).domain) \((error as NSError).code))"))
        }
        return ToolOutput(summary: "Added the event \(title).",
                          values: ["id": .string(id), "title": .string(title),
                                   "reply": .string(loc("C'est dans ton calendrier : \(title), \(spoken(start, end))."))])
    }

    /// The event exists with this title and these hours, and nobody is invited.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let id)? = output.values["id"], let (title, start, end, _) = try? fields(arguments, allowingPast: true) else {
            return loc("aucun événement à vérifier")
        }
        guard let saved = store.event(id: id) else { return loc("l'événement « \(title) » n'est pas dans ton calendrier") }
        if saved.title != title { return loc("l'événement enregistré s'appelle « \(saved.title) », pas « \(title) »") }
        if abs(saved.start.timeIntervalSince(start)) > 1 || abs(saved.end.timeIntervalSince(end)) > 1 {
            return loc("l'événement « \(title) » n'a pas les heures demandées")
        }
        if saved.hasAttendees { return loc("l'événement « \(title) » a des invités") }
        return nil
    }

    // MARK: - Arguments

    private func accessProblem() -> String? {
        #if os(iOS)
        switch store.access {
        case .granted: nil
        case .notDetermined: loc("iOS ne m'a pas encore donné accès à ton calendrier. Réponds « Autoriser » à sa question, ou autorise Yumi dans Réglages, Confidentialité et sécurité, Calendriers, puis redemande-moi")
        case .denied: loc("iOS ne me laisse pas accéder à ton calendrier. Autorise Yumi dans Réglages, Confidentialité et sécurité, Calendriers")
        }
        #else
        switch store.access {
        case .granted: nil
        case .notDetermined: loc("macOS ne m'a pas encore donné accès à ton calendrier. Réponds « Autoriser » à sa question, ou autorise Yumi dans Réglages Système, Confidentialité et sécurité, Calendriers, puis redemande-moi")
        case .denied: loc("macOS ne me laisse pas accéder à ton calendrier. Autorise Yumi dans Réglages Système, Confidentialité et sécurité, Calendriers")
        }
        #endif
    }

    private func fields(_ arguments: ToolArguments, allowingPast: Bool = false) throws(ToolError) -> (String, Date, Date, String?) {
        guard let title = line(arguments["title"], limit: Self.maxTitleLength) else {
            throw .invalidInput(loc("il me faut un titre d'une ligne, de \(Self.maxTitleLength) caractères au plus"))
        }
        let (start, end) = try moment(arguments, allowingPast: allowingPast)
        var location: String?
        if arguments["location"] != nil {
            guard let place = line(arguments["location"], limit: Self.maxLocationLength) else {
                throw .invalidInput(loc("le lieu doit tenir sur une ligne de \(Self.maxLocationLength) caractères au plus"))
            }
            location = place
        }
        return (title, start, end, location)
    }

    /// Start and end. The day and the time are both required: "jeudi" alone or "14 h" alone is ambiguous.
    func moment(_ arguments: ToolArguments, allowingPast: Bool = false) throws(ToolError) -> (Date, Date) {
        guard case .string(let date)? = arguments["date"], let day = date.nonEmptyTrimmed else {
            throw .invalidInput(loc("il me faut le jour exact de l'événement"))
        }
        guard case .string(let time)? = arguments["time"], let hour = time.nonEmptyTrimmed else {
            throw .invalidInput(loc("il me faut l'heure de début de l'événement"))
        }
        let dayParts = day.split(separator: "-").map { Int($0) }
        guard dayParts.count == 3, let year = dayParts[0], let month = dayParts[1], let dayNumber = dayParts[2] else {
            throw .invalidInput(loc("« \(day) » n'est pas une date précise (AAAA-MM-JJ)"))
        }
        let timeParts = hour.split(separator: ":").map { Int($0) }
        guard timeParts.count == 2, let h = timeParts[0], let m = timeParts[1], (0...23).contains(h), (0...59).contains(m) else {
            throw .invalidInput(loc("« \(hour) » n'est pas une heure (HH:mm)"))
        }
        let wanted = DateComponents(year: year, month: month, day: dayNumber, hour: h, minute: m)
        guard let start = calendar.date(from: wanted),
              calendar.dateComponents([.year, .month, .day], from: start) == DateComponents(year: year, month: month, day: dayNumber) else {
            throw .invalidInput(loc("« \(day) » n'existe pas dans le calendrier"))
        }
        var minutes = Self.defaultMinutes
        if let value = arguments["duration_minutes"] {
            guard case .number(let number) = value, number.rounded() == number, Self.minutes.contains(Int(number)) else {
                throw .invalidInput(loc("la durée doit être entre 5 minutes et 12 heures"))
            }
            minutes = Int(number)
        }
        if start <= now() && !allowingPast { throw .invalidInput(loc("\(spoken(start, start)), c'est déjà passé")) }
        return (start, start.addingTimeInterval(Double(minutes) * 60))
    }

    private func line(_ value: ToolValue?, limit: Int) -> String? {
        guard case .string(let raw)? = value else { return nil }
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= limit, !text.contains(where: \.isNewline) else { return nil }
        return text
    }

    /// "jeudi 9 octobre, 14 h à 15 h", "jeudi 9 octobre, 23 h à 1 h le lendemain".
    func spoken(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = loc("EEEE d MMMM")
        var text = formatter.string(from: start) + ", " + clock(start)
        if end > start {
            text += loc(" à ") + clock(end)
            if !calendar.isDate(end, inSameDayAs: start) { text += loc(" le lendemain") }
        }
        return text
    }

    private func clock(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = parts.minute ?? 0
        return minute == 0 ? "\(parts.hour ?? 0) h" : String(format: "%d h %02d", parts.hour ?? 0, minute)
    }
}
