import Foundation

/// Owns the modules, starts the selected ones, stops the others, and hands their
/// snapshots, in selection order, to whoever displays them (`AppState.modules`).
@MainActor
final class ModuleRegistry {
    private static let selectionKey = "selectedModules"
    private static let knownKey = "knownModules"

    private let defaults: UserDefaults
    private let modules: [any YumiModule]
    private let onPublish: @MainActor ([ModuleSnapshot]) -> Void
    private var running: Set<String> = []
    private var published: [ModuleSnapshot]?
    private var actionObserver: NSObjectProtocol?
    private var profilesObserver: NSObjectProtocol?
    /// The views' copy of the lineup, kept up to date.
    private weak var shared: ModuleLineup?

    private(set) var selection: ModuleSelection

    /// - Parameter onPublish: receives the snapshots each time they really change.
    init(modules: [any YumiModule], defaults: UserDefaults = .standard,
         onPublish: @escaping @MainActor ([ModuleSnapshot]) -> Void) {
        self.modules = modules
        self.defaults = defaults
        self.onPublish = onPublish
        let stored = defaults.stringArray(forKey: Self.selectionKey)
        selection = ModuleSelection(stored: stored, available: modules.map(\.id))
        // A module added by an update joins a selection saved before it existed, once.
        let known = selection.welcome(available: modules.map(\.id),
                                      known: stored == nil ? nil : defaults.stringArray(forKey: Self.knownKey) ?? ModuleSelection.firstModules)
        defaults.set(known, forKey: Self.knownKey)
        if stored != nil, selection.ids != stored { defaults.set(selection.ids, forKey: Self.selectionKey) }
    }

    /// Every module, the selected ones first in their order, then the hidden ones, for the
    /// settings and the island's edit mode.
    var lineup: [ModuleLineup.Entry] {
        let byID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let hidden = availableIDs.filter { !selection.contains($0) }
        return (selection.ids + hidden).compactMap { id in
            byID[id].map { ModuleLineup.Entry(module: Self.filed($0), selected: selection.contains(id)) }
        }
    }

    /// Hands the lineup to the views, and lets them change it. One registry at a time.
    func share(with lineup: ModuleLineup) {
        shared = lineup
        lineup.attach(entries: self.lineup,
                      move: { [weak self] id, index in self?.move(id, to: index); return self?.lineup ?? [] },
                      select: { [weak self] id, on in self?.setSelected(id, on); return self?.lineup ?? [] })
    }

    /// The snapshot of a module, with the tab it belongs to.
    private static func filed(_ module: any YumiModule) -> ModuleSnapshot {
        var snapshot = module.snapshot
        snapshot.category = module.category
        return snapshot
    }

    /// The selected modules of one tab, in the person's order.
    func selected(in category: ModuleCategory) -> [String] {
        let byID = Dictionary(modules.map { ($0.id, $0.category) }, uniquingKeysWith: { first, _ in first })
        return ModuleCategory.ids(selection.ids, in: category) { ModuleSpaces.chosen($0) ?? byID[$0] ?? ModuleCategory.of(moduleID: $0) }
    }

    /// Identifiers of every module of this build, in catalogue order.
    var availableIDs: [String] { modules.map(\.id) }

    // MARK: Lifecycle

    func start() {
        actionObserver = NotificationCenter.default.addObserver(
            forName: .moduleAction, object: nil, queue: .main
        ) { [weak self] note in
            let id = note.userInfo?["module"] as? String
            let action = (note.userInfo?["action"] as? String).flatMap(ModuleAction.init(rawValue:))
            MainActor.assumeIsolated {
                guard let self, let id, let action else { return }
                self.perform(action, on: id)
            }
        }
        profilesObserver = NotificationCenter.default.addObserver(
            forName: .profilesChosen, object: nil, queue: .main
        ) { [weak self] note in
            let ids = note.userInfo?["modules"] as? [String] ?? []
            MainActor.assumeIsolated { self?.adoptProfiles(ids) }
        }
        applySelection()
    }

    /// True once the modules were chosen (by the person, or by a profile at the first launch).
    static func modulesWereChosen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.stringArray(forKey: selectionKey) != nil
    }

    /// The modules of the profiles chosen at the first launch. Ignored once the modules were
    /// chosen: an update, or a first name asked again, never reshuffles them.
    func adoptProfiles(_ ids: [String]) {
        guard !Self.modulesWereChosen(in: defaults), !ids.isEmpty else { return }
        selection = ModuleSelection(stored: ids, available: availableIDs)
        persistAndApply()
    }

    /// Stops every module and stops listening to the island.
    func stop() {
        if let actionObserver { NotificationCenter.default.removeObserver(actionObserver) }
        actionObserver = nil
        if let profilesObserver { NotificationCenter.default.removeObserver(profilesObserver) }
        profilesObserver = nil
        for module in modules where running.contains(module.id) { module.stop() }
        running.removeAll()
    }

    // MARK: Selection

    func isSelected(_ id: String) -> Bool { selection.contains(id) }

    /// Selects or deselects a module. Returns false when nothing changed (unknown module, or selection full).
    @discardableResult
    func setSelected(_ id: String, _ selected: Bool) -> Bool {
        let changed = selected
            ? selection.select(id, available: availableIDs)
            : selection.deselect(id)
        if changed { persistAndApply() }
        return changed
    }

    /// Moves a selected module. Indexes below `ModuleCatalog.pinnedLimit` are in the island.
    func move(_ id: String, to index: Int) {
        let before = selection
        selection.move(id, to: index)
        if selection != before { persistAndApply() }
    }

    private func persistAndApply() {
        defaults.set(selection.ids, forKey: Self.selectionKey)
        applySelection()
    }

    /// Starts what became selected, stops what no longer is, then publishes.
    private func applySelection() {
        for module in modules {
            let wanted = selection.contains(module.id)
            let isRunning = running.contains(module.id)
            if wanted && !isRunning {
                running.insert(module.id)
                module.start { [weak self] in self?.publish() }
            } else if !wanted && isRunning {
                running.remove(module.id)
                module.stop()
            }
        }
        publish()
    }

    // MARK: Snapshots

    /// Rebuilds the snapshots. Publishes only on a real change, so views are not invalidated for nothing.
    func publish() {
        let byID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let snapshots = selection.ids.compactMap { byID[$0].map(Self.filed) }
        guard snapshots != published else { return }
        published = snapshots
        shared?.refresh(lineup)
        onPublish(snapshots)
    }

    // MARK: Events and actions

    /// Forwards a session event to the running modules.
    func receive(_ event: YumiEvent, sessions: [SessionID: Session]) {
        for module in modules where running.contains(module.id) {
            module.receive(event, sessions: sessions)
        }
    }

    /// A button was pressed in the island. Ignored for a module that is not running.
    func perform(_ action: ModuleAction, on id: String) {
        guard running.contains(id), let module = modules.first(where: { $0.id == id }) else { return }
        module.perform(action)
        publish()
    }
}
