import Foundation

// MARK: - When Yumi speaks first
// See « Quand il parle le premier » in design/voix.md and Contracts/RemarkTypes.swift.
// The engine is pure: an occasion and what surrounds it come in, a remark comes out, or nothing.
// When in doubt he stays quiet. `InitiativeDriver` watches the Mac and feeds the engine.

/// One of the eight moments Yumi may speak first.
enum Occasion: Equatable, Sendable {
    /// First time the Mac wakes today. `events` is the number of appointments left today,
    /// or nil when Yumi cannot see the calendar.
    case firstWake(events: Int?, firstAt: Date?)
    /// The person is back after a long absence.
    case back(agentFinished: Bool, agentWaiting: Bool)
    /// Two hours of work or more without a break.
    case longStretch(hours: Int)
    /// An agent finished a task that took a while.
    case agentDone(project: String, minutes: Int)
    /// An appointment is close while an agent waits for an answer.
    case meetingWhileAgentWaits(title: String, minutes: Int)
    case late
    case lowBattery(percent: Int)
    case weekEnd
    /// Something that counts happened on one of the person's repositories.
    case repository(GitHubEvent, count: Int)
    /// New mail arrived in the Gmail inbox: the newest one, and how many came.
    case mail(from: String, subject: String, count: Int)
    /// Today's screen time reached the daily threshold, or one more hour above it (minutes).
    case screenTime(minutes: Int, threshold: Int)

    /// The subject, for the rule about being ignored: one per kind of occasion.
    var topic: String {
        switch self {
        case .firstWake: return "firstWake"
        case .back: return "back"
        case .longStretch: return "longStretch"
        case .agentDone: return "agentDone"
        case .meetingWhileAgentWaits: return "meeting"
        case .late: return "late"
        case .lowBattery: return "lowBattery"
        case .weekEnd: return "weekEnd"
        case .repository(let event, _): return "github.\(event.kind.rawValue)"
        case .mail: return "mail"
        case .screenTime: return "screenTime"
        }
    }

    /// True when it matters enough for the discreet setting. Greetings and encouragements do not.
    var matters: Bool {
        switch self {
        case .firstWake(let events, _): return (events ?? 0) > 0
        case .back(let finished, let waiting): return finished || waiting
        case .weekEnd: return false
        case .longStretch, .agentDone, .meetingWhileAgentWaits, .late, .lowBattery, .repository, .mail, .screenTime: return true
        }
    }

    /// News the person asked to hear as it comes (what happens on their repositories): the
    /// twenty-minute rule and the daily count do not apply, and it does not delay the others.
    var isNews: Bool {
        switch self {
        case .repository, .mail: return true
        default: return false
        }
    }

    /// True when someone is waiting for an answer: the twenty-minute rule does not apply.
    var someoneWaits: Bool {
        switch self {
        case .meetingWhileAgentWaits: return true
        case .back(_, let waiting): return waiting
        default: return false
        }
    }
}

/// What the person can do about a remark.
enum RemarkAction: String, Codable, Sendable {
    /// Start a five-minute break.
    case takeBreak
    /// Bring forward the application the agent's session runs in.
    case openSession

    var label: String { self == .takeBreak ? loc("Pause") : loc("Voir") }
}

/// Everything around the moment, given by the caller so that nothing here reads a clock or the Mac.
struct Surroundings: Sendable {
    var now: Date
    var calendar: Calendar = .current
    var talk: YumiTalk = .discreet
    var name: String? = nil
    /// Names or sentences about the person's projects, and the latest of the thread, from the memory.
    var projects: [String] = []
    var thread: [String] = []
    // The moments he never interrupts.
    var focusRunning = false
    var screenShared = false
    var presenting = false
    var doNotDisturb = false
    /// How Yumi names the coding agent of the latest session: "Claude", "Codex", "Gemini".
    var agent = "Claude"
}

