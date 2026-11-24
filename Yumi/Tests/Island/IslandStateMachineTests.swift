import Testing
import Foundation

// IslandStateMachine.swift is compiled straight into this bundle (see project.yml):
// it has no dependency, so the tests run without launching the app.

@Suite @MainActor struct IslandStateMachineTests {

    typealias State = IslandStateMachine.State

    /// Short enough to keep the suite fast, long enough to be observed.
    static let short: TimeInterval = 0.05
    /// Longer than any test waits: a timer set to this never fires during a test.
    static let never: TimeInterval = 60
    /// How long we watch a state that must not change.
    static let settle: Duration = .milliseconds(250)

    /// Records every (from, to) pair reported by `onTransition`.
    final class Log {
        var transitions: [[State]] = []
    }

    private func makeFSM(
        homeToPetit: TimeInterval = never,
        petitToHidden: TimeInterval = never,
        greetTimeout: TimeInterval = never,
        hoverOpen: TimeInterval = 0.3
    ) -> (IslandStateMachine, Log) {
        let fsm = IslandStateMachine()
        fsm.hoverOpenDelay = hoverOpen
        fsm.homeToPetitDelay = homeToPetit
        fsm.petitToHiddenDelay = petitToHidden
        fsm.greetingTimeout = greetTimeout
        let log = Log()
        fsm.onTransition = { from, to in log.transitions.append([from, to]) }
        return (fsm, log)
    }

    /// Polls until the machine reaches `expected`, or gives up after `timeout`.
    private func reaches(_ expected: State, _ fsm: IslandStateMachine, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while fsm.state != expected {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    // MARK: – Initial state and launch

    @Test func startsHidden() {
        let (fsm, log) = makeFSM()
        #expect(fsm.state == .hidden)
        #expect(log.transitions.isEmpty)
    }

    @Test func launchOpensTheGreeting() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        #expect(fsm.state == .greeting)
        #expect(log.transitions == [[.hidden, .greeting]])
    }

    @Test func launchingTwiceReportsOneTransition() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        fsm.launch()
        #expect(log.transitions.count == 1)
    }

