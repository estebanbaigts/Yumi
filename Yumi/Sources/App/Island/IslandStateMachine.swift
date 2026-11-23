import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
/// (This file is compiled as is into the unit tests, with the module contract.)
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // open island
        case greeting // launch sequence: drop, greeting, fold
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// home → petit delay (seconds): the user's setting.
    var homeToPetitDelay: TimeInterval = 15 {
        didSet {
            // A countdown already running starts again with the new delay
            guard homeToPetitDelay != oldValue, homeCollapseWork != nil else { return }
            scheduleHomeCollapse()
        }
    }
    /// false when the user chose "never": the open island only folds when asked to.
    var foldsByItself = true {
        didSet {
            guard foldsByItself != oldValue, state == .home else { return }
            if !foldsByItself {
                homeCollapseWork?.cancel()
                homeCollapseWork = nil
            } else if !hovered && !pinned {
                scheduleHomeCollapse()
            }
        }
    }
    /// petit → hidden delay (seconds): the user's setting.
    var petitToHiddenDelay: TimeInterval = 60 {
        didSet {
            // A countdown already running starts again with the new delay
            guard petitToHiddenDelay != oldValue, petitHideWork != nil else { return }
            schedulePetitHide()
        }
    }
    /// greeting → petit if `greetComplete()` never comes. The launch lasts about 5 s.
    var greetingTimeout: TimeInterval = 8

    /// An alert waits for an answer: the open island never closes by itself.
    var pinned = false {
        didSet {
            guard pinned != oldValue, state == .home else { return }
            if pinned {
                homeCollapseWork?.cancel()
                homeCollapseWork = nil
            } else if !hovered {
                scheduleHomeCollapse()
            }
        }
    }

    /// The pointer is on the island. Kept here so that every way of reaching a state
    /// (click, alert, end of the launch) starts the right timer.
    private var hovered = false

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    /// The pointer rests on the folded island: it opens on its own, without a click.
    private var hoverOpenWork: DispatchWorkItem?
    /// How long the pointer rests on the folded island before it opens (seconds).
    var hoverOpenDelay: TimeInterval = 0.3
    private var greetTimeoutWork: DispatchWorkItem?

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .greeting)
        scheduleGreetTimeout()
    }

    /// Mouse entered the island
    func mouseEntered() {
        hovered = true
        switch state {
        case .hidden:
            cancelTimers()
            transition(to: .petit)
            scheduleHoverOpen()
        case .petit:
            petitHideWork?.cancel()
            petitHideWork = nil
            scheduleHoverOpen()
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .greeting:
            // The launch plays to its end whatever the pointer does
            break
        }
    }

    /// Mouse left the island
    func mouseLeft() {
        hovered = false
        hoverOpenWork?.cancel()
        hoverOpenWork = nil
        switch state {
        case .hidden, .greeting:
            break
        case .petit:
            schedulePetitHide()
        case .home:
            if !pinned { scheduleHomeCollapse() }
        }
    }

    /// Compact island clicked
    func click() {
        guard state == .petit else { return }
        enterHome()
    }

    /// The island opens by itself: an alert, the shortcut, a file dragged over it.
    func open() {
        guard state != .home else { return }
        enterHome()
    }

    /// The open island folds back now: Escape, an "OK" button.
    func collapse() {
        guard state == .home else { return }
        enterPetit()
    }

    /// The user quits: the goodbye plays like the launch, and nothing interrupts it.
    func leave() {
        cancelTimers()
        transition(to: .greeting)
    }

    /// The launch sequence reached its end (about 4.5 s).
    func greetComplete() {
        guard state == .greeting else { return }
        enterPetit()
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal)
    func reveal() {
        guard state == .hidden else { return }
        enterPetit()
    }

    // MARK: – Entering a state

    private func enterHome() {
        cancelTimers()
        transition(to: .home)
        if !hovered && !pinned { scheduleHomeCollapse() }
    }

    private func enterPetit() {
        cancelTimers()
        transition(to: .petit)
        if !hovered { schedulePetitHide() }
    }

    // MARK: – Timers

    private func scheduleHoverOpen() {
        hoverOpenWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.hovered, self.state == .petit else { return }
            self.enterHome()
        }
        hoverOpenWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverOpenDelay, execute: item)
    }

    private func schedulePetitHide() {
        petitHideWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .petit else { return }
            self.transition(to: .hidden)
        }
        petitHideWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + petitToHiddenDelay, execute: item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        homeCollapseWork = nil
        guard foldsByItself else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home, !self.pinned else { return }
            self.enterPetit()
        }
        homeCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + homeToPetitDelay, execute: item)
    }

    private func scheduleGreetTimeout() {
        greetTimeoutWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .greeting else { return }
            self.enterPetit()
        }
        greetTimeoutWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + greetingTimeout, execute: item)
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetTimeoutWork?.cancel(); greetTimeoutWork = nil
        hoverOpenWork?.cancel();    hoverOpenWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
    }

}

