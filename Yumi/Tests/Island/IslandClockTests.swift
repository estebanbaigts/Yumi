import Foundation
import Testing

@Suite struct IslandClockTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func staleMacPictureShowsNoWork() {
        #expect(IslandClock.workingSince(sessionUpdatedAt: now.addingTimeInterval(-60),
                                         snapshotSentAt: now.addingTimeInterval(-3600), now: now) == nil)
    }

    @Test func workForgottenSinceYesterdayShowsNoCounter() {
        #expect(IslandClock.workingSince(sessionUpdatedAt: now.addingTimeInterval(-50 * 3600),
                                         snapshotSentAt: now, now: now) == nil)
    }

    @Test func recentWorkCounts() {
        let since = now.addingTimeInterval(-300)
        #expect(IslandClock.workingSince(sessionUpdatedAt: since, snapshotSentAt: now, now: now) == since)
    }

    @Test func counterStopsAtTheMaximum() {
        #expect(IslandClock.workingRange(since: now).upperBound == now.addingTimeInterval(IslandClock.maxWorking))
    }

    @Test func alwaysAStaleDate() {
        #expect(IslandClock.staleDate(at: nil, working: nil, now: now) > now)
        #expect(IslandClock.staleDate(at: now.addingTimeInterval(120), working: nil, now: now) == now.addingTimeInterval(180))
    }

    @Test func activityTooOldIsReplaced() {
        #expect(IslandClock.isTooOld(startedAt: now.addingTimeInterval(-IslandClock.maxLife), now: now))
        #expect(!IslandClock.isTooOld(startedAt: now.addingTimeInterval(-60), now: now))
        #expect(IslandClock.isTooOld(startedAt: .distantPast, now: now))
    }

    @Test func meetingSoonOnlyWithinFifteenMinutes() {
        #expect(IslandClock.isSoon(now.addingTimeInterval(600), now: now))
        #expect(!IslandClock.isSoon(now.addingTimeInterval(3600), now: now))
        #expect(!IslandClock.isSoon(now.addingTimeInterval(-60), now: now))
    }

    @Test func mailAndDoneLeaveTheIsland() {
        #expect(IslandClock.isFreshMail(now.addingTimeInterval(-300), now: now))
        #expect(!IslandClock.isFreshMail(now.addingTimeInterval(-3600), now: now))
        #expect(!IslandClock.isFreshMail(nil, now: now))
        #expect(IslandClock.isJustDone(now.addingTimeInterval(-60), now: now))
        #expect(!IslandClock.isJustDone(now.addingTimeInterval(-600), now: now))
    }

    @Test func durationReads() {
        #expect(IslandClock.duration(18 * 60) == "18 min")
        #expect(IslandClock.duration(65 * 60) == "1 h 05")
    }

    @Test func firstRainOfTheDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 0))!
        let at = { (h: Int) in calendar.date(byAdding: .hour, value: h, to: day)! }
        let hours = [(at(5), 90), (at(9), 30), (at(18), 70), (at(20), 80)]
        #expect(IslandClock.firstRain(on: day, hours: hours, calendar: calendar) == at(18))
        #expect(IslandClock.firstRain(on: day, hours: [(at(9), 20)], calendar: calendar) == nil)
    }
}