    @Test func launchCancelsAPendingHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.launch()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .greeting)
    }

    // MARK: – Hover

    @Test func hoverRevealsTheCompactIsland() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        #expect(fsm.state == .petit)
        #expect(log.transitions == [[.hidden, .petit]])
    }

    @Test func leavingWhileHiddenDoesNothing() {
        let (fsm, log) = makeFSM()
        fsm.mouseLeft()
        #expect(fsm.state == .hidden)
        #expect(log.transitions.isEmpty)
    }

    @Test func compactIslandHidesAfterTheMouseLeaves() async {
        let (fsm, log) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        #expect(fsm.state == .petit)
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [[.hidden, .petit], [.petit, .hidden]])
    }

    @Test func aShorterHideDelayTakesEffectAtOnce() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.never)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.petitToHiddenDelay = Self.short
        #expect(await reaches(.hidden, fsm))
    }

    @Test func aLongerHideDelayTakesEffectAtOnce() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.petitToHiddenDelay = Self.never
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    @Test func compactIslandStaysWhileHovered() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short, hoverOpen: Self.never)
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    @Test func comingBackCancelsTheHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short, hoverOpen: Self.never)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Click

    @Test func clickExpandsTheCompactIsland() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.click()
        #expect(fsm.state == .home)
        #expect(log.transitions == [[.hidden, .petit], [.petit, .home]])
    }

    @Test func clickIsIgnoredOutsideTheCompactState() {
        let (hidden, _) = makeFSM()
        hidden.click()
        #expect(hidden.state == .hidden)

        let (greeting, _) = makeFSM()
        greeting.launch()
        greeting.click()
        #expect(greeting.state == .greeting)

        let (home, log) = makeFSM()
        home.mouseEntered()
        home.click()
        home.click()
        #expect(home.state == .home)
        #expect(log.transitions.count == 2)
    }

    @Test func clickCancelsAPendingHide() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.click()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Expanded island

    @Test func expandedIslandCollapsesAfterTheMouseLeaves() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        fsm.mouseLeft()
        #expect(fsm.state == .home)
        #expect(await reaches(.petit, fsm))
    }

    @Test func expandedIslandStaysWhileHovered() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func comingBackCancelsTheCollapse() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.click()
        fsm.mouseLeft()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Greeting

    @Test func greetingEndsWhenTheLaunchSequenceDoes() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        fsm.greetComplete()
        #expect(fsm.state == .petit)
        #expect(log.transitions == [[.hidden, .greeting], [.greeting, .petit]])
    }

    @Test func greetingStaysUntilTheLaunchSequenceEnds() async {
        let (fsm, _) = makeFSM()
        fsm.launch()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .greeting)
    }

    @Test func greetCompleteIsIgnoredOutsideTheGreeting() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.greetComplete()
        #expect(fsm.state == .petit)
        #expect(log.transitions.count == 1)
    }

    @Test func thePointerDoesNotInterruptTheGreeting() {
        let (fsm, log) = makeFSM()
        fsm.launch()
        fsm.mouseEntered()
        #expect(fsm.state == .greeting)
        fsm.mouseLeft()
        #expect(fsm.state == .greeting)
        #expect(log.transitions == [[.hidden, .greeting]])
    }

    @Test func aStuckGreetingEndsByItself() async {
        let (fsm, log) = makeFSM(greetTimeout: Self.short)
        fsm.launch()
        #expect(await reaches(.petit, fsm))
        #expect(log.transitions == [[.hidden, .greeting], [.greeting, .petit]])
    }

    @Test func compactIslandHidesAfterTheGreetingWhenNotHovered() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.launch()
        fsm.greetComplete()
        #expect(await reaches(.hidden, fsm))
    }

    @Test func compactIslandStaysAfterTheGreetingWhileHovered() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.launch()
        fsm.mouseEntered()
        fsm.greetComplete()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Opening without a click (alert, shortcut, file drag)

    @Test func openWorksFromEveryState() {
        let (hidden, log) = makeFSM()
        hidden.open()
        #expect(hidden.state == .home)
        #expect(log.transitions == [[.hidden, .home]])

        let (petit, _) = makeFSM()
        petit.mouseEntered()
        petit.open()
        #expect(petit.state == .home)

        let (greeting, _) = makeFSM()
        greeting.launch()
        greeting.open()
        #expect(greeting.state == .home)
    }

    @Test func openingAgainReportsNothing() {
        let (fsm, log) = makeFSM()
        fsm.open()
        fsm.open()
        #expect(log.transitions.count == 1)
    }

    @Test func anIslandOpenedByItselfClosesWhenNobodyIsThere() async {
        let (fsm, log) = makeFSM(homeToPetit: Self.short)
        fsm.open()
        #expect(await reaches(.petit, fsm))
        #expect(log.transitions == [[.hidden, .home], [.home, .petit]])
    }

    @Test func anIslandOpenedByItselfStaysWhileHovered() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.open()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func aStuckGreetingTimerDoesNotCloseAnAlert() async {
        let (fsm, _) = makeFSM(greetTimeout: Self.short)
        fsm.launch()
        fsm.open()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Pinned (an alert waits for an answer)

    @Test func aPinnedIslandNeverClosesByItself() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.pinned = true
        fsm.open()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)

        fsm.mouseEntered()
        fsm.mouseLeft()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func pinningCancelsAPendingCollapse() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.open()
        fsm.pinned = true
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func unpinningLetsTheIslandCloseAgain() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.pinned = true
        fsm.open()
        fsm.pinned = false
        #expect(await reaches(.petit, fsm))
    }

    @Test func unpinningWhileHoveredKeepsTheIslandOpen() async {
        let (fsm, _) = makeFSM(homeToPetit: Self.short)
        fsm.mouseEntered()
        fsm.pinned = true
        fsm.open()
        fsm.pinned = false
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    // MARK: – Explicit collapse (Escape, OK button)

    @Test func collapseFoldsTheOpenIsland() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.click()
        fsm.collapse()
        #expect(fsm.state == .petit)
        #expect(log.transitions == [[.hidden, .petit], [.petit, .home], [.home, .petit]])
    }

    @Test func collapseIsIgnoredOutsideTheOpenState() {
        let (hidden, _) = makeFSM()
        hidden.collapse()
        #expect(hidden.state == .hidden)

        let (greeting, _) = makeFSM()
        greeting.launch()
        greeting.collapse()
        #expect(greeting.state == .greeting)
    }

    @Test func aCollapsedIslandHidesWhenNobodyIsThere() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.open()
        fsm.collapse()
        #expect(fsm.state == .petit)
        #expect(await reaches(.hidden, fsm))
    }

    @Test func aCollapsedIslandStaysWhileHovered() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.click()
        fsm.collapse()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Reveal

    @Test func revealShowsTheCompactIslandThenHidesIt() async {
        let (fsm, log) = makeFSM(petitToHidden: Self.short)
        fsm.reveal()
        #expect(fsm.state == .petit)
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [[.hidden, .petit], [.petit, .hidden]])
    }

    @Test func revealIsIgnoredWhenTheIslandIsVisible() {
        let (fsm, log) = makeFSM()
        fsm.mouseEntered()
        fsm.click()
        fsm.reveal()
        #expect(fsm.state == .home)
        #expect(log.transitions.count == 2)
    }

    @Test func hoveringARevealedIslandKeepsItOpen() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short, hoverOpen: Self.never)
        fsm.reveal()
        fsm.mouseEntered()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    // MARK: – Timers

    @Test func cancelTimersStopsEveryPendingTransition() async {
        let (fsm, _) = makeFSM(petitToHidden: Self.short)
        fsm.mouseEntered()
        fsm.mouseLeft()
        fsm.cancelTimers()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .petit)
    }

    @Test func fullCycleReportsEveryTransitionInOrder() async {
        let (fsm, log) = makeFSM(homeToPetit: Self.short, petitToHidden: Self.short)
        fsm.launch()
        fsm.mouseEntered()
        fsm.greetComplete()
        #expect(fsm.state == .petit)
        fsm.click()
        fsm.mouseLeft()
        #expect(await reaches(.petit, fsm))
        #expect(await reaches(.hidden, fsm))
        #expect(log.transitions == [
            [.hidden, .greeting],
            [.greeting, .petit],
            [.petit, .home],
            [.home, .petit],
            [.petit, .hidden],
        ])
    }
}

