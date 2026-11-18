import Foundation

/// Turns what happens on the Mac into occasions to speak. Pure: every method is given the time.
/// It only remembers what it needs to recognise an occasion once: the day already greeted, since
/// when the person works, which agent started when.
struct InitiativeWatch: Codable, Equatable, Sendable {
    /// Away this long, the person is "back".
    static let longAbsence: TimeInterval = 30 * 60
    /// A stretch of work worth a remark, and every such stretch after it.
    static let stretch: TimeInterval = 2 * 3600
    /// An agent's task this long is worth a word when it ends.
    static let longTask: TimeInterval = 10 * 60
    /// An appointment this close while an agent waits.
    static let meetingLead: TimeInterval = 10 * 60
    static let lowBattery = 15
    /// "Late" starts at 23:30 and lasts until 4:00.
    static let lateStart = (hour: 23, minute: 30)
    static let lateEndHour = 4
    /// The week ends on Friday at 18:00.
    static let weekEndHour = 18

    private var greetedDay: String?
    private var awaySince: Date?
    private var workingSince: Date?
    private var stretchesSaid = 0
    private var promptAt: [String: Date] = [:]
    private var finishedWhileAway = false
    private var lateDay: String?
    private var weekEnd: String?
    private var batteryWarned = false
    private var meetingsSaid: [String] = []
    /// Sessions waiting for the person right now.
    private(set) var waiting: Set<String> = []
    /// How Yumi names the agent of the latest session event ("Codex"). nil before any.
    private(set) var agentSpeaker: String?

    init() {}

    var agentWaiting: Bool { !waiting.isEmpty }

    // MARK: Presence

    /// The Mac woke, was unlocked, or Yumi started.
    mutating func arrived(now: Date, calendar: Calendar, eventsToday: Int?, firstEventAt: Date?) -> Occasion? {
        let day = Self.day(now, calendar)
        let absence = awaySince.map { now.timeIntervalSince($0) } ?? 0
        let finished = finishedWhileAway
        awaySince = nil
        finishedWhileAway = false
        if workingSince == nil || absence >= 5 * 60 {
            // A real break: the stretch of work starts again.
            workingSince = now
            stretchesSaid = 0
        }
        if greetedDay != day {
            greetedDay = day
            return .firstWake(events: eventsToday, firstAt: firstEventAt)
        }
        guard absence >= Self.longAbsence else { return nil }
        return .back(agentFinished: finished, agentWaiting: agentWaiting)
    }

    /// The Mac goes to sleep or is locked.
    mutating func left(now: Date) {
        if awaySince == nil { awaySince = now }
    }

    /// The person is back after five minutes or more without touching the Mac, the session left
    /// open: that was a break too, the stretch of work starts again.
    mutating func rested(now: Date) {
        guard awaySince == nil, workingSince != nil else { return }
        workingSince = now
        stretchesSaid = 0
    }

    /// The person took the break Yumi offered.
    mutating func tookBreak(now: Date) {
        workingSince = now
        stretchesSaid = 0
    }

    // MARK: Agents

    /// A session event went through the engine. `sessions` is the state after it.
    mutating func session(_ event: YumiEvent, sessions: [SessionID: Session], now: Date) -> Occasion? {
        waiting = Set(sessions.values.filter { $0.status == .waitingForUser }.map(\.id.value))
        if let id = event.sessionID, let session = sessions[id] { agentSpeaker = AgentCatalog.speaker(of: session.agent) }
        switch event {
        case .promptSubmitted(let id, _):
            promptAt[id.value] = now
        case .sessionEnded(let id), .sessionErrored(let id, _):
            promptAt[id.value] = nil
        case .taskCompleted(let id):
            guard let started = promptAt.removeValue(forKey: id.value) else { break }
            if awaySince != nil {
                finishedWhileAway = true
                break
            }
            let duration = now.timeIntervalSince(started)
            guard duration >= Self.longTask, let session = sessions[id] else { break }
            return .agentDone(project: ClaudeSessions.projectName(session), minutes: Int((duration / 60).rounded()))
        default:
            break
        }
        return nil
    }

