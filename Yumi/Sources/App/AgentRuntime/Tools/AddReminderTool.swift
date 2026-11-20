import Foundation

/// A reminder as the Reminders app keeps it, read back to check what was saved.
struct StoredReminder: Equatable, Sendable {
    var title: String
    /// Year, month, day, and the hour and minute when it has a time.
    var due: DateComponents?
    var list: String
}

/// The Reminders app, as far as the agent needs it: add one to the default list, read it back.
/// The EventKit implementation lives with the Notes module (`EventKitReminderStore`).
protocol ReminderStore: Sendable {
    var access: PermissionState { get }
    /// The name of the list new reminders go to, nil when there is none.
    func defaultListName() -> String?
    /// Saves a new reminder in the default list. Returns its identifier.
    func add(title: String, due: DateComponents?) throws -> String
    func reminder(id: String) -> StoredReminder?
    /// Shows macOS's own question about Reminders, once, when nobody answered it yet. True when granted.
    func requestAccess() async -> Bool
}

/// Adds one reminder to the default list of the Reminders app: a title, and a date and a time
/// when the person gave them. Never changes, completes or removes an existing reminder.
struct AddReminderTool: Tool {
    static let maxTitleLength = 120

    var store: any ReminderStore
    var calendar: Calendar
    var now: @Sendable () -> Date