// MARK: – The folded island: what is live

@Suite struct FoldedIslandTests {

    private func module(_ id: String, live priority: Int? = nil, text: String = "…") -> ModuleSnapshot {
        ModuleSnapshot(id: id, name: id, colorHex: "#FFFFFF", status: "", title: "", subtitle: "",
                       primaryAction: "Voir", secondaryAction: nil,
                       live: priority.map { ModuleLive(text: text, priority: $0) })
    }

    @Test func nothingLiveShowsNothing() {
        #expect(FoldedIsland.live(in: [], shown: nil) == nil)
        #expect(FoldedIsland.live(in: [module("agenda"), module("music")], shown: "music") == nil)
    }

    @Test func theHighestPriorityWins() {
        let modules = [
            module("agenda", live: ModuleLivePriority.ambient),
            module("music", live: ModuleLivePriority.activity),
            module("claude-code", live: ModuleLivePriority.attention),
            module("weather"),
        ]
        #expect(FoldedIsland.live(in: modules, shown: nil)?.id == "claude-code")
        #expect(FoldedIsland.live(in: modules, shown: "music")?.id == "claude-code")
    }

    @Test func atEqualPriorityTheOneShownStays() {
        let modules = [
            module("focus", live: ModuleLivePriority.activity),
            module("music", live: ModuleLivePriority.activity),
        ]
        #expect(FoldedIsland.live(in: modules, shown: "music")?.id == "music")
        #expect(FoldedIsland.live(in: modules, shown: "focus")?.id == "focus")
    }

    @Test func atEqualPriorityTheFirstInOrderIsTakenWhenNoneWasShown() {
        let modules = [
            module("focus", live: ModuleLivePriority.activity),
            module("music", live: ModuleLivePriority.activity),
        ]
        #expect(FoldedIsland.live(in: modules, shown: nil)?.id == "focus")
        #expect(FoldedIsland.live(in: modules, shown: "agenda")?.id == "focus")
    }

    @Test func theOneShownGivesWayToAHigherPriority() {
        let modules = [
            module("agenda", live: ModuleLivePriority.ambient),
            module("music", live: ModuleLivePriority.activity),
        ]
        #expect(FoldedIsland.live(in: modules, shown: "agenda")?.id == "music")
    }

    @Test func theOneShownIsReplacedOnceItIsNoLongerLive() {
        let modules = [module("music"), module("agenda", live: ModuleLivePriority.ambient)]
        #expect(FoldedIsland.live(in: modules, shown: "music")?.id == "agenda")
    }

    @Test func aNewTrackIsANewLineButACountdownIsNot() {
        #expect(FoldedIsland.isNewLine("Lueur · Halo Nord", "Marée basse · Halo Nord"))
        #expect(!FoldedIsland.isNewLine("18:42", "18:41"))
        #expect(!FoldedIsland.isNewLine("Pause 04:59", "Pause 04:58"))
        #expect(FoldedIsland.isNewLine("18:42", "18:41 en pause"))
        #expect(!FoldedIsland.isNewLine("Lueur · Halo Nord", "Lueur · Halo Nord"))
    }

