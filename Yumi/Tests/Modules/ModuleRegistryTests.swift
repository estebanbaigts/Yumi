import Testing
import Foundation

@MainActor
private final class FakeModule: YumiModule {
    let id: String
    var status = "0"
    var starts = 0, stops = 0
    var actions: [ModuleAction] = []
    var received = 0
    var onChange: (@MainActor () -> Void)?

    init(_ id: String) { self.id = id }

    var snapshot: ModuleSnapshot {
        ModuleSnapshot(id: id, name: id, colorHex: "#FFFFFF", status: status, title: "", subtitle: "", primaryAction: "Voir")
    }
    func start(onChange: @escaping @MainActor () -> Void) { starts += 1; self.onChange = onChange }
    func stop() { stops += 1; onChange = nil }
    func perform(_ action: ModuleAction) { actions.append(action) }
    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) { received += 1 }
}

@MainActor
@Suite struct ModuleRegistryTests {

    private func makeDefaults() -> UserDefaults {
        let name = "yumi.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theProfilesOfTheFirstLaunchApplyOnceAndNeverOverAChoice() {
        let defaults = makeDefaults()
        let modules = ["claude-code", "github", "gmail", "agenda", "notes", "weather"].map(FakeModule.init)
        let registry = ModuleRegistry(modules: modules, defaults: defaults) { _ in }
        #expect(!ModuleRegistry.modulesWereChosen(in: defaults))
        registry.adoptProfiles(["gmail", "agenda", "notes", "unknown"])
        #expect(registry.selection.ids == ["gmail", "agenda", "notes"])
        #expect(ModuleRegistry.modulesWereChosen(in: defaults))
        // A second time (a first name asked again later): the choice stays.
        registry.adoptProfiles(["claude-code", "github"])
        #expect(registry.selection.ids == ["gmail", "agenda", "notes"])
    }

    @Test func startsOnlyTheSelectedModulesAndPublishesInSelectionOrder() {
        let defaults = makeDefaults()
        defaults.set(["focus", "claude-code"], forKey: "selectedModules")
        let claude = FakeModule("claude-code"), focus = FakeModule("focus"), weather = FakeModule("weather")
        var published: [[String]] = []
        let registry = ModuleRegistry(modules: [claude, focus, weather], defaults: defaults) { published.append($0.map(\.id)) }

        registry.start()

        #expect(claude.starts == 1 && focus.starts == 1 && weather.starts == 0)
        #expect(published == [["focus", "claude-code"]])
    }

    @Test func firstLaunchSelectsTheDefaultModulesThatExist() {
        let registry = ModuleRegistry(modules: [FakeModule("weather"), FakeModule("claude-code")], defaults: makeDefaults()) { _ in }
        #expect(registry.selection.ids == ["claude-code", "weather"])
    }

    @Test func deselectingStopsTheModuleAndSelectingStartsItAgain() {
        let defaults = makeDefaults()
        let focus = FakeModule("focus")
        var last: [String] = []
        let registry = ModuleRegistry(modules: [focus], defaults: defaults) { last = $0.map(\.id) }
        registry.start()

        #expect(registry.setSelected("focus", false))
        #expect(focus.stops == 1)
        #expect(last.isEmpty)
        #expect(defaults.stringArray(forKey: "selectedModules") == [])

        #expect(registry.setSelected("focus", true))
        #expect(focus.starts == 2)
        #expect(last == ["focus"])
        #expect(!registry.setSelected("unknown", true))
    }

    @Test func publishesWhenAModuleReportsAChangeAndOnlyThen() {
        let focus = FakeModule("focus")
        var count = 0
        var lastStatus = ""
        let registry = ModuleRegistry(modules: [focus], defaults: makeDefaults()) { count += 1; lastStatus = $0.first?.status ?? "" }
        registry.start()
        #expect(count == 1)

        focus.onChange?()
        #expect(count == 1)

        focus.status = "24:59"
        focus.onChange?()
        #expect(count == 2)
        #expect(lastStatus == "24:59")
    }

    @Test func actionsAndEventsReachOnlyRunningModules() {
        let defaults = makeDefaults()
        defaults.set(["focus"], forKey: "selectedModules")
        let focus = FakeModule("focus"), weather = FakeModule("weather")
        let registry = ModuleRegistry(modules: [focus, weather], defaults: defaults) { _ in }
        registry.start()

        registry.perform(.primary, on: "focus")
        registry.perform(.secondary, on: "weather")
        registry.receive(.taskCompleted(SessionID("s")), sessions: [:])

        #expect(focus.actions == [.primary])
        #expect(weather.actions.isEmpty)
        #expect(focus.received == 1 && weather.received == 0)
    }

    @Test func theIslandNotificationTriggersTheAction() {
        let focus = FakeModule("focus")
        let registry = ModuleRegistry(modules: [focus], defaults: makeDefaults()) { _ in }
        registry.start()

        NotificationCenter.default.post(name: .moduleAction, object: nil, userInfo: ["module": "focus", "action": "secondary"])
        NotificationCenter.default.post(name: .moduleAction, object: nil, userInfo: ["module": "focus", "action": "bogus"])

        #expect(focus.actions == [.secondary])
        registry.stop()
        NotificationCenter.default.post(name: .moduleAction, object: nil, userInfo: ["module": "focus", "action": "primary"])
        #expect(focus.actions == [.secondary])
        #expect(focus.stops == 1)
    }

    @Test func movingAModuleChangesTheOrder() {
        let defaults = makeDefaults()
        defaults.set(["a", "b", "c"], forKey: "selectedModules")
        var last: [String] = []
        let registry = ModuleRegistry(modules: [FakeModule("a"), FakeModule("b"), FakeModule("c")], defaults: defaults) { last = $0.map(\.id) }
        registry.start()
        registry.move("c", to: 0)
        #expect(last == ["c", "a", "b"])
    }
}

@Suite struct ModuleSelectionTests {
    @Test func storedSelectionDropsUnknownAndDuplicateModules() {
        let selection = ModuleSelection(stored: ["focus", "gone", "focus", "weather"], available: ["weather", "focus"])
        #expect(selection.ids == ["focus", "weather"])
    }

    @Test func selectionIsCapped() {
        let all = (0..<15).map { "m\($0)" }
        var selection = ModuleSelection(stored: all, available: all)
        #expect(selection.ids.count == ModuleCatalog.selectionLimit)
        let refused = selection.select("m14", available: all)
        let removed = selection.deselect("m0")
        let accepted = selection.select("m14", available: all)
        let removedTwice = selection.deselect("m0")
        #expect(!refused && removed && accepted && !removedTwice)
    }

    @Test func moveClampsTheIndex() {
        var selection = ModuleSelection(stored: ["a", "b", "c"], available: ["a", "b", "c"])
        selection.move("a", to: 99)
        #expect(selection.ids == ["b", "c", "a"])
        selection.move("a", to: -3)
        #expect(selection.ids == ["a", "b", "c"])
    }
}