    init(store: any ReminderStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    var descriptor: ToolDescriptor {
        ToolDescriptor(
            id: "add_reminder",
            name: loc("Add a reminder"),
            description: "Adds one reminder to the default list of the Reminders app, with a date and a time when the person gives them; never changes an existing reminder.",
            inputSchema: ToolInputSchema(fields: [
                .init(name: "title", type: .string, required: true, description: "what to remember, as the person said it (Appeler le dentiste)"),
                .init(name: "date", type: .string, required: false, description: "YYYY-MM-DD, worked out from <now>; omit when the person gives no day"),
                .init(name: "time", type: .string, required: false, description: "HH:mm, 24 hours; omit when the person gives no time"),
            ]),
            risk: .write,
            outputKeys: ["id", "title", "reply"])
    }

    /// The approval shows the reminder itself: its title, when, and the list.
    func action(for arguments: ToolArguments) -> ToolAction? {
        guard let title = title(arguments) else { return nil }
        var text = loc("le rappel « \(title) »")
        if let due = try? due(arguments, allowingPast: true) { text += ", \(spoken(due))" }
        text += loc(", dans la liste \(store.defaultListName() ?? "par défaut")")
        return ToolAction(kind: .create, resources: [ResourceRef(.unknown, text)], reversible: true)
    }

    func check(_ arguments: ToolArguments) async -> String? {
        // Never asked yet: macOS asks the person now, before Yumi's own approval. Their answer is
        // the system's to keep; nothing is added or changed here.
        if store.access == .notDetermined { _ = await store.requestAccess() }
        if let problem = accessProblem() { return problem }
        guard title(arguments) != nil else { return loc("il me faut un titre d'une ligne, de \(Self.maxTitleLength) caractères au plus") }
        do { _ = try due(arguments) } catch { return error.reason }
        if store.defaultListName() == nil { return loc("je ne trouve pas de liste par défaut dans Rappels") }
        return nil
    }

    func execute(_ arguments: ToolArguments, in context: ToolContext) async throws -> ToolOutput {
        if let problem = accessProblem() { throw ToolError.failed(problem) }
        guard let title = title(arguments) else { throw ToolError.invalidInput(loc("il me faut un titre d'une ligne")) }
        let due = try due(arguments)
        try Task.checkCancellation()
        let id: String
        do {
            id = try store.add(title: title, due: due)
        } catch {
            throw ToolError.failed(loc("Rappels n'a pas enregistré le rappel (\((error as NSError).domain) \((error as NSError).code))"))
        }
        let when = due.map { ", \(spoken($0))" } ?? ""
        return ToolOutput(summary: "Added the reminder \(title).",
                          values: ["id": .string(id), "title": .string(title),
                                   "reply": .string(loc("C'est noté dans tes Rappels : \(title)\(when)."))])
    }

    /// The reminder exists, with this title and this date.
    func verify(_ arguments: ToolArguments, output: ToolOutput) async -> String? {
        guard case .string(let id)? = output.values["id"], let title = title(arguments) else { return loc("aucun rappel à vérifier") }
        guard let saved = store.reminder(id: id) else { return loc("le rappel « \(title) » n'est pas dans Rappels") }
        if saved.title != title { return loc("le rappel enregistré s'appelle « \(saved.title) », pas « \(title) »") }
        // The moment may have passed since the reminder was saved: only its date counts here.
        let expected = try? due(arguments, allowingPast: true)
        if Self.key(saved.due) != Self.key(expected) { return loc("le rappel « \(title) » n'a pas la date demandée") }
        return nil
    }

    // MARK: - Arguments

    private func accessProblem() -> String? {
        #if os(iOS)
        switch store.access {
        case .granted: nil
        case .notDetermined: loc("iOS ne m'a pas encore donné accès à tes Rappels. Réponds « Autoriser » à sa question, ou autorise Yumi dans Réglages, Confidentialité et sécurité, Rappels, puis redemande-moi")
        case .denied: loc("iOS ne me laisse pas accéder à tes Rappels. Autorise Yumi dans Réglages, Confidentialité et sécurité, Rappels")
        }
        #else
        switch store.access {
        case .granted: nil
        case .notDetermined: loc("macOS ne m'a pas encore donné accès à tes Rappels. Réponds « Autoriser » à sa question, ou autorise Yumi dans Réglages Système, Confidentialité et sécurité, Rappels, puis redemande-moi")
        case .denied: loc("macOS ne me laisse pas accéder à tes Rappels. Autorise Yumi dans Réglages Système, Confidentialité et sécurité, Rappels")
        }
        #endif
    }

    /// One line, not empty, not too long.
    private func title(_ arguments: ToolArguments) -> String? {
        guard case .string(let raw)? = arguments["title"] else { return nil }
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= Self.maxTitleLength, !title.contains(where: \.isNewline) else { return nil }
        return title
    }

    /// The due date, nil when none was given. A time alone is for today. Never in the past.
    func due(_ arguments: ToolArguments, allowingPast: Bool = false) throws(ToolError) -> DateComponents? {
        var date: String?
        var time: String?
        if let value = arguments["date"] {
            guard case .string(let text) = value else { throw .invalidInput(loc("la date doit s'écrire AAAA-MM-JJ")) }
            date = text.nonEmptyTrimmed
        }
        if let value = arguments["time"] {
            guard case .string(let text) = value else { throw .invalidInput(loc("l'heure doit s'écrire HH:mm")) }
            time = text.nonEmptyTrimmed
        }
        guard date != nil || time != nil else { return nil }

        let today = calendar.dateComponents([.year, .month, .day], from: now())
        var components = DateComponents()
        if let date {
            let parts = date.split(separator: "-").map { Int($0) }
            guard parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2] else {
                throw .invalidInput(loc("« \(date) » n'est pas une date (AAAA-MM-JJ)"))
            }
            components.year = year; components.month = month; components.day = day
        } else {
            components.year = today.year; components.month = today.month; components.day = today.day
        }
        if let time {
            let parts = time.split(separator: ":").map { Int($0) }
            guard parts.count == 2, let hour = parts[0], let minute = parts[1], (0...23).contains(hour), (0...59).contains(minute) else {
                throw .invalidInput(loc("« \(time) » n'est pas une heure (HH:mm)"))
            }
            components.hour = hour; components.minute = minute
        }
        // The calendar rolls a 31 September over to 1 October: a day that changed did not exist.
        guard let moment = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: moment)
                == DateComponents(year: components.year, month: components.month, day: components.day) else {
            throw .invalidInput(loc("« \(date ?? "") » n'existe pas dans le calendrier"))
        }
        let past = time == nil ? calendar.startOfDay(for: moment) < calendar.startOfDay(for: now()) : moment <= now()
        if past && !allowingPast { throw .invalidInput(loc("\(spoken(components)), c'est déjà passé")) }
        return components
    }

    /// "demain à 10:00", "aujourd'hui", "le 12/10 à 9:30".
    private func spoken(_ due: DateComponents) -> String {
        let startOfToday = calendar.startOfDay(for: now())
        let day = calendar.date(from: DateComponents(year: due.year, month: due.month, day: due.day)) ?? startOfToday
        let offset = calendar.dateComponents([.day], from: startOfToday, to: calendar.startOfDay(for: day)).day ?? 0
        var text = switch offset {
        case 0: loc("aujourd'hui")
        case 1: loc("demain")
        case 2: loc("après-demain")
        default: day.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(AppLanguage.locale))
        }
        if let hour = due.hour { text += loc(" à \(String(format: "%d:%02d", hour, due.minute ?? 0))") }
        return text
    }

    /// What counts when two due dates are compared.
    private static func key(_ due: DateComponents?) -> [Int?]? {
        due.map { [$0.year, $0.month, $0.day, $0.hour, $0.minute] }
    }
}
