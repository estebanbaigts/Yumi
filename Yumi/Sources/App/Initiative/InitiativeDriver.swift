import AppKit
import IOKit.ps

/// What the driver needs from the rest of the app, given as closures so it depends on nothing.
struct InitiativeLinks {
    /// Shows a remark, or removes it with nil.
    var show: @MainActor (YumiRemark?) -> Void
    var memory: @MainActor () -> MemoryBook
    var focusRunning: @MainActor () -> Bool
    /// Today's remaining appointments: how many (nil when the calendar cannot be read), and the next one.
    var agenda: @MainActor () -> (count: Int?, next: (title: String, start: Date)?)
    var perform: @MainActor (RemarkAction) -> Void
    /// What the Mac says about the moment: Do Not Disturb, a presentation, a shared screen.
    var mac: @MainActor () -> (doNotDisturb: Bool, presenting: Bool, screenShared: Bool) = {
        (MacSurroundings.doNotDisturb(), MacSurroundings.presenting(), MacSurroundings.screenShared())
    }
    /// Seconds after launch before the first look: the modules need a moment to read the calendar.
    var settleTime: Double = 6
}

/// Watches the Mac and feeds the initiative engine. It costs nothing at rest: it reacts to
/// notifications of the system (wake, lock, battery) and to session events, and for what only
/// time brings it sleeps until the exact moment. No repeating timer, no polling.
@MainActor
final class InitiativeDriver {
    private static let stateKey = "initiativeState"

    private struct Saved: Codable {
        var engine = InitiativeEngine()
        var watch = InitiativeWatch()
    }

    private let links: InitiativeLinks
    private let defaults: UserDefaults
    private var saved: Saved
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var deadline: Task<Void, Never>?
    private var expiry: Task<Void, Never>?
    private var batterySource: CFRunLoopSource?
    /// How many times the driver was woken, for the measure of what it costs at rest.
    private(set) var wakeUps = 0

    init(links: InitiativeLinks, defaults: UserDefaults = .standard) {
        self.links = links
        self.defaults = defaults
        saved = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(Saved.self, from: $0) } ?? Saved()
    }

    // MARK: Lifecycle

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        listen(workspace, NSWorkspace.didWakeNotification) { $0.arrived() }
        listen(workspace, NSWorkspace.screensDidWakeNotification) { $0.arrived() }
        listen(workspace, NSWorkspace.willSleepNotification) { $0.left() }
        listen(workspace, NSWorkspace.screensDidSleepNotification) { $0.left() }
        let distributed = DistributedNotificationCenter.default()
        listen(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.arrived() }
        listen(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.left() }

        let center = NotificationCenter.default
        observers.append((center, center.addObserver(forName: .remarkAccepted, object: nil, queue: .main) { [weak self] note in
            let id = note.userInfo?["id"] as? String
            MainActor.assumeIsolated { if let id { self?.accepted(id) } }
        }))
        observers.append((center, center.addObserver(forName: .remarkDismissed, object: nil, queue: .main) { [weak self] note in
            let id = note.userInfo?["id"] as? String
            let ignored = note.userInfo?["ignored"] as? Bool ?? false
            MainActor.assumeIsolated { if let id { self?.dismissed(id, ignored: ignored) } }
        }))

        // The system calls back when the battery level or the charger changes: nothing to poll.
        Self.current = self
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            MainActor.assumeIsolated { InitiativeDriver.current?.batteryChanged() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            batterySource = source
        }
        deadline = Task { [weak self, settle = links.settleTime] in
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled else { return }
            self?.arrived()
        }
    }

    func stop() {
        for (center, observer) in observers { center.removeObserver(observer) }
        observers = []
        deadline?.cancel()
        expiry?.cancel()
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode) }
        batterySource = nil
        if Self.current === self { Self.current = nil }
    }

    private static weak var current: InitiativeDriver?

    private func listen(_ center: NotificationCenter, _ name: Notification.Name, _ handle: @escaping @MainActor (InitiativeDriver) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { handle(self) } }
        }))
    }

    // MARK: What happens

    func arrived() {
        wakeUps += 1
        let agenda = links.agenda()
        let occasion = saved.watch.arrived(now: Date(), calendar: .current, eventsToday: agenda.count, firstEventAt: agenda.next?.start)
        offer(occasion)
        clock()
    }

    func left() {
        wakeUps += 1
        saved.watch.left(now: Date())
        deadline?.cancel()
        deadline = nil
        save()
    }

    /// A session event went through the engine.
    func session(_ event: YumiEvent, sessions: [SessionID: Session]) {
        let wasWaiting = saved.watch.agentWaiting
        offer(saved.watch.session(event, sessions: sessions, now: Date()))
        // Someone starts waiting: an appointment close by becomes worth a word.
        if saved.watch.agentWaiting != wasWaiting { clock() }
    }

    /// The person is back after a real break without leaving the session (screen time saw it):
    /// the two hours of work count again from now.
    func rested() {
        wakeUps += 1
        saved.watch.rested(now: Date())
        clock()
    }

    /// Something a module thinks is worth a word. The engine decides, with all its rules.
    func notice(_ occasion: Occasion) {
        offer(occasion)
    }

    private func batteryChanged() {
        wakeUps += 1
        guard let battery = MacSurroundings.battery() else { return }
        offer(saved.watch.battery(percent: battery.percent, charging: battery.charging))
    }

    /// Says what the time brings, then sleeps until the next moment it can bring something.
    private func clock() {
        let now = Date()
        for occasion in saved.watch.clock(now: now, calendar: .current) { offer(occasion) }
        let next = links.agenda().next
        if let next { offer(saved.watch.meeting(title: next.title, start: next.start, now: now)) }
        save()

        deadline?.cancel()
        guard let date = saved.watch.nextDeadline(now: now, calendar: .current, nextEventStart: next?.start) else {
            deadline = nil
            return
        }
        deadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(date.timeIntervalSinceNow + 1), tolerance: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.wakeUps += 1
            self.clock()
        }
    }

    // MARK: Speaking

    private func offer(_ occasion: Occasion?) {
        guard let occasion else { return }
        let book = links.memory()
        var around = Surroundings(now: Date())
        around.talk = defaults.string(forKey: YumiTalk.defaultsKey).flatMap(YumiTalk.init(rawValue:)) ?? .discreet
        around.name = book.name
        if let agent = saved.watch.agentSpeaker { around.agent = agent }
        around.projects = book.entries(of: .project).map(\.text)
        around.thread = book.entries(of: .thread).filter { around.now.timeIntervalSince($0.date) < 3 * 24 * 3600 }.map(\.text)
        // Cheap checks first; the Mac is only asked about the rest when he would otherwise speak.
        around.focusRunning = links.focusRunning()
        guard saved.engine.refusal(of: occasion, in: around) == nil else { return }
        let mac = links.mac()
        around.doNotDisturb = mac.doNotDisturb
        around.presenting = mac.presenting
        around.screenShared = mac.screenShared

        // One remark at a time: the one on screen gives way, as ignored.
        if let previous = saved.engine.pendingID { saved.engine.dismissed(id: previous, ignored: true, now: around.now) }
        guard let remark = saved.engine.consider(occasion, in: around) else { return }
        save()
        links.show(remark)
        expiry?.cancel()
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(remark.duration))
            guard !Task.isCancelled else { return }
            // The island reports the timeout too; whichever comes first counts, once.
            self?.dismissed(remark.id, ignored: true)
        }
    }

    /// The island's answers, also reachable directly.
    func answer(accepted id: String) { accepted(id) }
    func answer(dismissed id: String, ignored: Bool) { dismissed(id, ignored: ignored) }

    private func accepted(_ id: String) {
        guard saved.engine.pendingID == id else { return }
        let action = saved.engine.accepted(id: id)
        expiry?.cancel()
        links.show(nil)
        if action == .takeBreak {
            saved.watch.tookBreak(now: Date())
            clock()
        }
        save()
        if let action { links.perform(action) }
    }

    private func dismissed(_ id: String, ignored: Bool) {
        guard saved.engine.dismissed(id: id, ignored: ignored, now: Date()) else { return }
        expiry?.cancel()
        links.show(nil)
        save()
    }

    #if DEBUG
    /// Tests only: makes a session's prompt older, since the driver reads the real clock.
    func backdatePrompt(id: String, by seconds: TimeInterval) {
        saved.watch.backdatePrompt(id: id, to: Date().addingTimeInterval(-seconds))
    }
    #endif

    private func save() {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: Self.stateKey) }
    }
}

