import Foundation
import Observation
import SwiftUI

/// Yumi on the iPhone: one character for every screen, so he greets once per launch and keeps
/// his mood from one tab to the other. He says something useful about the day, reacts to a tap
/// and to the finger, thinks while he answers, and has the habits of the hour.
@MainActor
@Observable
final class PhoneCharacter {
    /// What he says under himself, drawn from the day. Changes with a tap.
    private(set) var remark: String = ""
    /// Seen by the screens: a bubble pops each time it changes.
    private(set) var remarkID = 0

    /// False while the opening draws him: the screens hold him still, so that one engine is never
    /// run by two pictures at once.
    var onScreen = false
    /// Where the home screen draws him, in screen points: the opening lands him exactly there.
    @ObservationIgnored var homeFrame: CGRect?
    @ObservationIgnored let engine = BotEngine()
    @ObservationIgnored private var greeted = false
    @ObservationIgnored private var remarks: [String] = []
    @ObservationIgnored private var next = 0
    @ObservationIgnored private var habitTask: Task<Void, Never>?
    @ObservationIgnored private var taps: [Date] = []

    /// The launch sequence already greeted: the first screen only sets him up.
    func greetedAtLaunch() {
        guard !greeted else { return }
        greeted = true
        engine.setLook(accent: .current(), costume: .current())
        engine.setState(Self.isNight() ? .sleeping : .idle, force: true)
        habitLater()
    }

    /// The first screen shown at launch: hello, with his sound, once.
    func appear() {
        guard !greeted else { return }
        greeted = true
        engine.setLook(accent: .current(), costume: .current())
        if Self.isNight() {
            engine.setState(.sleeping, force: true)
            return
        }
        engine.setState(.idle, force: true)
        engine.greet()
        habitLater()
    }

    /// A tap: the next thing he has to say, with a little jump. Three quick taps and he is dizzy
    /// (the engine counts them).
    func tapped() {
        if engine.state == .sleeping {
            engine.setState(.idle)
            engine.play(.stretch)
            say(loc("Hmm… je suis là."))
            return
        }
        engine.setHabit(nil)
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 1.7 } + [now]
        if taps.count >= 3 {
            // Teased: his bounce, then dizzy for a moment
            taps = []
            engine.slap()
            SoundEngine.shared.play("dizzy")
            dizzy()
        } else {
            engine.play([.pop, .jump, .wave].randomElement() ?? .pop)
            engine.triggerEmote([.happy, .wink, .love].randomElement() ?? .happy)
            SoundEngine.shared.play("blip")
        }
        if !remarks.isEmpty {
            next = (next + 1) % remarks.count
            say(remarks[next])
        }
    }

    /// The finger on him or near him: he looks at it. `point` from -1 to 1 on each axis.
    func look(at point: CGPoint?) { engine.setGaze(point) }

    func thinking(_ on: Bool) {
        engine.setHabit(nil)
        engine.setState(on ? .thinking : .idle)
    }

    /// The end of an answer or an action.
    func finished(success: Bool) {
        engine.setState(.idle)
        if success {
            engine.play(.celebrate)
            engine.setMood(.happy)
        } else {
            engine.play(.shake)
            engine.setMood(.worried)
        }
        Task { [engine] in
            try? await Task.sleep(for: .seconds(3))
            engine.setMood(nil)
        }
    }

    func asking(_ on: Bool) { engine.setState(on ? .approval : .idle) }

    /// The three taps of `slap`: dizzy for a moment, then himself again.
    func dizzy() {
        engine.setState(.dizzy)
        Task { [engine] in
            try? await Task.sleep(for: .seconds(2.4))
            engine.setState(.idle)
        }
    }

    /// What he can say today, from what the person allowed him to read.
    func update(from today: PhoneToday, name: String?, mac: LinkSnapshot?) {
        var lines: [String] = []
        let now = Date()
        if let event = today.events.first(where: { $0.start > now && !$0.isAllDay }) {
            let minutes = Int(event.start.timeIntervalSince(now) / 60)
            if minutes < 60 {
                lines.append(loc("« \(event.title) » dans \(minutes) min."))
            } else {
                lines.append(loc("Prochain : « \(event.title) » à \(event.start.formatted(date: .omitted, time: .shortened))."))
            }
        } else if today.calendarAccess == .granted {
            lines.append(loc("Rien d'autre à l'agenda aujourd'hui. Profite."))
        }
        if case .ready(let report) = today.weather {
            lines.append(WeatherSummary.advice(report, now: now))
        }
        if let first = today.reminders.first {
            lines.append(today.reminders.count == 1 ? loc("N'oublie pas : \(first.title).")
                                                    : loc("\(today.reminders.count) rappels t'attendent, dont « \(first.title) »."))
        }
        if let waiting = mac?.approvals.first {
            lines.insert(loc("Ton Mac attend ton accord : \(waiting.summary)."), at: 0)
        }
        if lines.isEmpty {
            lines.append(name.map { loc("Je suis là, \($0). Parle-moi quand tu veux.") } ?? loc("Je suis là. Parle-moi quand tu veux."))
        }
        let changed = lines != remarks
        remarks = lines
        if changed {
            next = 0
            say(lines[0])
        }
    }

    private func say(_ text: String) {
        remark = text
        remarkID += 1
    }

    /// After a while on screen, a habit of the hour for a few seconds: coffee in the morning,
    /// water at noon, tea in the evening, a book late. Then back to himself.
    private func habitLater() {
        habitTask?.cancel()
        habitTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 25...45)))
                guard let self, !Task.isCancelled, self.engine.state == .idle else { continue }
                self.engine.setHabit(Self.habitOfTheHour())
                try? await Task.sleep(for: .seconds(9))
                self.engine.setHabit(nil)
            }
        }
    }

    private static func habitOfTheHour(_ date: Date = Date()) -> YumiHabit {
        switch Calendar.current.component(.hour, from: date) {
        case 6..<11: .coffee
        case 11..<14: .water
        case 14..<17: [.headphones, .matcha, .juice].randomElement() ?? .juice
        case 17..<21: .tea
        default: .book
        }
    }

    private static func isNight(_ date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 23 || hour < 6
    }
}