    @Test func theEarFitsItsContent() {
        #expect(FoldedIsland.ear(content: 140, minimum: 80, notchWidth: 184, openWidth: 660) == 140)
    }

    @Test func theEarIsNeverNarrowerThanTheMockUp() {
        #expect(FoldedIsland.ear(content: 0, minimum: 80, notchWidth: 184, openWidth: 660) == 80)
        #expect(FoldedIsland.ear(content: 42, minimum: 80, notchWidth: 184, openWidth: 660) == 80)
    }

    @Test func theFoldedIslandIsNeverWiderThanTheOpenOne() {
        for content in stride(from: 0.0, through: 2000, by: 37) {
            let ear = FoldedIsland.ear(content: content, minimum: 80, notchWidth: 184, openWidth: 660)
            #expect(184 + 2 * ear <= 660)
        }
        // An open island narrower than the folded minimum: the minimum still holds
        #expect(FoldedIsland.ear(content: 500, minimum: 80, notchWidth: 184, openWidth: 300) == 80)
    }
}

// MARK: – The chat answering live

@Suite struct LiveChatTests {

    @Test func aReaderAtTheBottomFollowsTheAnswer() {
        #expect(LiveChat.followsBottom(offset: 200, viewport: 170, content: 370))
        #expect(LiveChat.followsBottom(offset: 195, viewport: 170, content: 370))
    }

    @Test func aReaderWhoScrolledUpIsLeftAlone() {
        #expect(!LiveChat.followsBottom(offset: 40, viewport: 170, content: 370))
        #expect(!LiveChat.followsBottom(offset: 0, viewport: 170, content: 370))
    }

    @Test func aConversationShorterThanItsViewAlwaysFollows() {
        #expect(LiveChat.followsBottom(offset: 0, viewport: 170, content: 60))
        #expect(LiveChat.followsBottom(offset: 0, viewport: 170, content: 170))
    }

    @Test func anAnswerThatWroteOrEditedSomethingIsCelebrated() {
        #expect(LiveChat.celebrates(done: [("reading", true), ("writing", true)]))
        #expect(LiveChat.celebrates(done: [("editing", true)]))
    }

    @Test func anAnswerThatOnlyReadOrRanIsNot() {
        #expect(!LiveChat.celebrates(done: []))
        #expect(!LiveChat.celebrates(done: [("reading", true), ("running", true), ("searching", true)]))
    }

    @Test func aFailedWriteIsNotCelebrated() {
        #expect(!LiveChat.celebrates(done: [("writing", false), ("editing", false)]))
        #expect(LiveChat.celebrates(done: [("writing", false), ("editing", true)]))
    }
}

// MARK: – The fold delay of the settings, and leaving

@Suite @MainActor struct IslandFoldSettingTests {
    typealias State = IslandStateMachine.State
    static let short: TimeInterval = 0.05
    static let settle: Duration = .milliseconds(250)

    private func reaches(_ expected: State, _ fsm: IslandStateMachine, timeout: TimeInterval = 5) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while fsm.state != expected {
            if Date() > deadline { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test func withNeverTheOpenIslandStaysOpen() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = Self.short
        fsm.foldsByItself = false
        fsm.open()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)

        fsm.mouseEntered()
        fsm.mouseLeft()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func choosingNeverCancelsACountdown() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = Self.short
        fsm.open()
        fsm.foldsByItself = false
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func choosingADelayAgainFoldsTheIsland() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = Self.short
        fsm.foldsByItself = false
        fsm.open()
        fsm.foldsByItself = true
        #expect(await reaches(.petit, fsm))
    }

    @Test func choosingADelayWhileHoveredDoesNotFold() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = Self.short
        fsm.foldsByItself = false
        fsm.mouseEntered()
        fsm.open()
        fsm.foldsByItself = true
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func neverStillFoldsWhenAsked() {
        let fsm = IslandStateMachine()
        fsm.foldsByItself = false
        fsm.open()
        fsm.collapse()
        #expect(fsm.state == .petit)
    }