struct InitiativeEngine: Codable, Equatable, Sendable {
    /// At least this long between two remarks, unless someone is waiting for an answer.
    static let quietTime: TimeInterval = 20 * 60
    /// Ignored this many times in a row on a subject, he drops it for a while.
    static let ignoresBeforeSilence = 3
    static let silenceAfterIgnores: TimeInterval = 3 * 24 * 3600
    /// "A few times a day at most" when discreet; more when chatty.
    static let dailyLimit: [YumiTalk: Int] = [.silent: 0, .discreet: 4, .chatty: 10]

    private struct Said: Codable, Equatable, Sendable { var day: String; var phrase: String }
    private struct Pending: Codable, Equatable, Sendable { var id: String; var topic: String; var action: RemarkAction? }

    private var lastRemarkAt: Date?
    private var said: [Said] = []
    private var ignoredInARow: [String: Int] = [:]
    private var silentUntil: [String: Date] = [:]
    private var pending: Pending?

    init() {}

    // MARK: Speaking

    /// The remark for this occasion, or nil when Yumi should stay quiet. Saying it is recorded.
    mutating func consider(_ occasion: Occasion, in around: Surroundings) -> YumiRemark? {
        guard refusal(of: occasion, in: around) == nil else { return nil }
        let day = Self.day(around.now, around.calendar)
        let yesterday = Self.day(around.now.addingTimeInterval(-24 * 3600), around.calendar)
        let saidYesterday = Set(said.filter { $0.day == yesterday }.map(\.phrase))
        let saidToday = said.filter { $0.day == day }.map(\.phrase)
        // Never the same sentence two days in a row. Within a day he also varies as long as he can;
        // once every wording has been used today, the one used longest ago comes back.
        let variants = InitiativePhrases.variants(for: occasion, around).filter { !saidYesterday.contains($0.key) }
        guard let chosen = variants.first(where: { !saidToday.contains($0.key) })
                ?? variants.min(by: { (saidToday.lastIndex(of: $0.key) ?? -1) < (saidToday.lastIndex(of: $1.key) ?? -1) }) else { return nil }

        let remark = YumiRemark(id: UUID().uuidString, text: chosen.text, mood: chosen.mood,
                                action: chosen.action?.label, duration: chosen.text.count > 60 ? 10 : 8)
        if !occasion.isNews { lastRemarkAt = around.now }
        said.append(Said(day: day, phrase: chosen.key))
        said.removeAll { $0.day != day && $0.day != yesterday }
        pending = Pending(id: remark.id, topic: occasion.topic, action: chosen.action)
        return remark
    }

    /// Why Yumi stays quiet on this occasion, or nil when he may speak.
    func refusal(of occasion: Occasion, in around: Surroundings) -> Refusal? {
        if around.talk == .silent { return .silent }
        if around.focusRunning { return .focus }
        if around.screenShared { return .screenShared }
        if around.presenting { return .presenting }
        if around.doNotDisturb { return .doNotDisturb }
        if around.talk == .discreet, !occasion.matters { return .smallTalk }
        if let until = silentUntil[occasion.topic], around.now < until { return .ignoredTooOften }
        if !occasion.someoneWaits, !occasion.isNews {
            if let last = lastRemarkAt, around.now.timeIntervalSince(last) < Self.quietTime { return .tooSoon }
            let day = Self.day(around.now, around.calendar)
            // GitHub news (`gh.`) do not use up the remarks of the day
            if said.filter({ $0.day == day && !$0.phrase.hasPrefix("gh.") }).count >= (Self.dailyLimit[around.talk] ?? 0) { return .enoughForToday }
        }
        return nil
    }

    enum Refusal: Equatable, Sendable {
        case silent, focus, screenShared, presenting, doNotDisturb, smallTalk, ignoredTooOften, tooSoon, enoughForToday
    }

    // MARK: What the person did with it