// MARK: - The folded island: what is live

/// Pure rules of the folded island (Contracts/ModuleTypes.swift): which module it shows on
/// the right of the notch, and how wide it may grow for it. No view, no state.
enum FoldedIsland {

    /// The live module with the highest priority. With several at that priority, the one
    /// already shown stays, so that the island does not flicker between them; otherwise the
    /// first in the user's order. nil when nothing is live: the island shows nothing.
    static func live(in modules: [ModuleSnapshot], shown: String?) -> ModuleSnapshot? {
        guard let top = modules.compactMap({ $0.live?.priority }).max() else { return nil }
        let best = modules.filter { $0.live?.priority == top }
        return best.first { $0.id == shown } ?? best.first
    }

    /// The second activity, shown in the bubble that detaches from the folded island: the
    /// live module with the highest priority once the main one is set aside.
    static func second(in modules: [ModuleSnapshot], after main: String?) -> ModuleSnapshot? {
        guard let main else { return nil }
        return live(in: modules.filter { $0.id != main }, shown: nil)
    }

    /// True when the change of text is a new thing to read (the next track) rather than the
    /// same thing ticking (a countdown): only the first one slides.
    static func isNewLine(_ old: String, _ new: String) -> Bool {
        skeleton(old) != skeleton(new)
    }

    /// The text without what ticks: every digit reads the same.
    static func skeleton(_ text: String) -> String {
        String(text.map { $0.isNumber ? "0" : $0 })
    }

    /// Width of one ear (the island sticks out by this much on each side of the notch): wide
    /// enough for `content`, never narrower than `minimum`, and never so wide that the folded
    /// island would be wider than the open one.
    static func ear(content: Double, minimum: Double, notchWidth: Double, openWidth: Double) -> Double {
        let widest = max(minimum, (openWidth - notchWidth) / 2)
        return min(max(minimum, content), widest)
    }
}

// MARK: - The chat answering live

/// Pure rules of the talk view while an answer is being made (Contracts/ChatLive.swift).
enum LiveChat {

    /// The conversation follows its last line only while the reader is at the bottom:
    /// someone who scrolled up to read is left where they are.
    static func followsBottom(offset: Double, viewport: Double, content: Double, slack: Double = 12) -> Bool {
        content <= viewport || offset + viewport >= content - slack
    }

    /// Kinds of action (`ChatActivity.Kind` raw values) that leave something behind.
    static let changes: Set<String> = ["writing", "editing"]

    /// Yumi celebrates an answer that created or modified something, and only if it worked.
    static func celebrates(done: [(kind: String, succeeded: Bool)]) -> Bool {
        done.contains { changes.contains($0.kind) && $0.succeeded }
    }
}

// MARK: - Asking the first name

/// Yumi asks the person's first name once, after the launch, and does not insist
/// (design/voix.md): passed over, he asks again some days later.
enum FirstName {
    /// How long he waits before asking again.
    static let patience: TimeInterval = 3 * 24 * 3600

    static func shouldAsk(name: String?, lastAsked: Date?, now: Date) -> Bool {
        guard clean(name ?? "") == nil else { return false }
        guard let lastAsked else { return true }
        return now.timeIntervalSince(lastAsked) >= patience
    }