    @Test func aShorterDelayAppliesToTheCountdownAlreadyRunning() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = 60
        fsm.open()
        fsm.homeToPetitDelay = Self.short
        #expect(await reaches(.petit, fsm))
    }

    @Test func aNewDelayDoesNotStartACountdownWhileHovered() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = 60
        fsm.mouseEntered()
        fsm.open()
        fsm.homeToPetitDelay = Self.short
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .home)
    }

    @Test func leavingTakesOverFromEveryState() {
        for prepare in [{ (_: IslandStateMachine) in }, { $0.mouseEntered() }, { $0.open() }, { $0.launch() }] {
            let fsm = IslandStateMachine()
            prepare(fsm)
            fsm.leave()
            #expect(fsm.state == .greeting)
        }
    }

    @Test func nothingInterruptsTheGoodbye() async {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = Self.short
        fsm.petitToHiddenDelay = Self.short
        fsm.greetingTimeout = Self.short
        fsm.open()
        fsm.mouseLeft()
        fsm.leave()
        fsm.mouseEntered()
        fsm.click()
        fsm.mouseLeft()
        fsm.reveal()
        fsm.collapse()
        try? await Task.sleep(for: Self.settle)
        #expect(fsm.state == .greeting)
    }
}

// MARK: – The bubble of the second activity

@Suite struct FoldedBubbleTests {
    private func module(_ id: String, live priority: Int? = nil) -> ModuleSnapshot {
        ModuleSnapshot(id: id, name: id, colorHex: "#FFFFFF", status: "", title: "", subtitle: "",
                       primaryAction: "Voir", secondaryAction: nil,
                       live: priority.map { ModuleLive(text: "…", priority: $0) })
    }

    @Test func theSecondActivityIsTheNextHighestPriority() {
        let modules = [
            module("agenda", live: ModuleLivePriority.ambient),
            module("music", live: ModuleLivePriority.activity),
            module("claude-code", live: ModuleLivePriority.attention),
        ]
        #expect(FoldedIsland.second(in: modules, after: "claude-code")?.id == "music")
        #expect(FoldedIsland.second(in: modules, after: "music")?.id == "claude-code")
    }

    @Test func aSingleLiveModuleLeavesNoBubble() {
        let modules = [module("agenda"), module("music", live: ModuleLivePriority.activity)]
        #expect(FoldedIsland.second(in: modules, after: "music") == nil)
    }

    @Test func nothingLiveLeavesNoBubble() {
        #expect(FoldedIsland.second(in: [module("agenda"), module("music")], after: nil) == nil)
        #expect(FoldedIsland.second(in: [module("agenda", live: ModuleLivePriority.ambient)], after: nil) == nil)
    }
}

// MARK: – Asking the first name

@Suite struct FirstNameTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func heAsksWhenHeDoesNotKnowIt() {
        #expect(FirstName.shouldAsk(name: nil, lastAsked: nil, now: now))
        #expect(FirstName.shouldAsk(name: "", lastAsked: nil, now: now))
        #expect(FirstName.shouldAsk(name: "   ", lastAsked: nil, now: now))
    }

    @Test func heDoesNotAskWhenHeKnowsIt() {
        #expect(!FirstName.shouldAsk(name: "Esteban", lastAsked: nil, now: now))
        #expect(!FirstName.shouldAsk(name: "Esteban", lastAsked: now.addingTimeInterval(-90 * 24 * 3600), now: now))
    }

    @Test func passedOverHeDoesNotInsist() {
        #expect(!FirstName.shouldAsk(name: nil, lastAsked: now.addingTimeInterval(-60), now: now))
        #expect(!FirstName.shouldAsk(name: nil, lastAsked: now.addingTimeInterval(-2 * 24 * 3600), now: now))
    }

    @Test func heAsksAgainLater() {
        #expect(FirstName.shouldAsk(name: nil, lastAsked: now.addingTimeInterval(-FirstName.patience), now: now))
        #expect(FirstName.shouldAsk(name: nil, lastAsked: now.addingTimeInterval(-10 * 24 * 3600), now: now))
    }

    @Test func whatIsTypedBecomesAFirstName() {
        #expect(FirstName.clean("  Esteban ") == "Esteban")
        #expect(FirstName.clean("Marie-Lou\nautre chose") == "Marie-Lou")
        #expect(FirstName.clean("") == nil)
        #expect(FirstName.clean("  \n ") == nil)
        #expect(FirstName.clean(String(repeating: "a", count: 200))?.count == 40)
    }
}

// MARK: – Yumi's voice

@Suite struct IslandVoiceTests {
    @Test func smallNumbersAreWrittenInLetters() {
        #expect(Voice.number(2) == "deux")
        #expect(Voice.number(12) == "douze")
        #expect(Voice.number(26) == "vingt-six")
        #expect(Voice.number(250) == "250")
    }

