import Foundation

/// Yumi's own notes: one per line in a plain text file the user can open and edit.
/// A line may start with "[date] ", written for the reader and ignored when loading.
struct NotesStore: Sendable {
    static let maxLength = 280

    let fileURL: URL

    /// Notes in the order they were written; the last one is the most recent.
    func load() -> [String] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return content.split(whereSeparator: \.isNewline).compactMap { line in
            let text = Self.withoutDate(String(line)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
    }

    /// Adds a note at the end of the file. Returns the text kept, or nil when there was
    /// nothing to keep (empty text, or the same note twice in a row).
    @discardableResult
    func add(_ text: String, now: Date = Date()) -> String? {
        let note = Self.clean(text)
        guard !note.isEmpty, load().last != note else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let line = "[\(formatter.string(from: now))] \(note)\n"

        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        if !content.isEmpty && !content.hasSuffix("\n") { content += "\n" }
        content += line
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            return note
        } catch {
            return nil
        }
    }

    /// Creates the file if needed, so it can be opened even before the first note.
    func ensureFileExists() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// One line, no surrounding space, capped.
    static func clean(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return oneLine.count > maxLength ? String(oneLine.prefix(maxLength - 1)) + "…" : oneLine
    }

    private static func withoutDate(_ line: String) -> String {
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return line }
        return String(line[line.index(after: end)...])
    }
}

/// A reminder from the Reminders app that is due today or late.
struct ReminderItem: Equatable, Sendable {
    let id: String
    var title: String
    var due: Date?
    /// False when the reminder is due on a day, without a time.
    var hasTime: Bool
}

enum NotesSummary {
    /// Reminders due first, the most overdue on top; reminders without a date last.
    static func ordered(_ reminders: [ReminderItem]) -> [ReminderItem] {
        reminders.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x != y ? x < y : a.title < b.title
            case (_?, nil):    return true
            case (nil, _?):    return false
            case (nil, nil):   return a.title < b.title
            }
        }
    }

    static func snapshot(notes: [String], reminders: [ReminderItem], remindersAccess: PermissionState,
                         now: Date, calendar: Calendar = .current) -> ModuleSnapshot {
        plainSnapshot(notes: notes, reminders: reminders, remindersAccess: remindersAccess, now: now, calendar: calendar).withSymbols("note.text")
    }

    private static func plainSnapshot(notes: [String], reminders: [ReminderItem], remindersAccess: PermissionState,
                                      now: Date, calendar: Calendar) -> ModuleSnapshot {
        let due = ordered(reminders)
        let total = notes.count + due.count
        var snapshot = ModuleSnapshot(id: "notes", name: "Notes", colorHex: "#F2C744",
                                      status: total == 0 ? loc("vide") : "\(total)",
                                      title: loc("Rien à garder pour l'instant."),
                                      subtitle: loc("Copie un texte, je le garde en note."),
                                      primaryAction: loc("Nouvelle note"),
                                      secondaryAction: remindersAccess == .notDetermined ? loc("Activer les rappels") : loc("Tout voir"))

        if let reminder = due.first {
            snapshot.title = loc("Rappel : \(reminder.title)")
            snapshot.subtitle = when(reminder, now: now, calendar: calendar)
            if due.count == 2 { snapshot.subtitle += loc(" Un autre attend.") }
            if due.count > 2 { snapshot.subtitle += loc(" \(FrenchText.sentenceStart(FrenchText.spelled(due.count - 1))) autres attendent.") }
            snapshot.primaryAction = loc("Terminé")
            snapshot.secondaryAction = loc("Tout voir")
            snapshot.needsAttention = isLate(reminder, now: now, calendar: calendar)
            // A late reminder is the one thing worth the folded island: it can be ticked off from there.
            if snapshot.needsAttention {
                snapshot.live = ModuleLive(text: loc("Rappel : \(reminder.title)"), priority: ModuleLivePriority.ambient,
                                           controls: [ModuleControl(id: ModuleAction.primary.rawValue, symbol: "checkmark", label: loc("Terminé"))])
            }
        } else if let note = notes.last {
            snapshot.title = loc("Ta dernière note")
            snapshot.subtitle = note
        }
        return snapshot
    }

    private static func isLate(_ reminder: ReminderItem, now: Date, calendar: Calendar) -> Bool {
        guard let due = reminder.due else { return false }
        return reminder.hasTime ? due <= now : due < calendar.startOfDay(for: now)
    }

    private static func when(_ reminder: ReminderItem, now: Date, calendar: Calendar) -> String {
        guard let due = reminder.due else { return loc("Sans date.") }
        if due < calendar.startOfDay(for: now) { return loc("C'était prévu avant aujourd'hui.") }
        guard reminder.hasTime else { return loc("C'est pour aujourd'hui.") }
        return due <= now ? loc("C'était pour \(FrenchText.clock(due, calendar: calendar)).")
                          : loc("C'est pour \(FrenchText.clock(due, calendar: calendar)).")
    }
}
