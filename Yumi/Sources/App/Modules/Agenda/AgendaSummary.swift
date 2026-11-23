import Foundation

/// One calendar event, reduced to what the island shows.
struct AgendaEvent: Equatable, Sendable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String
    /// Link to join the meeting, when the event carries one.
    var joinURL: URL?
}

enum AgendaSummary {
    /// An event starting within this delay asks for attention.
    private static let soon: TimeInterval = 5 * 60

    /// Hosts of the video meeting services recognised in an event.
    private static let meetingHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com",
                                       "webex.com", "whereby.com", "facetime.apple.com", "meet.jit.si", "gotomeet.me"]

    /// The first video meeting link found in the texts of an event (URL field, location, notes).
    static func joinURL(in texts: [String?]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector.matches(in: text, range: range) {
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                if meetingHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) { return url }
            }
        }
        return nil
    }

    /// The event to show: the one in progress, otherwise the next one. All-day events are left out.
    static func featured(_ events: [AgendaEvent], now: Date) -> AgendaEvent? {
        let timed = events.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        // An event about to start matters more than one that is ending.
        if let next = timed.first(where: { $0.start > now }), next.start.timeIntervalSince(now) <= soon { return next }
        return timed.first
    }

    /// The day's appointments as `rows` (past ones `.neutral` with a date before now, the next one
    /// `.waiting`), and the next four days in `pages["week"]`, one line per day.
    static func withDays(_ snapshot: ModuleSnapshot, events: [AgendaEvent], now: Date,
                         calendar: Calendar = .current) -> ModuleSnapshot {
        var out = snapshot
        let timed = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let today = timed.filter { calendar.isDate($0.start, inSameDayAs: now) }
        let next = today.first { $0.end > now }
        out.rows = today.map { event in
            ModuleRow(id: event.id, title: event.title, detail: FrenchText.clock(event.start, calendar: calendar),
                      state: event.id == next?.id ? .waiting : (event.end <= now ? .success : .neutral),
                      label: event.id == next?.id && event.start > now
                          ? loc("dans \(FrenchText.spokenMinutes(event.start.timeIntervalSince(now)))") : "",
                      date: event.start)
        }
        var week: [ModuleRow] = []
        let start = calendar.startOfDay(for: now)
        for offset in 1...4 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let those = timed.filter { calendar.isDate($0.start, inSameDayAs: day) }
            let label = day.formatted(.dateTime.weekday(.abbreviated).day()).capitalized
            let first = those.first.map { "\($0.title) · \(FrenchText.clock($0.start, calendar: calendar))" }
            week.append(ModuleRow(id: "day-\(offset)", title: label, detail: first ?? loc("Rien de prévu"),
                                  state: .neutral, label: those.isEmpty ? "" : loc("\(those.count) évén."), date: day))
        }
        out.pages["week"] = week
        return out
    }

    static func snapshot(events: [AgendaEvent], access: PermissionState, now: Date,
                         calendar: Calendar = .current) -> ModuleSnapshot {
        plainSnapshot(events: events, access: access, now: now, calendar: calendar).withSymbols("calendar")
    }

    private static func plainSnapshot(events: [AgendaEvent], access: PermissionState, now: Date,
                                      calendar: Calendar) -> ModuleSnapshot {
        var snapshot = ModuleSnapshot(id: "agenda", name: loc("Agenda"), colorHex: "#5B8CFF", status: loc("libre"),
                                      title: loc("Rien de prévu."), subtitle: loc("Ta journée est à toi."),
                                      primaryAction: loc("Voir la journée"), secondaryAction: nil)
        switch access {
        case .notDetermined:
            snapshot.status = loc("à brancher")
            snapshot.title = loc("Je ne vois pas ton agenda.")
            snapshot.subtitle = loc("Tu me l'ouvres ?")
            snapshot.primaryAction = loc("Autoriser")
            return snapshot
        case .denied:
            snapshot.status = loc("bloqué")
            snapshot.title = loc("Ton agenda m'est fermé.")
            snapshot.subtitle = loc("Ça se rouvre dans Réglages Système.")
            snapshot.primaryAction = loc("Ouvrir les réglages")
            return snapshot
        case .granted:
            break
        }

        guard let event = featured(events, now: now) else { return snapshot }

        let startsToday = calendar.isDate(event.start, inSameDayAs: now)
        let clock = FrenchText.clock(event.start, calendar: calendar)
        if event.start <= now {
            snapshot.status = loc("en cours")
            snapshot.title = loc("\(event.title) a commencé.")
        } else if !startsToday {
            snapshot.title = loc("Demain, \(event.title).")
            snapshot.subtitle = loc("Plus rien aujourd'hui")
        } else if event.start.timeIntervalSince(now) < 3600 {
            snapshot.status = clock
            snapshot.title = loc("\(event.title) dans \(FrenchText.spokenMinutes(event.start.timeIntervalSince(now))).")
        } else {
            snapshot.status = clock
            snapshot.title = loc("\(event.title) à \(clock).")
        }

        var details = [loc("\(clock) à \(FrenchText.clock(event.end, calendar: calendar))")]
        if event.joinURL != nil { details.append(loc("en visio")) }
        if !event.location.isEmpty && joinURL(in: [event.location]) == nil {
            details.append(event.location.split(whereSeparator: \.isNewline).first.map(String.init) ?? event.location)
        }
        if startsToday || event.start <= now {
            snapshot.subtitle = FrenchText.sentenceStart(details.joined(separator: ", ")) + "."
        } else {
            snapshot.subtitle += loc(", demain ") + details.joined(separator: ", ") + "."
        }

        // The folded island announces today's events only: tomorrow is not happening now.
        // The button joins the featured event, so it is only offered when that is the one announced.
        if startsToday || event.start <= now {
            let upcoming = events.filter { !$0.isAllDay && $0.start > now && calendar.isDate($0.start, inSameDayAs: now) }
                .min { $0.start < $1.start }
            let announced = upcoming ?? event
            let join = ModuleControl(id: ModuleAction.primary.rawValue, symbol: "video.fill", label: loc("Rejoindre"))
            let text = announced.start <= now ? loc("\(announced.title), en cours")
                                              : "\(FrenchText.clock(announced.start, calendar: calendar)) \(announced.title)"
            snapshot.live = ModuleLive(text: text, priority: ModuleLivePriority.ambient,
                                       controls: announced == event && event.joinURL != nil ? [join] : [])
        }

        snapshot.primaryAction = event.joinURL != nil ? loc("Rejoindre") : loc("Ouvrir")
        snapshot.secondaryAction = loc("Voir la journée")
        let delay = event.start.timeIntervalSince(now)
        snapshot.needsAttention = delay <= soon && delay > -120
        return snapshot
    }
}