    @Test func durationsReadLikeASentence() {
        #expect(Voice.duration(20) == "moins d'une minute")
        #expect(Voice.duration(60) == "une minute")
        #expect(Voice.duration(12 * 60 + 40) == "douze minutes")
        #expect(Voice.duration(21 * 60) == "vingt et une minutes")
        #expect(Voice.duration(3600) == "une heure")
        #expect(Voice.duration(2 * 3600 + 10 * 60) == "deux heures dix")
    }

    @Test func filesAreCountedInLetters() {
        #expect(Voice.files(0) == nil)
        #expect(Voice.files(1) == "un fichier touché")
        #expect(Voice.files(3) == "trois fichiers touchés")
    }

    @Test func aSentenceStartsWithACapital() {
        #expect(Voice.sentence("depuis douze minutes") == "Depuis douze minutes")
        #expect(Voice.sentence("") == "")
    }

    @Test func theFirstNameIsUsedOnlyWhenKnown() {
        #expect(Voice.goodbye(name: nil) == "À tout à l'heure")
        #expect(Voice.goodbye(name: "  ") == "À tout à l'heure")
        #expect(Voice.goodbye(name: "Esteban") == "À tout à l'heure, Esteban")
    }
}

// MARK: – When Yumi speaks first

@Suite struct SpeakTests {
    @Test func aShortSentenceFitsOnOneLine() {
        let size = Speak.size(text: 200, action: 0, minimum: 100)
        #expect(size.lines == 1)
        #expect(size.band == Speak.oneLine)
        #expect(size.textWidth == 200)
        #expect(size.width == Speak.lead + 200 + Speak.cross + Speak.trail)
    }

    @Test func aLongSentenceTakesTwoLinesAndStaysNarrow() {
        let size = Speak.size(text: 600, action: 0, minimum: 100)
        #expect(size.lines == 2)
        #expect(size.band == Speak.twoLines)
        #expect(size.textWidth <= Speak.textMax)
        #expect(size.textWidth * 2 >= 600)
    }

    @Test func anActionMakesRoomForItsButton() {
        let without = Speak.size(text: 200, action: 0, minimum: 100)
        let with = Speak.size(text: 200, action: 50, minimum: 100)
        #expect(with.width == without.width + 60)
    }

    @Test func theIslandIsNeverNarrowerThanFolded() {
        #expect(Speak.size(text: 20, action: 0, minimum: 345).width == 345)
    }

    @Test func theIslandNeverGrowsPastItsLimit() {
        for text in stride(from: 0.0, through: 5000, by: 113) {
            let size = Speak.size(text: text, action: 80, minimum: 100)
            #expect(size.width <= Speak.lead + Speak.textMax + 90 + Speak.cross + Speak.trail)
        }
    }
}

// MARK: – GitHub

@Suite struct GitHubFiguresTests {
    @Test func threeFiguresAreRead() {
        #expect(GitHubFigures.parse("128 · 12 · 3") == .init(stars: "128", forks: "12", pulls: "3"))
        #expect(GitHubFigures.parse("0·0·0") == .init(stars: "0", forks: "0", pulls: "0"))
        #expect(GitHubFigures.parse("1,2 k · 40 · 7") == .init(stars: "1,2 k", forks: "40", pulls: "7"))
    }

    @Test func anythingElseIsLeftAsItIs() {
        #expect(GitHubFigures.parse("") == nil)
        #expect(GitHubFigures.parse("2 PR") == nil)
        #expect(GitHubFigures.parse("128 · 12") == nil)
        #expect(GitHubFigures.parse("à brancher · · ") == nil)
        #expect(GitHubFigures.parse("un · deux · trois") == nil)
    }

    @Test func aPastedTokenLosesWhatSurroundsIt() {
        #expect(GitHubFigures.cleanToken("  ghp_abc123\n") == "ghp_abc123")
        #expect(GitHubFigures.cleanToken("") == nil)
        #expect(GitHubFigures.cleanToken(" \n ") == nil)
    }
}

@Suite struct RowTimeTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    @Test func sessionsSaySinceWhen() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(RowTime.elapsed(since: now.addingTimeInterval(-20), now: now) == "à l'instant")
        #expect(RowTime.elapsed(since: now.addingTimeInterval(-12 * 60), now: now) == "12 min")
        #expect(RowTime.elapsed(since: now.addingTimeInterval(-65 * 60), now: now) == "1 h 05")
    }

    @Test func eventsSayWhen() {
        let now = try! Date("2026-10-03T14:00:00+02:00", strategy: .iso8601)
        #expect(RowTime.clock(try! Date("2026-10-03T09:05:00+02:00", strategy: .iso8601), now: now, calendar: calendar) == "09:05")
        #expect(RowTime.clock(try! Date("2026-10-02T22:00:00+02:00", strategy: .iso8601), now: now, calendar: calendar) == "hier")
        #expect(RowTime.clock(try! Date("2026-09-28T10:00:00+02:00", strategy: .iso8601), now: now, calendar: calendar) == "28 sept.")
    }
}

