import Foundation

/// The limits of Yumi's Live Activity on the iPhone. Without a server of ours the activity cannot
/// change on its own, so every counter it shows must stop by itself and the activity must not
/// outlive what it tells.
enum IslandClock {
    /// A picture of the Mac older than this says nothing about now (the Mac asleep, closed, gone).
    static let macFreshness: TimeInterval = 15 * 60
    /// The working counter never goes past this: an agent at work longer is shown without a count.
    static let maxWorking: TimeInterval = 2 * 60 * 60
    /// The activity never lives longer than this; the app starts a new one when it runs again.
    static let maxLife: TimeInterval = 4 * 60 * 60

    /// Since when an agent of the Mac works, if the picture is recent and the work too.
    static func workingSince(sessionUpdatedAt: Date, snapshotSentAt: Date, now: Date) -> Date? {
        guard now.timeIntervalSince(snapshotSentAt) < macFreshness,
              sessionUpdatedAt <= now,
              now.timeIntervalSince(sessionUpdatedAt) < maxWorking else { return nil }
        return sessionUpdatedAt
    }

    /// The range the working counter runs over: it stops at `maxWorking`.
    static func workingRange(since: Date) -> ClosedRange<Date> {
        since...since.addingTimeInterval(maxWorking)
    }

    /// When iOS should dim the activity: the earliest of the thing starting, the counter
    /// stopping and the snapshot growing old.
    static func staleDate(at: Date?, working: Date?, now: Date) -> Date {
        var dates = [now.addingTimeInterval(macFreshness * 4)]
        if let at { dates.append(at.addingTimeInterval(60)) }
        if let working { dates.append(working.addingTimeInterval(maxWorking)) }
        return dates.min()!
    }

    /// True when an activity started then has lived long enough and should be ended.
    static func isTooOld(startedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= maxLife
    }

    /// A meeting this close comes first: Yumi thinks of it and the countdown takes the front.
    static let soon: TimeInterval = 15 * 60
    /// A new mail stays in the island this long.
    static let mailShown: TimeInterval = 30 * 60
    /// A finished agent stays in the island this long, then the day comes back.
    static let doneShown: TimeInterval = 5 * 60

    static func isSoon(_ start: Date, now: Date) -> Bool {
        start > now && start.timeIntervalSince(now) <= soon
    }

    static func isFreshMail(_ date: Date?, now: Date) -> Bool {
        guard let date else { return false }
        return date <= now.addingTimeInterval(60) && now.timeIntervalSince(date) < mailShown
    }

    static func isJustDone(_ finishedAt: Date, now: Date) -> Bool {
        finishedAt <= now && now.timeIntervalSince(finishedAt) < doneShown
    }

    /// « 18 min », « 1 h 05 »: how long an agent worked.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        return minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    /// The first hour of rain worth a word (one chance in two or more) on `day`, between 7 h and
    /// 22 h, from the hours of the forecast.
    static func firstRain(on day: Date, hours: [(time: Date, chance: Int)], calendar: Calendar = .current) -> Date? {
        hours.first { hour in
            calendar.isDate(hour.time, inSameDayAs: day) && hour.chance >= 50
                && (7..<22).contains(calendar.component(.hour, from: hour.time))
        }?.time
    }
}