    /// What was typed, as a first name: trimmed, one line, not endless. nil when empty.
    static func clean(_ typed: String) -> String? {
        let line = typed.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let name = line.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(40))
    }
}

// MARK: - Yumi's voice

/// How Yumi writes numbers and durations (design/voix.md): small numbers in letters
/// inside a sentence, figures only for values read at a glance.
enum Voice {
    /// "douze" up to ninety-nine, figures beyond.
    static func number(_ n: Int) -> String {
        FrenchText.spelled(n)
    }


    /// "moins d'une minute", "une minute", "douze minutes", "une heure", "deux heures dix".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes < 1 { return loc("moins d'une minute") }
        // In the language of the app: "deux heures dix", "two hours and ten minutes".
        return FrenchText.spokenMinutes(TimeInterval(minutes * 60))
    }

    /// "un fichier touché", "trois fichiers touchés"; nil for none.
    static func files(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? loc("un fichier touché") : loc("\(number(count)) fichiers touchés")
    }

    /// A sentence starts with a capital.
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The first name, when it is worth saying: he uses it rarely.
    static func goodbye(name: String?) -> String {
        guard let name = FirstName.clean(name ?? "") else { return loc("À tout à l'heure") }
        return loc("À tout à l'heure, \(name)")
    }
}

// MARK: - When Yumi speaks first

/// The size the folded island takes to hold one remark next to Yumi (Contracts/RemarkTypes.swift):
/// just wide enough for the sentence, on one line when it fits and on two when it does not.
enum Speak {
    /// Yumi's place on the left, then the text.
    static let lead: Double = 62
    static let trail: Double = 12
    /// The cross, and the gap before it.
    static let cross: Double = 28
    static let textMax: Double = 340
    static let oneLine: Double = 34
    static let twoLines: Double = 50

    struct Size: Equatable {
        var width: Double
        /// Height under the notch.
        var band: Double
        var textWidth: Double
        var lines: Int
    }

    /// - Parameters:
    ///   - text: width of the sentence on a single line.
    ///   - action: width of the action button, 0 without one.
    ///   - minimum: the island is never narrower than this (its folded width).
    static func size(text: Double, action: Double, minimum: Double) -> Size {
        let lines = text > textMax ? 2 : 1
        // On two lines the text is about half as wide, with room for an uneven break
        let textWidth = lines == 1 ? text : min(textMax, max(textMax * 0.6, text / 2 + 40))
        let width = lead + textWidth + (action > 0 ? 10 + action : 0) + cross + trail
        return Size(width: max(minimum, width.rounded(.up)), band: lines == 1 ? oneLine : twoLines,
                    textWidth: textWidth.rounded(.up), lines: lines)
    }
}

// MARK: - GitHub

/// The three figures of the GitHub activity, read from the module's `status`:
/// stars, forks and open pull requests, in that order, separated by " · ".
enum GitHubFigures {
    struct Figures: Equatable {
        var stars: String
        var forks: String
        var pulls: String
    }

    /// nil when the status is not three figures: the island then shows it as it is.
    static func parse(_ status: String) -> Figures? {
        let parts = status.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.first!.isNumber }) else { return nil }
        return Figures(stars: parts[0], forks: parts[1], pulls: parts[2])
    }

    /// A token as it is pasted: without the spaces and line breaks around it. nil when empty.
    static func cleanToken(_ typed: String) -> String? {
        let token = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}

// MARK: - The time of a line of a module's list

enum RowTime {
    /// Since when, for a session: "à l'instant", "4 min", "1 h 05".
    static func elapsed(since date: Date, now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return loc("à l'instant") }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(String(format: "%02d", minutes % 60))"
    }

    /// When, for an event: "14:05" today, "hier", or "3 oct." before.
    static func clock(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(date, inSameDayAs: now) {
            if AppLanguage.isEnglish {
                formatter.setLocalizedDateFormatFromTemplate("jmm")
                return formatter.string(from: date)
            }
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return loc("hier")
        }
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}

// MARK: - Versions and feedback