@Suite struct YumiVersionTests {
    private func v(_ text: String) -> YumiVersion { YumiVersion(text)! }

    @Test func preReleasesComeBeforeTheirRelease() {
        #expect(v("0.1.0-alpha") < v("0.1.0-alpha.2"))
        #expect(v("0.1.0-alpha.2") < v("0.1.0"))
        #expect(v("0.1.0-alpha") < v("0.1.0"))
        #expect(v("0.1.0-alpha.2") < v("0.1.0-alpha.10"))
        #expect(v("0.1.0-alpha.9") < v("0.1.0-beta"))
        #expect(v("0.1.0") < v("0.1.1-alpha"))
        #expect(v("0.9.9") < v("0.10.0"))
    }

    @Test func tagsAreRead() {
        #expect(v("v0.1.0-alpha") == v("0.1.0-alpha"))
        #expect(v("0.2") == v("0.2.0"))
        #expect(!(v("0.1.0-alpha") < v("v0.1.0-alpha")))
        #expect(YumiVersion("nightly") == nil)
        #expect(YumiVersion("") == nil)
    }
}

@Suite struct FeedbackTests {
    @Test func theFormIsFilledWithTheMacAndNothingElse() {
        let url = Feedback.url(version: "0.1.0-alpha", macOS: "26.1.0", model: "Mac15,3", notch: true)!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(url.absoluteString.hasPrefix("https://github.com/estebanbaigts/Yumi/issues/new?"))
        #expect(items.map(\.name) == ["template", "version-yumi", "version-macos", "mac"])
        #expect(items.map(\.value) == ["bug.yml", "0.1.0-alpha", "26.1.0", "Mac15,3, notch : oui"])
        #expect(Feedback.fields(version: "1", macOS: "2", model: "Mac14,2", notch: false).last?.1 == "Mac14,2, notch : non")
    }

    @Test func theFormWithoutAccountCarriesOnlyTheVersion() {
        let url = Feedback.formURL(version: "0.1.0-alpha.5")!
        #expect(url.absoluteString == "https://tally.so/r/Me9lvA?version=0.1.0-alpha.5")
    }
}

@Suite struct SettingsPageTests {
    @Test func theDeveloperPageIsHiddenUntilAskedFor() {
        #expect(!SettingsPage.sidebar(developer: false).contains(.developer))
        #expect(SettingsPage.sidebar(developer: true).last == .developer)
        #expect(SettingsPage.sidebar(developer: false).first == .general)
        #expect(SettingsPage.shown(.developer, developer: false) == .general)
        #expect(SettingsPage.shown(.developer, developer: true) == .developer)
        #expect(SettingsPage.shown(nil, developer: true) == .general)
    }

