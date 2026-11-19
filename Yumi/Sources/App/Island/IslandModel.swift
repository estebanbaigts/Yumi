import SwiftUI

/// What the island knows on top of `AppState`: its shape during the launch, the module it
/// shows, the second square, and what it last asked Yumi to do.
@MainActor
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    /// Set once by the window controller, from the screen the island lives on.
    @Published var layout = IslandLayout()

    // MARK: Launch

    /// The shape of the island while the launch plays; nil the rest of the time.
    @Published var launchStage: IslandStage?
    /// The classes of `.greet` in the mock-up: lit, say, bye.
    @Published var greeting = GreetingPhase()
    /// The overview is in "Modifier" mode: the modules wiggle, can be moved and hidden.
    @Published var editingModules = false
    /// The chat field holds text not sent yet.
    var hasDraft = false
    /// The sequence playing is the goodbye, not the launch.
    @Published var leaving = false
    /// When the rings and the sparks of the greeting started.
    @Published var sparksStart: Date?
    /// True for the one change that must not be animated (the mock-up's `snap`).
    @Published var snap = false

    struct GreetingPhase: Equatable {
        var lit = false
        var say = false
        var bye = false
    }

    // MARK: Folded island

    /// The live module shown on the right of the notch: kept while another one only ties with it.
    @Published var liveModuleID: String?
    /// The pointer is on the folded island: the buttons of the live module are out.
    @Published var foldedHover = false
    /// How many of those buttons there are, for the window controller's hit test.
    var foldedControls = 0

    // MARK: When Yumi speaks first (Contracts/RemarkTypes.swift)

    /// A remark is on screen in the folded island: it takes the `speak` shape.
    @Published var speaking = false
    /// The remark the person answered or closed: it leaves at once, before the core clears it.
    @Published var closedRemarkID: String?
    private var remarkTimer: DispatchWorkItem?

    /// The remark to show, if any.
    func remark(in state: AppState) -> YumiRemark? {
        guard let remark = state.remark, remark.id != closedRemarkID else { return nil }
        return remark
    }

    /// A remark appears: it stays `duration` seconds, then leaves as ignored.
    func remarkAppeared(_ remark: YumiRemark?) {
        remarkTimer?.cancel()
        remarkTimer = nil
        guard let remark else { return }
        pose(.pop)
        let item = DispatchWorkItem { [weak self] in self?.close(remark, ignored: true) }
        remarkTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2, remark.duration), execute: item)
    }

    /// The action of the remark was pressed.
    func accept(_ remark: YumiRemark) {
        guard closedRemarkID != remark.id else { return }
        remarkTimer?.cancel()
        closedRemarkID = remark.id
        NotificationCenter.default.post(name: .remarkAccepted, object: nil, userInfo: ["id": remark.id])
        SoundEngine.shared.play("blip")
    }

    /// Closed by the person (`ignored` false) or left untouched until its time ran out (true).
    func close(_ remark: YumiRemark, ignored: Bool) {
        guard closedRemarkID != remark.id else { return }
        remarkTimer?.cancel()
        closedRemarkID = remark.id
        NotificationCenter.default.post(name: .remarkDismissed, object: nil,
                                        userInfo: ["id": remark.id, "ignored": ignored])
    }

    /// Filming mode: the green button of the alert looks pressed, without a pointer.
    @Published var studioPress = false

    // MARK: Open island

    @Published var selectedModuleID: String?
    /// The tab of the open island: Travail, Journée or Détente. Kept from one opening to the next.
    @Published var category: ModuleCategory = ModuleCategory(rawValue: UserDefaults.standard.string(forKey: IslandPrefs.categoryKey) ?? "") ?? .work {
        didSet { UserDefaults.standard.set(category.rawValue, forKey: IslandPrefs.categoryKey) }
    }
    /// The Claude Code session shown in the large card; nil: the first one.
    @Published var selectedSessionID: String?
    /// A letter typed while the island was open: the chat opens with it in its field.
    var chatSeed: String?
    /// The chat opens on the list of past conversations ("Tout voir" › Conversations).
    @Published var showChatHistory = false

    /// The pseudo module of the work tab that shows the quick task and its list.
    static let tasksID = "tasks"

    /// What the open tab offers, in the person's order: its modules, and the tasks in "Travail".
    func entries(in category: ModuleCategory, modules: [ModuleSnapshot]) -> [String] {
        let ids = modules.filter { $0.tab == category }.map(\.id)
        guard category == tasksSpace else { return ids }
        // The tasks tile sits where the person put it, at the end until then
        var out = ids
        out.insert(Self.tasksID, at: min(max(0, tasksPlace ?? ids.count), ids.count))
        return out
    }

    /// The space the tasks tile lives in: Travail until the person moves it.
    var tasksSpace: ModuleCategory {
        get { (UserDefaults.standard.string(forKey: "island.tasks.space")).flatMap(ModuleCategory.init(rawValue:)) ?? .work }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "island.tasks.space"); objectWillChange.send() }
    }

    /// The place of the tasks tile among its tab's tiles, once the person moved it.
    var tasksPlace: Int? {
        get { UserDefaults.standard.object(forKey: "island.tasks.place") as? Int }
        set { UserDefaults.standard.set(newValue, forKey: "island.tasks.place"); objectWillChange.send() }
    }

    /// The module of the open tab on screen: the chosen one if it is in the tab, else the first.
    func current(in category: ModuleCategory, modules: [ModuleSnapshot]) -> String? {
        let ids = entries(in: category, modules: modules)
        if let id = selectedModuleID, ids.contains(id) { return id }
        return ids.first
    }

    /// The tabs worth showing: the ones that hold something.
    func tabs(modules: [ModuleSnapshot]) -> [ModuleCategory] {
        // The three spaces are always there, so a module can be dropped into an empty one
        modules.isEmpty ? [] : ModuleCategory.allCases
    }

    /// Where each tab of the top row is, in the open island's coordinates.
    var tabFrames: [ModuleCategory: CGRect] = [:]
    /// The tab a dragged module hovers.
    @Published var dropTab: ModuleCategory?
    /// Height the open island needs for what it shows: it is as low as the content allows.
    @Published var openHeight: CGFloat = IslandConst.openHeightDefault

    // MARK: What the agent has been doing (for "Depuis 12 min, 3 fichiers modifiés")

    @Published var workStart: Date?
    @Published var workEnd: Date?
    @Published var filesTouched: Set<String> = []

    // MARK: Yumi

    /// The habit last asked for. His caption follows it.
    @Published private(set) var habit: YumiHabit?
    private var sentMood: YumiMood?
    private var sentRim: YumiRimTone?
    private var lateHabit: DispatchWorkItem?
    /// What he holds in the current session of work; nil when no agent works.
    private var workPick: YumiHabit?
    private var winkBack: DispatchWorkItem?

    /// The character view is in the window and listens to the commands.
    private(set) var actorReady = false
    private var whenReady: [() -> Void] = []

    private init() {}

    // MARK: - Shape

    func stage(for mode: IslandMode) -> IslandStage {
        if let launchStage { return launchStage }
        switch mode {
        case .hidden:   return .hidden
        case .compact:  return speaking ? .speak : .compact
        case .expanded: return .open
        }
    }

    func islandSize(for mode: IslandMode) -> CGSize {
        layout.size(stage(for: mode), openHeight: openHeight)
    }

    // MARK: - Modules

    /// The module with dedicated screens (working, alert, finished, error): the home view
    /// does not repeat it.
    static let agentModuleID = "claude-code"

    func pinned(_ modules: [ModuleSnapshot]) -> [ModuleSnapshot] {
        Array(modules.prefix(ModuleCatalog.pinnedLimit))
    }

    func others(_ modules: [ModuleSnapshot]) -> [ModuleSnapshot] {
        Array(modules.dropFirst(ModuleCatalog.pinnedLimit).prefix(ModuleCatalog.selectionLimit - ModuleCatalog.pinnedLimit))
    }

    func selectedModule(in modules: [ModuleSnapshot]) -> ModuleSnapshot? {
        modules.first { $0.id == selectedModuleID } ?? modules.first
    }

    /// The one thing the home view shows: what needs the user now, else the next thing to know.
    func featuredModule(in modules: [ModuleSnapshot]) -> ModuleSnapshot? {
        modules.first { $0.needsAttention }
            ?? modules.first { $0.id != Self.agentModuleID }
            ?? modules.first
    }

    static func isBusy(_ state: BotState) -> Bool {
        state == .working || state == .thinking || state == .searching
    }

    nonisolated static func isMusic(_ moduleID: String?) -> Bool {
        moduleID == "music" || moduleID == "musique"
    }

    // MARK: - Agent activity

    func track(state old: BotState, _ new: BotState) {
        let busy: Set<BotState> = [.working, .thinking, .searching]
        let paused: Set<BotState> = [.approval, .question]
        if busy.contains(new), !busy.contains(old), !paused.contains(old) {
            workStart = .now
            workEnd = nil
            filesTouched = []
        }
        if new == .finished || new == .error, workEnd == nil { workEnd = .now }
        if new == .idle, old != .finished { workStart = nil }
    }

    /// Steps look like "Modifie · IslandRootView.swift" (HookServer.frenchStep).
    func track(step: String?) {
        guard let step else { return }
        for verb in [loc("Modifie") + " · ", loc("Écrit") + " · "] where step.hasPrefix(verb) {
            filesTouched.insert(String(step.dropFirst(verb.count)))
        }
    }

    // MARK: - Commanding Yumi (Contracts/CharacterCommands.swift)

    func actorAppeared() {
        actorReady = true
        let pending = whenReady
        whenReady = []
        pending.forEach { $0() }
    }

    /// Runs `work` once the character can hear commands.
    func onActorReady(_ work: @escaping () -> Void) {
        if actorReady { work() } else { whenReady.append(work) }
    }

    func pose(_ pose: YumiPose) {
        NotificationCenter.default.post(name: .yumiPose, object: pose)
    }

    func setHabit(_ newHabit: YumiHabit?) {
        var newHabit = newHabit
        #if DEBUG
        // `YUMI_HABIT=headphones` (or smoke, coffee, cloud, whistle, sleep…) keeps that habit on,
        // to measure what a habit that lasts costs
        if let forced = ProcessInfo.processInfo.environment["YUMI_HABIT"] {
            newHabit = YumiHabit(rawValue: forced)
        }
        #endif
        habit = newHabit
        NotificationCenter.default.post(name: .yumiHabit, object: newHabit)
    }

    /// The character clears the gaze and any passing face on every mood it receives, so a
    /// mood is only sent when it changes. Send the gaze after it.
    func setMood(_ mood: YumiMood?, force: Bool = false) {
        guard force || mood != sentMood else { return }
        sentMood = mood
        NotificationCenter.default.post(name: .yumiMood, object: mood)
    }

    /// A small sign that he learnt something: a wink, then the face he had.
    func wink() {
        let before = sentMood
        winkBack?.cancel()
        NotificationCenter.default.post(name: .yumiMood, object: YumiMood.wink)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NotificationCenter.default.post(name: .yumiMood, object: self.sentMood ?? before)
        }
        winkBack = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    func setRim(_ tone: YumiRimTone?) {
        guard tone != sentRim else { return }
        sentRim = tone
        NotificationCenter.default.post(name: .yumiRim, object: tone)
    }

    func setLit(_ on: Bool) {
        NotificationCenter.default.post(name: .yumiLit, object: on)
    }

    func setGaze(_ point: CGPoint?) {
        NotificationCenter.default.post(name: .yumiGaze, object: point)
    }

    // MARK: - Context (Context/ContextSnapshot.swift)

    /// What the Context Engine says about Yumi: idle, observing, or the front application just changed.
    @Published private(set) var contextPresence = ContextPresence.idle
    private var glanceBack: DispatchWorkItem?
    private var glanceSide: CGFloat = 1

    /// The front application changed: folded and with nothing else going on, he glances down
    /// at it, then his eyes follow the pointer again. He only looks; he does nothing about it.
    func contextPresenceChanged(_ presence: ContextPresence, stage: IslandStage) {
        contextPresence = presence
        guard presence == .contextChanged, launchStage == nil, stage == .compact, habit == nil else { return }
        glanceSide = -glanceSide
        setGaze(CGPoint(x: 0.5 * glanceSide, y: 0.6))
        glanceBack?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard self?.launchStage == nil else { return }
            self?.setGaze(nil)
        }
        glanceBack = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: item)
    }

    /// What the island is doing, as far as Yumi is concerned.
    struct Situation: Equatable {
        var stage: IslandStage
        /// The screen shown, or the one that would be if the island were open.
        var screen: IslandScreen
        var moduleID: String?
        /// What he holds while an agent works (the setting).
        var workHabit: YumiWorkHabit
        /// The live module is the music, and it is playing.
        var music = false
        /// The chat is carrying out an action right now (reading, writing, running).
        var chatActs = false
        /// An agent is at work.
        var busy = false
        /// The face of what Yumi is saying on his own.
        var remarkMood: YumiMood?
    }

    /// `STATES` of the mock-up: the face, the rim colour, the habit and the pose of each view.
    /// The character already follows `AppState.effectiveState` by itself; the island adds
    /// what only it knows.
    func direct(from old: Situation?, to new: Situation) {
        guard launchStage == nil, new.stage == .open || new.stage == .compact || new.stage == .speak || new.stage == .hidden else { return }

        if new.stage == .hidden {
            cancelLateHabit()
            setHabit(nil)
            setMood(nil)
            setRim(nil)
            return
        }

        let open = new.stage == .open
        let stageChanged = old?.stage != new.stage
        let viewChanged = old?.screen != new.screen || (new.screen == .module && old?.moduleID != new.moduleID)

        // Face and rim: only for the views the state of the agent knows nothing about.
        var look = open ? Self.look(for: new.screen, moduleID: new.moduleID) : nil
        // Talking: he thinks while there is only text, and works during an action
        if open, new.screen == .talk, new.chatActs { look = (.focused, .work) }
        // While he says something on his own, he makes the face that goes with it
        setMood(new.remarkMood ?? look?.mood)
        setRim(look?.rim)

        // Habit. Music playing puts his headphones on wherever nothing else is going on:
        // folded, on the home view, and on the view of the music module.
        let listening = (new.music && (!open || new.screen == .home))
            || (open && new.screen == .module && Self.isMusic(new.moduleID))
        // An agent at work: the cigarette, the coffee or the matcha chosen in the settings.
        // Shown wherever the island is not about something else.
        let atWork = new.busy && (!open || new.screen == .home || new.screen == .working)
        if !atWork { workPick = nil }
        switch new.screen {
        case _ where atWork:
            cancelLateHabit()
            // Drawn once per session of work, so the random choice does not change hands
            if workPick == nil || old?.workHabit != new.workHabit {
                workPick = new.workHabit.habit(filming: IslandStudio.isOn)
            }
            setHabit(workPick)
        case .error:
            cancelLateHabit()
            setHabit(.cloud)
        case .finished:
            // He celebrates first; the sunglasses drop once he has landed (`late: [1650, 'soleil']`).
            if old?.screen != .finished {
                setHabit(nil)
                let item = DispatchWorkItem { [weak self] in self?.setHabit(.sunglasses) }
                lateHabit = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.65, execute: item)
            }
        default:
            cancelLateHabit()
            setHabit(listening ? .headphones : nil)
        }

        // A habit brings its own face: it steps aside while he says something on his own
        if new.remarkMood != nil, habit != nil {
            cancelLateHabit()
            setHabit(nil)
        }

        // Pose: `playPose(Y, s.pose || 'pop')` on every view
        if stageChanged {
            pose(open ? Self.pose(for: new.screen) : .pop)
        } else if viewChanged {
            pose(Self.pose(for: new.screen))
        }
    }

    private func cancelLateHabit() {
        lateHabit?.cancel()
        lateHabit = nil
    }

    /// Forgets what was sent, so that the next `direct` sends everything again.
    func forgetCommands() {
        cancelLateHabit()
        sentMood = nil
        sentRim = nil
        habit = nil
    }

    static func look(for screen: IslandScreen, moduleID: String? = nil) -> (mood: YumiMood, rim: YumiRimTone)? {
        switch screen {
        case .module where isMusic(moduleID): return nil   // his headphones bring their own face
        case .module where moduleID == "focus": return (.focused, .think)
        case .module where moduleID == "agenda": return (.neutral, .calm)
        case .settings, .memory, .quickTask, .apps: return (.curious, .calm)
        case .welcome: return (.happy, .joy)
        case .home:     return nil   // the state of the agent decides (neutral and calm at rest)
        case .working:  return (.focused, .work)
        case .alert:    return (.surprised, .warn)
        case .finished: return (.happy, .done)
        case .error:    return (.worried, .error)
        case .module:   return (.curious, .calm)
        case .talk:     return (.thinking, .think)
        case .drop:     return (.surprised, .calm)
        }
    }

    static func pose(for screen: IslandScreen) -> YumiPose {
        switch screen {
        case .alert:    return .shake
        case .finished: return .celebrate
        case .error:    return .squash
        case .drop:     return .stretch
        case .welcome: return .wave
        case .home, .working, .module, .talk, .settings, .memory, .quickTask, .apps: return .pop
        }
    }

    /// The few words under Yumi (`cap`). A habit says it its own way.
    static func caption(for habit: YumiHabit) -> String {
        switch habit {
        case .smoke:      return loc("Il bosse dur")
        case .exhausted:  return loc("J'en peux plus")
        case .coffee:     return loc("Café d'abord")
        case .headphones: return loc("Il kiffe")
        case .sunglasses: return "Trop facile"
        case .cloud:      return loc("Sale journée")
        case .whistle:    return loc("La la la")
        case .sleep:      return "Chut"
        case .matcha:     return loc("Pause matcha")
        case .tea:        return loc("Pause thé")
        case .water:      return loc("Je m'hydrate")
        case .juice:      return loc("Petit jus")
        case .book:       return loc("Un chapitre")
        case .gamepad:    return loc("Encore une partie")
        case .knitting:   return loc("Maille à l'endroit")
        case .focus:      return loc("Concentré")
        }
    }
}

// MARK: - Preferences of the island

enum IslandPrefs {
    /// What he holds while an agent works (YumiWorkHabit). "La cigarette doit pouvoir être
    /// désactivée" (docs/journal.md): it is one choice among others.
    static let workHabitKey = YumiWorkHabit.defaultsKey
    /// When Yumi last asked the first name.
    static let nameAskedKey = "firstNameAskedAt"
    /// The tab of the open island last shown.
    static let categoryKey = "islandCategory"
}