    /// Sets when a session's prompt was sent (used to replay a task of a known length).
    mutating func backdatePrompt(id: String, to date: Date) {
        promptAt[id] = date
    }

    // MARK: Appointment

    /// An appointment is close while an agent waits. Said once per appointment.
    mutating func meeting(title: String, start: Date, now: Date) -> Occasion? {
        let lead = start.timeIntervalSince(now)
        let key = "\(title)@\(Int(start.timeIntervalSince1970))"
        guard agentWaiting, awaySince == nil, lead > 0, lead <= Self.meetingLead, !meetingsSaid.contains(key) else { return nil }
        meetingsSaid = Array((meetingsSaid + [key]).suffix(10))
        return .meetingWhileAgentWaits(title: title, minutes: max(1, Int((lead / 60).rounded(.up))))
    }

    // MARK: Battery

    mutating func battery(percent: Int, charging: Bool) -> Occasion? {
        if charging || percent > Self.lowBattery + 5 {
            batteryWarned = false
            return nil
        }
        guard percent <= Self.lowBattery, !batteryWarned, awaySince == nil else { return nil }
        batteryWarned = true
        return .lowBattery(percent: percent)
    }

    // MARK: Clock

    /// What the time alone brings: a long stretch of work, a late hour, the end of the week.
    /// Each is given once; call it when `nextDeadline` is reached.
    mutating func clock(now: Date, calendar: Calendar) -> [Occasion] {
        guard awaySince == nil else { return [] }
        var occasions: [Occasion] = []
        if let since = workingSince {
            let stretches = Int(now.timeIntervalSince(since) / Self.stretch)
            if stretches > stretchesSaid {
                stretchesSaid = stretches
                occasions.append(.longStretch(hours: stretches * Int(Self.stretch / 3600)))
            }
        }
        let parts = calendar.dateComponents([.hour, .minute, .weekday, .yearForWeekOfYear, .weekOfYear], from: now)
        let hour = parts.hour ?? 12, minute = parts.minute ?? 0
        let isLate = hour < Self.lateEndHour || hour > Self.lateStart.hour || (hour == Self.lateStart.hour && minute >= Self.lateStart.minute)
        // A night belongs to the day it started: one remark for 23:30 to 4:00.
        let night = Self.day(now.addingTimeInterval(-Double(Self.lateEndHour) * 3600), calendar)
        if isLate, lateDay != night {
            lateDay = night
            occasions.append(.late)
        }
        let week = "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
        if parts.weekday == 6, hour >= Self.weekEndHour, !isLate, weekEnd != week {
            weekEnd = week
            occasions.append(.weekEnd)
        }
        return occasions
    }

    /// When the clock next has something to say, so the caller sleeps until then and not a second less.
    func nextDeadline(now: Date, calendar: Calendar, nextEventStart: Date?) -> Date? {
        guard awaySince == nil else { return nil }
        var candidates: [Date] = []
        if let since = workingSince {
            candidates.append(since.addingTimeInterval(Double(stretchesSaid + 1) * Self.stretch))
        }
        if let late = calendar.nextDate(after: now, matching: DateComponents(hour: Self.lateStart.hour, minute: Self.lateStart.minute),
                                        matchingPolicy: .nextTime) {
            candidates.append(late)
        }
        if let friday = calendar.nextDate(after: now, matching: DateComponents(hour: Self.weekEndHour, weekday: 6), matchingPolicy: .nextTime) {
            candidates.append(friday)
        }
        if agentWaiting, let start = nextEventStart {
            candidates.append(start.addingTimeInterval(-Self.meetingLead))
        }
        return candidates.filter { $0 > now }.min()
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