    @Test func everySettingOfTheOldWindowHasOnePage() {
        let old = ["soundEnabled", "soundVolume", "autoCloseInterval", "absenceInterval", "hotkeyEnabled", "hotkeyFlags",
                   "hotkeyCode", "contextEngineEnabled",
                   "workHabit", "claudeDirectoryBookmark", "github-token", "launchAtStartup",
                   "hooks", "engineSettings", "engineKeys", "yumiPermissions", "contextPanel", "agentPanel",
                   // Until now only in the island
                   "yumiTalk", "updateCheckEnabled", "feedback", "memory"]
        let placed = SettingsPage.allCases.flatMap { SettingsPage.settings[$0] ?? [] }
        for key in old { #expect(placed.filter { $0 == key }.count == 1, "\(key)") }
        // The old integrations are gone: none of their settings is shown anywhere.
        let retired = ["vercelProjectFilter", "n8nWorkflowFilter", "activeIntegrations", "resend-api-key", "resend-from", "n8n-url",
                       "n8n-api-key", "vercel-token", "stripe-api-key", "calcom-api-key", "notion-api-key"]
        for key in retired { #expect(!placed.contains(key), "\(key)") }
        #expect(Set(placed).count == placed.count)
    }

    @Test func everyPageHasANameAndASymbol() {
        for page in SettingsPage.allCases {
            #expect(!page.title.isEmpty)
            #expect(!page.symbol.isEmpty)
        }
    }
}

@Suite struct ReachingYumiTests {
    private func press(_ detector: inout TripleShift, at time: TimeInterval) -> Bool {
        _ = detector.modifiers(shift: true, others: false, at: time)
        return detector.modifiers(shift: false, others: false, at: time + 0.05)
    }

    @Test func threeQuickShiftsOpenTheIsland() {
        var detector = TripleShift()
        let r1 = press(&detector, at: 0)
        #expect(!r1)
        let r2 = press(&detector, at: 0.2)
        #expect(!r2)
        let r3 = press(&detector, at: 0.4)
        #expect(r3)
        // It starts again from zero
        let r4 = press(&detector, at: 0.6)
        #expect(!r4)
    }

    @Test func slowShiftsOrShiftWithAKeyDoNot() {
        var slow = TripleShift()
        let r5 = press(&slow, at: 0)
        #expect(!r5)
        let r6 = press(&slow, at: 0.5)
        #expect(!r6)
        let r7 = press(&slow, at: 1.2)
        #expect(!r7)
        var typing = TripleShift()
        let r8 = press(&typing, at: 0)
        #expect(!r8)
        let r9 = press(&typing, at: 0.1)
        #expect(!r9)
        _ = typing.modifiers(shift: true, others: false, at: 0.2)
        typing.keyTyped()   // Shift+A: a capital letter
        let r10 = typing.modifiers(shift: false, others: false, at: 0.25)
        #expect(!r10)
        var combo = TripleShift()
        let r11 = press(&combo, at: 0)
        #expect(!r11)
        _ = combo.modifiers(shift: true, others: true, at: 0.1)   // ⌘⇧
        let r12 = combo.modifiers(shift: false, others: false, at: 0.15)
        #expect(!r12)
        let r13 = press(&combo, at: 0.2)
        #expect(!r13)
    }

    @Test func openingSettingsFoldsTheIslandUnlessAnApprovalWaits() {
        #expect(SettingsOpening.foldsIsland(approvalPending: false))
        #expect(!SettingsOpening.foldsIsland(approvalPending: true))
    }

    @Test func theSettingsWindowStartsUnderTheMenuBarAndTheIsland() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)   // under the menu bar
        let size = CGSize(width: 760, height: 600)
        let free = SettingsOpening.frame(size: size, visible: visible, islandBottom: nil)
        #expect(free.maxY <= visible.maxY)
        #expect(free.midX == visible.midX)
        #expect(free.size == size)
        let below = SettingsOpening.frame(size: size, visible: visible, islandBottom: 700)
        #expect(below.maxY <= 700)
        #expect(below.minY >= visible.minY)
        #expect(below.maxY == 688)
    }

    @Test func aClickOutsideFoldsUnlessSomethingWaits() {
        #expect(OutsideClick.folds(islandOpen: true, insideIsland: false, approvalPending: false, unsentDraft: false, pinned: false))
        #expect(!OutsideClick.folds(islandOpen: true, insideIsland: true, approvalPending: false, unsentDraft: false, pinned: false))
        #expect(!OutsideClick.folds(islandOpen: true, insideIsland: false, approvalPending: true, unsentDraft: false, pinned: false))
        #expect(!OutsideClick.folds(islandOpen: true, insideIsland: false, approvalPending: false, unsentDraft: true, pinned: false))
        #expect(!OutsideClick.folds(islandOpen: false, insideIsland: false, approvalPending: false, unsentDraft: false, pinned: false))
        #expect(!OutsideClick.folds(islandOpen: true, insideIsland: false, approvalPending: false, unsentDraft: false, pinned: true))
    }

    @Test func theHooksAreOfferedOnceWhenClaudeCodeIsThereWithoutThem() {
        #expect(HookOffer.offers(claudeCodeInstalled: true, hooksInstalled: false, alreadyOffered: false, filming: false))
        #expect(!HookOffer.offers(claudeCodeInstalled: false, hooksInstalled: false, alreadyOffered: false, filming: false))
        #expect(!HookOffer.offers(claudeCodeInstalled: true, hooksInstalled: true, alreadyOffered: false, filming: false))
        #expect(!HookOffer.offers(claudeCodeInstalled: true, hooksInstalled: false, alreadyOffered: true, filming: false))
        #expect(!HookOffer.offers(claudeCodeInstalled: true, hooksInstalled: false, alreadyOffered: false, filming: true))
    }
}