/// What the Mac says about the moment. Asked only when Yumi is about to speak.
enum MacSurroundings {
    /// Battery level and whether a charger is plugged in; nil on a Mac without a battery.
    static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let capacity = description[kIOPSMaxCapacityKey] as? Int, capacity > 0 else { continue }
            let plugged = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            return (current * 100 / capacity, plugged)
        }
        return nil
    }

    /// True when a Focus (Do Not Disturb) is on. macOS has no public call for it from a plain app:
    /// the system keeps the active Focus in a file, read here when it is readable (it is not in
    /// the sandbox, where this answers false).
    static func doNotDisturb() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stores = root["data"] as? [[String: Any]] else { return false }
        return stores.contains { !(($0["storeAssertionRecords"] as? [Any]) ?? []).isEmpty }
    }

    /// True when the display is mirrored (a projector, a shared room screen) or a slideshow fills the screen.
    static func presenting() -> Bool {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 8)
        if CGGetActiveDisplayList(8, &displays, &count) == .success,
           displays.prefix(Int(count)).contains(where: { CGDisplayIsInMirrorSet($0) != 0 }) { return true }
        let slideshows = ["Keynote", "Microsoft PowerPoint"]
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // A slideshow plays above ordinary windows; a document being edited does not.
        return windows.contains { window in
            slideshows.contains(window[kCGWindowOwnerName as String] as? String ?? "") && (window[kCGWindowLayer as String] as? Int ?? 0) > 0
        }
    }

    /// True when another program is watching the screen: a call sharing it, a recording.
    static func screenShared() -> Bool {
        #if APPSTORE
        return false
        #else
        // The window server knows; the call is not in the public headers, so it is looked up at
        // run time and simply not used if a future system no longer has it.
        typealias Check = @convention(c) () -> Bool
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSIsScreenWatcherPresent") else { return false }
        return unsafeBitCast(symbol, to: Check.self)()
        #endif
    }
}