    /// The person pressed the action. Returns what to do, once.
    mutating func accepted(id: String) -> RemarkAction? {
        guard let remark = pending, remark.id == id else { return nil }
        pending = nil
        ignoredInARow[remark.topic] = 0
        return remark.action
    }

    /// The remark was closed (`ignored` false) or left to time out (`ignored` true).
    /// Returns true when it was the remark on screen.
    @discardableResult
    mutating func dismissed(id: String, ignored: Bool, now: Date) -> Bool {
        guard let remark = pending, remark.id == id else { return false }
        pending = nil
        guard ignored else {
            ignoredInARow[remark.topic] = 0
            return true
        }
        let count = (ignoredInARow[remark.topic] ?? 0) + 1
        if count >= Self.ignoresBeforeSilence {
            ignoredInARow[remark.topic] = 0
            silentUntil[remark.topic] = now.addingTimeInterval(Self.silenceAfterIgnores)
        } else {
            ignoredInARow[remark.topic] = count
        }
        return true
    }

    /// The identifier of the remark waiting for an answer, if any.
    var pendingID: String? { pending?.id }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

// MARK: - What he says

/// The sentences, written ahead in Yumi's voice. Several per occasion, so he does not repeat himself.
enum InitiativePhrases {
    struct Variant: Equatable, Sendable {
        /// Identifies the wording whatever the numbers and names in it.
        var key: String
        var text: String
        var mood: YumiMood = .neutral
        var action: RemarkAction? = nil
    }