/// A version of Yumi as GitHub tags it: "v0.1.0-alpha.2", compared the semantic-versioning way.
struct YumiVersion: Comparable, Equatable, Sendable {
    var core: [Int]
    /// "alpha.2" → ["alpha", "2"]. Empty for a release.
    var pre: [String]

    init?(_ text: String) {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        text = String(text.split(separator: "+", maxSplits: 1).first ?? "")
        let parts = text.split(separator: "-", maxSplits: 1).map(String.init)
        guard let first = parts.first, !first.isEmpty else { return nil }
        let numbers = first.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        core = numbers.compactMap { $0 }
        while core.count < 3 { core.append(0) }
        pre = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    static func < (a: YumiVersion, b: YumiVersion) -> Bool {
        if a.core != b.core { return a.core.lexicographicallyPrecedes(b.core) }
        // A release comes after all its pre-releases
        if a.pre.isEmpty || b.pre.isEmpty { return !a.pre.isEmpty && b.pre.isEmpty }
        for (x, y) in zip(a.pre, b.pre) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil):    return true
            case (nil, _?):    return false
            default:           return x < y
            }
        }
        return a.pre.count < b.pre.count
    }
}

/// The "Envoyer un retour" link: a new issue of the repository, on the bug form, with the facts
/// of this Mac filled in. Nothing else: no logs, nothing personal. GitHub's chooser page drops
/// what is passed to it, so the link goes to the form itself; the form links back to the others.
enum Feedback {
    static let newIssue = "https://github.com/estebanbaigts/Yumi/issues/new"
    /// A form that needs no account (Tally). Its hidden field `version` is filled from the link.
    static let form = "https://tally.so/r/Me9lvA"

    static func formURL(version: String) -> URL? {
        var parts = URLComponents(string: form)
        parts?.queryItems = [URLQueryItem(name: "version", value: version)]
        return parts?.url
    }

    /// The fields of `.github/ISSUE_TEMPLATE/bug.yml`, by their `id`.
    static func fields(version: String, macOS: String, model: String, notch: Bool) -> [(String, String)] {
        [("version-yumi", version), ("version-macos", macOS), ("mac", "\(model), notch : \(notch ? loc("oui") : loc("non"))")]
    }

    static func url(version: String, macOS: String, model: String, notch: Bool) -> URL? {
        var parts = URLComponents(string: newIssue)
        parts?.queryItems = [URLQueryItem(name: "template", value: "bug.yml")]
            + fields(version: version, macOS: macOS, model: model, notch: notch).map { URLQueryItem(name: $0.0, value: $0.1) }
        return parts?.url
    }
}

// MARK: - The settings window

/// The pages of the settings window, in the order of its sidebar.
enum SettingsPage: String, CaseIterable, Identifiable, Sendable {
    case general, yumi, modules, engines, claudeCode, permissions, memory, about, developer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return loc("Général")
        case .yumi:        return "Yumi"
        case .modules:     return "Modules"
        case .engines:     return loc("Moteurs")
        case .claudeCode:  return "Claude Code"
        case .permissions: return loc("Autorisations")
        case .memory:      return loc("Mémoire")
        case .about:       return loc("À propos")
        case .developer:   return loc("Développeur")
        }
    }

    var symbol: String {
        switch self {
        case .general:     return "gearshape"
        case .yumi:        return "face.smiling"
        case .modules:     return "square.grid.2x2"
        case .engines:     return "cpu"
        case .claudeCode:  return "terminal"
        case .permissions: return "hand.raised"
        case .memory:      return "brain"
        case .about:       return "info.circle"
        case .developer:   return "hammer"
        }
    }

    /// The sidebar: the developer page only once it was asked for.
    static func sidebar(developer: Bool) -> [SettingsPage] {
        allCases.filter { $0 != .developer || developer }
    }

    /// The page to show: one hidden from the sidebar falls back to the first page.
    static func shown(_ page: SettingsPage?, developer: Bool) -> SettingsPage {
        guard let page, sidebar(developer: developer).contains(page) else { return .general }
        return page
    }

    /// Where each stored setting lives: the same UserDefaults and Keychain keys as before the
    /// window was redone, so nothing set earlier is lost.
    static let settings: [SettingsPage: [String]] = [
        .general:     ["yumiLanguage", "tripleShiftEnabled", "launchAtStartup", "hotkeyEnabled", "hotkeyFlags", "hotkeyCode", "autoCloseInterval",
                       "absenceInterval", "contextEngineEnabled", "quickTaskShortcutEnabled", "quickTaskShortcutFlags",
                       "quickTaskShortcutCode", "quickTaskDestination", "quickTaskNotionBase"],
        .yumi:        ["soundEnabled", "soundVolume", "workHabit", "yumiTalk"],
        .modules:     ["github-token", "github-app-token", "agendaHiddenCalendars", "agendaTargetCalendar"],
        .engines:     ["engineSettings", "engineKeys"],
        .claudeCode:  ["hooks", "claudeDirectoryBookmark"],
        .permissions: ["macOSPermissions", "yumiPermissions"],
        .memory:      ["userName", "memory"],
        .about:       ["updateCheckEnabled", "feedback", "settingsDeveloper"],
        .developer:   ["contextPanel", "agentPanel"],
    ]

    /// Shows the developer page in the sidebar.
    static let developerKey = "settingsDeveloper"
}