    static func variants(for occasion: Occasion, _ around: Surroundings) -> [Variant] {
        let hello = around.name.map { loc("Salut \($0).") } ?? loc("Salut.")
        let comma = around.name.map { ", \($0)" } ?? ""
        let project = around.projects.first.flatMap(projectName)
        func n(_ value: Int, feminine: Bool = false) -> String { FrenchText.spelled(value, feminine: feminine) }
        func cap(_ text: String) -> String { FrenchText.sentenceStart(text) }

        switch occasion {
        case .firstWake(let events, let firstAt):
            if let events, events > 0 {
                let count = FrenchText.spelledCount(events, loc("rendez-vous"), loc("rendez-vous (pluriel)"))
                let first = firstAt.map { FrenchText.spokenHour($0, calendar: around.calendar) }
                let when = first.map { events == 1 ? loc(", à \($0)") : loc(", le premier à \($0)") } ?? ""
                return [
                    Variant(key: "wake.events.1", text: loc("\(hello) \(cap(count)) aujourd'hui\(when)."), mood: .happy),
                    Variant(key: "wake.events.2", text: loc("Bonjour\(comma). J'ai regardé ta journée : \(count)\(when)."), mood: .happy),
                    Variant(key: "wake.events.3", text: loc("Te voilà\(comma). \(cap(count)) au programme\(when)."), mood: .curious),
                ]
            }
            // Without a view on the calendar he does not claim the day is free.
            var quiet = events == nil ? [
                Variant(key: "wake.plain.1", text: loc("\(hello) J'ai bien dormi. Toi aussi, j'espère."), mood: .wink),
                Variant(key: "wake.plain.2", text: loc("Bonjour\(comma). Je suis réveillé, tu peux y aller."), mood: .happy),
                Variant(key: "wake.plain.3", text: loc("Te voilà\(comma). Je prends mon poste."), mood: .happy),
            ] : [
                Variant(key: "wake.free.1", text: loc("\(hello) Rien de prévu aujourd'hui. Je garde la maison."), mood: .happy),
                Variant(key: "wake.free.2", text: loc("Bonjour\(comma). Journée libre, à ce que je vois."), mood: .happy),
                Variant(key: "wake.free.3", text: loc("\(hello) J'ai bien dormi. Toi aussi, j'espère."), mood: .wink),
            ]
            if let thread = around.thread.last, thread.count <= 90 {
                quiet.insert(Variant(key: "wake.thread", text: loc("\(hello) Je n'ai pas oublié : \(lowered(thread))."), mood: .curious), at: 1)
            }
            return quiet

        case .back(let finished, let waiting):
            if waiting {
                return [
                    Variant(key: "back.waiting.1", text: loc("Te revoilà. \(around.agent) attend ta réponse."), mood: .curious, action: .openSession),
                    Variant(key: "back.waiting.2", text: loc("Ah, te voilà. \(around.agent) a une question pour toi."), mood: .curious, action: .openSession),
                    Variant(key: "back.waiting.3", text: loc("Tu tombes bien. \(around.agent) t'attend depuis un moment."), mood: .curious, action: .openSession),
                ]
            }
            if finished {
                return [
                    Variant(key: "back.finished.1", text: loc("Te revoilà. \(around.agent) a fini pendant que tu étais parti."), mood: .happy, action: .openSession),
                    Variant(key: "back.finished.2", text: loc("Tu as raté la fin : \(around.agent) a terminé sans toi."), mood: .wink, action: .openSession),
                    Variant(key: "back.finished.3", text: loc("Bon retour. C'est passé pendant ton absence."), mood: .happy, action: .openSession),
                ]
            }
            var plain = [
                Variant(key: "back.plain.1", text: loc("Te revoilà. Rien n'a bougé ici."), mood: .happy),
                Variant(key: "back.plain.2", text: loc("Bon retour\(comma). J'ai gardé ta place."), mood: .happy),
                Variant(key: "back.plain.3", text: loc("Ah, te voilà. Je commençais à somnoler."), mood: .wink),
            ]
            if let project {
                plain.insert(Variant(key: "back.project", text: loc("Te revoilà. On reprend \(project) ?"), mood: .curious), at: 1)
            }
            return plain

        case .longStretch(let hours):
            let span = hours <= 1 ? loc("Une heure") : loc("\(cap(n(hours, feminine: true))) heures")
            return [
                Variant(key: "stretch.1", text: loc("\(span) d'affilée. Une pause ?"), mood: .worried, action: .takeBreak),
                Variant(key: "stretch.2", text: loc("Tu n'as pas levé le nez depuis \(n(hours, feminine: true)) \(hours > 1 ? loc("heures") : loc("heure")). Cinq minutes ?"), mood: .worried, action: .takeBreak),
                Variant(key: "stretch.3", text: loc("\(span) sans souffler. Je te garde ta place cinq minutes ?"), mood: .curious, action: .takeBreak),
            ]

        case .screenTime(let minutes, let threshold):
            let total = ScreenTimeSummary.time(minutes)
            if minutes <= threshold {
                return [
                    Variant(key: "screen.limit.1", text: loc("\(total) d'écran aujourd'hui. C'est ton seuil."), mood: .worried, action: .takeBreak),
                    Variant(key: "screen.limit.2", text: loc("Ça fait \(total) devant l'écran. On avait dit que c'était assez pour aujourd'hui."), mood: .worried, action: .takeBreak),
                    Variant(key: "screen.limit.3", text: loc("Seuil atteint : \(total) d'écran. Tes yeux méritent une pause."), mood: .curious, action: .takeBreak),
                ]
            }
            return [
                Variant(key: "screen.over.1", text: loc("\(total) d'écran aujourd'hui. Toujours là ?"), mood: .worried, action: .takeBreak),
                Variant(key: "screen.over.2", text: loc("Encore une heure de plus : \(total) d'écran aujourd'hui."), mood: .worried, action: .takeBreak),
                Variant(key: "screen.over.3", text: loc("\(total) devant l'écran. Je dis ça pour tes yeux."), mood: .curious, action: .takeBreak),
            ]

        case .agentDone(let project, let minutes):
            let time = FrenchText.spokenMinutes(Double(minutes) * 60)
            return [
                Variant(key: "done.1", text: loc("C'est passé, après \(time). Bien joué."), mood: .happy, action: .openSession),
                Variant(key: "done.2", text: loc("\(around.agent) a fini sur \(project), en \(time)."), mood: .happy, action: .openSession),
                Variant(key: "done.3", text: loc("\(cap(time)) plus tard, c'est terminé sur \(project)."), mood: .happy, action: .openSession),
            ]

        case .meetingWhileAgentWaits(let title, let minutes):
            let time = FrenchText.spokenMinutes(Double(minutes) * 60)
            return [
                Variant(key: "meeting.1", text: loc("\(title) dans \(time), et \(around.agent) attend ta réponse."), mood: .worried, action: .openSession),
                Variant(key: "meeting.2", text: loc("\(around.agent) t'attend, et \(title) commence dans \(time)."), mood: .worried, action: .openSession),
                Variant(key: "meeting.3", text: loc("Deux choses : \(around.agent) attend, et \(title) est dans \(time)."), mood: .worried, action: .openSession),
            ]

        case .late:
            return [
                Variant(key: "late.1", text: loc("Il est tard. Je reste là, mais toi tu peux aller dormir."), mood: .asleep),
                Variant(key: "late.2", text: loc("Il se fait tard\(comma). Ça attendra demain, non ?"), mood: .asleep),
                Variant(key: "late.3", text: loc("Je bâille. Toi aussi, je parie."), mood: .asleep),
            ]

        case .lowBattery(let percent):
            return [
                Variant(key: "battery.1", text: loc("\(cap(n(percent))) pour cent. Je dis ça, je dis rien."), mood: .worried),
                Variant(key: "battery.2", text: loc("Plus que \(n(percent)) pour cent de batterie. Le chargeur n'est pas loin ?"), mood: .worried),
                Variant(key: "battery.3", text: loc("\(cap(n(percent))) pour cent et pas de chargeur. Je m'inquiète un peu."), mood: .worried),
            ]

        case .repository(let event, let count):
            let repo = event.repoName
            switch event.kind {
            case .star where count > 1:
                let stars = loc("\(n(count, feminine: true)) étoiles")
                return [
                    Variant(key: "gh.stars.1", text: loc("\(cap(stars)) d'un coup sur \(repo). Ça brille."), mood: .happy),
                    Variant(key: "gh.stars.2", text: loc("\(repo) vient de prendre \(stars)."), mood: .happy),
                    Variant(key: "gh.stars.3", text: loc("\(cap(stars)) de plus pour \(repo). Je les ai comptées."), mood: .wink),
                ]
            case .star where event.actor.isEmpty:
                return [
                    Variant(key: "gh.star.q1", text: loc("Une étoile de plus sur \(repo). Va voir."), mood: .happy),
                    Variant(key: "gh.star.q2", text: loc("Hé, quelqu'un vient d'étoiler \(repo)."), mood: .wink),
                    Variant(key: "gh.star.q3", text: loc("\(repo) prend une étoile. Ça brille."), mood: .happy),
                ]
            case .fork where event.actor.isEmpty:
                return [
                    Variant(key: "gh.fork.q1", text: loc("Hé, \(repo) vient d'être forké."), mood: .curious),
                    Variant(key: "gh.fork.q2", text: loc("Un fork de plus pour \(repo). Ton code voyage."), mood: .happy),
                ]
            case .push:
                let who = event.actor.isEmpty ? "" : loc(" par \(event.actor)")
                if event.headline.isEmpty {
                    return [
                        Variant(key: "gh.push.1", text: loc("Hé, il y a eu un push sur \(repo)\(who). Regarde."), mood: .curious),
                        Variant(key: "gh.push.2", text: loc("Ça bouge sur \(repo) : du nouveau code\(who)."), mood: .happy),
                    ]
                }
                let line = event.headline.count > 70 ? String(event.headline.prefix(68)) + "…" : event.headline
                return [
                    Variant(key: "gh.commit.1", text: loc("Nouveau commit sur \(repo)\(who) : « \(line) »."), mood: .curious),
                    Variant(key: "gh.commit.2", text: loc("Hé, un push sur \(repo) : « \(line) »."), mood: .happy),
                ]
            case .star:
                return [
                    Variant(key: "gh.star.1", text: loc("Une étoile de plus sur \(repo), de la part de \(event.actor)."), mood: .happy),
                    Variant(key: "gh.star.2", text: loc("\(event.actor) vient d'étoiler \(repo). Je l'ai attrapée au vol."), mood: .wink),
                    Variant(key: "gh.star.3", text: loc("\(repo) plaît à \(event.actor). Une étoile de plus."), mood: .happy),
                ]
            case .fork:
                return [
                    Variant(key: "gh.fork.1", text: loc("\(event.actor) a forké \(repo). Ton code voyage."), mood: .curious),
                    Variant(key: "gh.fork.2", text: loc("\(repo) a un double chez \(event.actor)."), mood: .curious),
                    Variant(key: "gh.fork.3", text: loc("Un fork de \(repo), par \(event.actor). Quelqu'un s'y met."), mood: .happy),
                ]
            case .release:
                let name = event.detail.isEmpty ? loc("Une version de \(repo)") : event.detail
                return [
                    Variant(key: "gh.release.1", text: loc("\(name) est sortie. C'est dehors."), mood: .happy),
                    Variant(key: "gh.release.2", text: loc("\(name) est en ligne\(comma)."), mood: .happy),
                    Variant(key: "gh.release.3", text: loc("\(name) est partie. Je m'incline."), mood: .wink),
                ]
            default:
                let what = event.detail.isEmpty ? loc("sur \(repo)") : loc(": \(event.detail)")
                return [
                    Variant(key: "gh.merge.1", text: loc("C'est fusionné \(what)."), mood: .happy),
                    Variant(key: "gh.merge.2", text: loc("Une pull request de moins sur \(repo). C'est dans la branche."), mood: .happy),
                    Variant(key: "gh.merge.3", text: loc("Fusion faite sur \(repo). Deux gouttes, une seule."), mood: .wink),
                ]
            }

        case .mail(let from, let subject, let count):
            let what = subject.isEmpty ? "" : " : « \(subject.count > 60 ? String(subject.prefix(58)) + "…" : subject) »"
            if count > 1 {
                return [
                    Variant(key: "gh.mail.many.1", text: loc("\(count) nouveaux mails, dont un de \(from)\(what)."), mood: .curious),
                    Variant(key: "gh.mail.many.2", text: loc("Ta boîte se remplit : \(count) mails, le dernier de \(from)."), mood: .surprised),
                ]
            }
            return [
                Variant(key: "gh.mail.1", text: loc("Hé, un mail de \(from)\(what)."), mood: .curious),
                Variant(key: "gh.mail.2", text: loc("Nouveau mail de \(from)\(what)."), mood: .happy),
            ]

        case .weekEnd:
            var end = [
                Variant(key: "week.1", text: loc("Vendredi soir. Tu as bien bossé cette semaine."), mood: .happy),
                Variant(key: "week.2", text: loc("La semaine est finie\(comma). Je garde tout au chaud jusqu'à lundi."), mood: .wink),
                Variant(key: "week.3", text: loc("Vendredi soir. Va voir dehors, je surveille."), mood: .happy),
            ]
            if let project {
                end.insert(Variant(key: "week.project", text: loc("Vendredi soir. \(project) attendra lundi."), mood: .wink), at: 1)
            }
            return end
        }
    }

    /// The name of a project, from a memory such as "Yumi : une app pour la notch" or "Yumi, une app macOS".
    static func projectName(_ memory: String) -> String? {
        let name = memory.split(whereSeparator: { ":,".contains($0) }).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return name.isEmpty || name.count > 24 || name.lowercased().hasPrefix("tu ") ? nil : name
    }

    private static func lowered(_ sentence: String) -> String {
        let trimmed = sentence.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return trimmed.prefix(1).lowercased() + trimmed.dropFirst()
    }
}