// MARK: - Reaching Yumi without the menu bar

/// Three quick presses on Shift, alone: opens or folds the island. A press is Shift going down
/// then up with no other key or modifier in between.
struct TripleShift: Equatable, Sendable {
    /// The three presses must fit in this time.
    static let window: TimeInterval = 0.8
    static let defaultsKey = "tripleShiftEnabled"

    private var presses: [TimeInterval] = []
    private var down = false
    private var spoiled = false

    init() {}

    /// The modifiers changed. Returns true when this release completes a triple press.
    mutating func modifiers(shift: Bool, others: Bool, at time: TimeInterval) -> Bool {
        if others { presses = []; spoiled = down || shift; down = shift; return false }
        if shift && !down {
            down = true
            spoiled = false
            return false
        }
        guard !shift && down else { return false }
        down = false
        if spoiled { presses = []; return false }
        presses = presses.filter { time - $0 <= Self.window } + [time]
        guard presses.count >= 3 else { return false }
        presses = []
        return true
    }

    /// Another key was typed: the presses before it do not count.
    mutating func keyTyped() {
        presses = []
        spoiled = down
    }
}

/// A click outside the open island folds it, unless something is waiting there.
enum OutsideClick {
    static func folds(islandOpen: Bool, insideIsland: Bool, approvalPending: Bool, unsentDraft: Bool, pinned: Bool) -> Bool {
        islandOpen && !insideIsland && !approvalPending && !unsentDraft && !pinned
    }
}

/// Opening the settings window folds the island, as a click beside it would, unless an
/// approval waits there: then the island stays and the window opens below it.
enum SettingsOpening {
    static func foldsIsland(approvalPending: Bool) -> Bool { !approvalPending }

    /// Where the window starts (screen coordinates, origin bottom-left): centred horizontally,
    /// its top under the menu bar and under the island when it stays open, inside the screen.
    static func frame(size: CGSize, visible: CGRect, islandBottom: CGFloat?, gap: CGFloat = 12) -> CGRect {
        var top = visible.maxY - gap
        if let islandBottom { top = min(top, islandBottom - gap) }
        let height = min(size.height, max(top - visible.minY, 200))
        let width = min(size.width, visible.width)
        let y = max(visible.minY, top - height)
        let x = visible.midX - width / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// When the island offers to install the Claude Code hooks: Claude Code is there, the hooks
/// are not, it was never offered, and nothing is being filmed. Nothing is written without the
/// person's accord: the offer only opens the preview.
enum HookOffer {
    static let defaultsKey = "hookOfferShown"

    static func offers(claudeCodeInstalled: Bool, hooksInstalled: Bool, alreadyOffered: Bool, filming: Bool) -> Bool {
        claudeCodeInstalled && !hooksInstalled && !alreadyOffered && !filming
    }
}
