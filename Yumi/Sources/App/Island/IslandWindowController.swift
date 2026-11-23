import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }
    private let model = IslandModel.shared

    // State machine (hover, auto-close, launch)
    let fsm = IslandStateMachine()
    private let launch = IslandLaunch()

    private var wasInIsland = false
    /// Debug walk-through: the island does not fold by itself.
    var holdsOpen = false { didSet { syncFoldSetting() } }
    /// Debug walk-through: as if the pointer were on the folded island.
    var demoHover = false { didSet { recheckPointer() } }
    /// The user quit: the goodbye is playing, nothing else happens.
    private var leaving = false
    /// Held for a measure (`YUMI_ISLAND_HOLD`): nothing from outside changes the island's state.
    private var frozen = false
    private var monitors: [Any] = []
    /// Three quick presses on Shift open or fold the island.
    private var tripleShift = TripleShift()
    /// The quick task shortcut (⌥ Espace by default), system-wide.
    private var quickTaskKey: GlobalHotKey?
    private var subscriptions: Set<AnyCancellable> = []

    /// The view the island opens on, when something other than a click opens it.
    private var pendingView: IslandView?
    /// Modules that were already asking for attention: only a new one opens the island.
    private var attentive: Set<String> = []

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    convenience init() {
        let notch = Self.notchScreen()
        // No screen at all (a Mac started headless): a default frame, moved when a screen appears.
        let screen = notch ?? NSScreen.main ?? NSScreen.screens.first

        let panelW = IslandConst.panelWidth * IslandStudio.scale
        let panelH = IslandConst.panelHeight * IslandStudio.scale
        let sf = screen?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = IslandPanel(
            contentRect: NSRect(x: sf.midX - panelW/2, y: sf.maxY - panelH,
                                width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )

        self.init(window: panel)
        self.islandPanel = panel
        model.layout = IslandLayout(notchWidth: screen.map(Self.notchWidth(for:)) ?? IslandConst.notchWidth,
                                    notchHeight: screen.map(Self.notchHeight(for:)) ?? IslandConst.notchHeight,
                                    hasNotch: notch != nil)
        setupPanel()
    }

    private func setupPanel() {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // A click on a button of the island leaves the keyboard where it was: only a text field
        // takes it. Otherwise the next ⌘C or ⌘V typed in the application in front came to Yumi.
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        // The local monitor only hears the pointer move if the window asks for it
        panel.acceptsMouseMovedEvents = true

        // Propagate real notch dimensions to AppState
        state.notchWidth  = model.layout.notchWidth
        state.notchHeight = model.layout.notchHeight
        attentive = Set(state.modules.filter(\.needsAttention).map(\.id))

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits above the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] in
            // He opens on the drop view and stretches up to catch the file
            AppState.shared.fileDragOver = true
            self?.expand(to: .upload)
        }
        dropView.onDragExited = {
            // Do NOT collapse — drag session still active; island stays open.
            AppState.shared.fileDragOver = false
        }
        dropView.onFilesDropped = { urls in
            FileDropHandler.handle(urls: urls, state: AppState.shared)
        }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        wireFSM()
        startPolling()
        startMonitors()
        startQuickTaskKey()
        startObservers()
        #if DEBUG
        IslandDemo.startIfRequested(controller: self)
        #endif
        IslandStudio.startIfRequested(controller: self)
        IslandHookOffer.startIfNeeded()
        YumiUpdates.shared.start()
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        launch.onComplete = { [weak self] in
            guard let self else { return }
            self.fsm.greetComplete()
            if self.holdForMeasure() { return }
            self.askFirstNameIfNeeded()
        }

        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)
                self.islandPanel.giveKeyboardBack()

            case .petit:
                if from == .hidden { SoundEngine.shared.play("peek") }
                // The launch plays its own sounds
                self.setMode(.compact, sound: from != .greeting)
                self.leaveOpenIsland()

            case .home:
                if from == .greeting { self.launch.cancel() }
                self.state.view = self.pendingView ?? .overview
                self.pendingView = nil
                self.setMode(.expanded, sound: from != .greeting)
                // Opened by the pointer resting on him: he jumps up as the island opens
                if from == .petit { IslandModel.shared.pose(.jump) }

            case .greeting:
                // Yumi only lives while the island is not hidden, and the launch draws its
                // own shapes: the mode is "expanded" for its whole length.
                self.state.view = .greeting
                self.setMode(.expanded, sound: false)
                if self.leaving { self.startGoodbye() } else { self.launch.start() }
            }
        }
    }

    /// What is left behind when the island folds: the view, the key window, a chat error.
    private func leaveOpenIsland() {
        IslandActions.leaveChatError(next: nil)
        state.isPinned = false
        fsm.pinned = false
        if state.view != .overview { state.view = .overview }
        islandPanel.giveKeyboardBack()
    }

    // MARK: - Following the pointer, only when it moves

    /// The island used to read the pointer sixty times a second, all the time. It now hears
    /// about it from the system: a global monitor while the pointer is over other
    /// applications (the panel lets clicks through there), a local one while it is on the
    /// island. Nothing runs while the pointer is still.
    private func startPolling() {
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: moves, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pollFrame() }
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: moves, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pollFrame() }
            return event
        }) { monitors.append(monitor) }

        // The island changes size under a pointer that does not move: look again when it
        // does, and once more when the change has settled.
        state.$mode.map { _ in () }
            .merge(with: model.$openHeight.map { _ in () }, model.$layout.map { _ in () }, model.$speaking.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.recheckPointer() }
            .store(in: &subscriptions)

        // What the loop used to copy at every frame
        state.$autoCloseInterval.map { _ in () }
            .merge(with: state.$absenceInterval.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.syncFoldSetting() }
            .store(in: &subscriptions)
        state.$pendingApproval
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                // An alert that waits for an answer keeps the island open
                self.fsm.pinned = self.state.isPinned
            }
            .store(in: &subscriptions)
        syncFoldSetting()
        pollFrame()
    }

    private var settleCheck: DispatchWorkItem?

    private func recheckPointer() {
        pollFrame()
        settleCheck?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.pollFrame() }
        settleCheck = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: item)
    }

    /// The delays before the island folds (0 is "never") and before the compact island hides are the user's.
    func syncFoldSetting() {
        fsm.foldsByItself = !holdsOpen && state.autoCloseInterval > 0
        if state.autoCloseInterval > 0 { fsm.homeToPetitDelay = max(3, state.autoCloseInterval) }
        // A measure or the filming mode keeps its own delay
        if !holdsOpen && !IslandStudio.isOn { fsm.petitToHiddenDelay = max(60, state.absenceInterval) }
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }
        // Filming: the pointer does nothing to the island, and clicks go through it
        if IslandStudio.isOn {
            panel.ignoresMouseEvents = true
            return
        }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // The island and, when it is out, the second square under it
        let inIsland = islandFrame().insetBy(dx: -6, dy: -6).contains(local)

        // Toggle click-through
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // An alert that waits for an answer keeps the island open
        fsm.pinned = state.isPinned

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            fsm.mouseEntered()
        }
        if !inIsland && wasInIsland {
            fsm.mouseLeft()
        }
        if inIsland { state.lastActivity = .now }
        wasInIsland = inIsland

        // The buttons of the live module come out while the pointer is on the folded island
        let onFolded = (inIsland || demoHover) && model.stage(for: state.mode) == .compact
        if model.foldedHover != onFolded { model.foldedHover = onFolded }

        // Ghost character follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    // MARK: - Geometry (panel coordinates, origin bottom-left)

    private func islandFrame() -> CGRect {
        let scale = IslandStudio.scale
        let size = CGSize(width: model.islandSize(for: state.mode).width * scale,
                          height: model.islandSize(for: state.mode).height * scale)
        let panel = window?.frame.size ?? CGSize(width: IslandConst.panelWidth, height: IslandConst.panelHeight)
        return CGRect(x: (panel.width - size.width) / 2, y: panel.height - size.height,
                      width: size.width, height: size.height)
    }

    /// The buttons of the folded island: against its right edge, on its whole height.
    private func isFoldedControlHit(_ windowPoint: CGPoint) -> Bool {
        let count = CGFloat(model.foldedControls)
        guard count > 0, model.foldedHover, model.stage(for: state.mode) == .compact else { return false }
        let island = islandFrame()
        let width = count * IslandConst.foldedControl + (count - 1) * IslandConst.foldedControlGap
        let right = island.maxX - IslandConst.foldedTrailing
        return windowPoint.x >= right - width - IslandConst.foldedGap / 2
            && windowPoint.x <= island.maxX
            && windowPoint.y >= island.minY - 6
    }

    /// Where Yumi is: his 100 × 84 box at the scale of his seat.
    private func isBotHit(_ windowPoint: CGPoint) -> Bool {
        let stage = model.stage(for: state.mode)
        guard stage == .open || stage == .compact || stage == .speak else { return false }
        let seat = model.layout.seat(stage)
        let panel = window?.frame.size ?? CGSize(width: IslandConst.panelWidth, height: IslandConst.panelHeight)
        let dx = windowPoint.x - (panel.width / 2 + seat.x)
        let dy = windowPoint.y - (panel.height - seat.y)
        return abs(dx) <= 50 * seat.scale && abs(dy) <= 42 * seat.scale
    }

    // MARK: - Mode transitions

    private func setMode(_ mode: IslandMode, sound: Bool = true) {
        let prev = state.mode
        guard mode != prev else { return }
        state.mode = mode
        guard sound else { return }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded { SoundEngine.shared.play("close") }
    }

    /// Opens the island on a view. Alerts, the menu bar item, the shortcut, a file dragged
    /// over the notch and a window handed to Yumi all come through here.
    func expand(to view: IslandView) {
        guard !leaving, !frozen else { return }
        if fsm.state == .home {
            IslandActions.leaveChatError(next: view)
            state.view = view
        } else {
            pendingView = view
            fsm.pinned = state.isPinned
            fsm.open()
        }
        state.lastActivity = .now
    }

    /// The settings window opens: folds the island like a click beside it, unless an approval
    /// waits. Returns the bottom of the island on screen when it stays open.
    func makeRoomForSettings() -> CGFloat? {
        let open = fsm.state == .home
        guard open else { return nil }
        if SettingsOpening.foldsIsland(approvalPending: state.pendingApproval != nil) {
            collapse()
            return nil
        }
        guard let frame = window?.frame else { return nil }
        return frame.minY + islandFrame().minY
    }

    func collapse() {
        state.isPinned = false
        fsm.pinned = false
        fsm.collapse()
    }

    // MARK: - Mouse and keyboard

    private func startMonitors() {
        func keep(_ monitor: Any?) { if let monitor { monitors.append(monitor) } }

        // Escape folds the island: from another application (global), or while typing in ours (local)
        keep(NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
            MainActor.assumeIsolated {
                ShowMeController.shared.keyTyped()
                self?.tripleShift.keyTyped()
                self?.keyDown(keyCode: keyCode, flags: flags)
            }
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            ShowMeController.shared.keyTyped()
            guard let self else { return event }
            let keyCode = event.keyCode
            let command = event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command
            let plain = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            let typing = event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let letters = event.characters ?? ""
            let handled = MainActor.assumeIsolated { () -> Bool in
                self.tripleShift.keyTyped()
                // Without the menu bar item (hidden by the notch on a small screen): ⌘, and ⌘Q
                if command && keyCode == 43 { IslandActions.openSettings(); return true }
                if command && keyCode == 12 { NSApp.terminate(nil); return true }
                // ← and → turn the pages of the GitHub view
                if self.fsm.state == .home,
                   GitHubPagerKeys.handle(keyCode: keyCode, plain: plain) {
                    return true
                }
                // A letter typed on the open island, outside any field: the chat opens with it
                if typing, self.fsm.state == .home, self.startsChat(with: letters) { return true }
                // Escape on a sheet goes back to the tab's bento first
                if keyCode == 53, self.fsm.state == .home, self.state.view == .module {
                    withAnimation(.islandSpring(0.5)) { IslandActions.go(.overview) }
                    return true
                }
                guard keyCode == 53, self.fsm.state == .home, !self.state.isPinned else { return false }
                self.collapse()
                return true
            }
            return handled ? nil : event
        })

        // Triple Shift, from anywhere (global) or in the island (local)
        let flags: (NSEvent) -> Void = { [weak self] event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let time = event.timestamp
            let keyCode = event.keyCode
            let raw = event.modifierFlags.rawValue
            MainActor.assumeIsolated {
                self?.flagsChanged(modifiers, at: time)
                // The right Option key held: Yumi listens, then looks (App/ShowMeController)
                ShowMeController.shared.flagsChanged(keyCode: keyCode, rawFlags: raw, at: time)
            }
        }
        keep(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags))
        keep(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in flags(event); return event })

        // A click in another application folds the open island, unless something waits in it
        keep(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        })

        // Right click on Yumi or the island: the menu the menu bar item would give
        keep(NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let shown = MainActor.assumeIsolated { () -> Bool in
                guard self.wasInIsland, let view = event.window?.contentView else { return false }
                IslandMenu.pop(at: event.locationInWindow, in: view)
                return true
            }
            return shown ? nil : event
        })

        // Window attach drag, and the click that opens the compact island.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland else { return }
                // A button of the folded island acts by itself: the island stays folded
                guard !self.isFoldedControlHit(event.locationInWindow) else { return }
                self.pendingIslandClick = true
                // Drag only starts when clicking directly on Yumi
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
            }
            return event
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                self.showDragGhost()
            }
            return event
        })
        keep(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                self.pendingIslandClick = false
                if self.inAttachDrag {
                    self.finishDrag()
                } else {
                    self.attachDragStart = nil
                    // A click on what Yumi says answers it; it does not open the island
                    if hadPendingClick, self.model.stage(for: self.state.mode) != .speak { self.fsm.click() }   // petit → home, ignored elsewhere
                }
            }
            return event
        })
        keep(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishDrag() }
        })
    }

    /// Registers the quick task shortcut, again each time the settings change it.
    private func startQuickTaskKey() {
        let key = GlobalHotKey { [weak self] in self?.quickTaskKeyPressed() }
        quickTaskKey = key
        if !IslandStudio.isOn { key.set(QuickTaskShortcut.stored()) }
        NotificationCenter.default.publisher(for: .quickTaskShortcutChanged)
            .receive(on: DispatchQueue.main)
            .sink { _ in if !IslandStudio.isOn { key.set(QuickTaskShortcut.stored()) } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .shortcutRecording)
            .receive(on: DispatchQueue.main)
            .sink { note in
                guard !IslandStudio.isOn else { return }
                key.set(note.object as? Bool == true ? nil : QuickTaskShortcut.stored())
            }
            .store(in: &subscriptions)
    }

    /// Opens the island on the quick task field; pressed again there, folds it.
    private func quickTaskKeyPressed() {
        guard !frozen, !leaving else { return }
        if fsm.state == .home, state.view == .quickTask, !state.isPinned {
            collapse()
        } else {
            expand(to: .quickTask)
        }
    }

    /// Opens the chat with `letters` in its field, when they are a letter or a digit and no
    /// field of the island already takes the keyboard. ⌥ Space keeps the quick task.
    private func startsChat(with letters: String) -> Bool {
        guard letters.count == 1, let scalar = letters.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar),
              !(window?.firstResponder is NSText),
              IslandScreen.resolve(view: state.view, state: state.effectiveState,
                                   approvalPending: state.pendingApproval != nil) != .talk else { return false }
        IslandActions.talk(seed: letters)
        return true
    }

    private func keyDown(keyCode: UInt16, flags: UInt) {
        if keyCode == 53 { // Escape
            if fsm.state == .home && !state.isPinned { collapse() }
            return
        }
        // Global hotkey to show island
        guard state.hotkeyEnabled, flags == state.hotkeyFlags, keyCode == state.hotkeyCode else { return }
        if fsm.state != .home { expand(to: .overview) }
    }

    private func flagsChanged(_ modifiers: NSEvent.ModifierFlags, at time: TimeInterval) {
        let others = !modifiers.subtracting(.shift).isEmpty
        guard tripleShift.modifiers(shift: modifiers.contains(.shift), others: others, at: time),
              UserDefaults.standard.object(forKey: TripleShift.defaultsKey) as? Bool ?? true,
              !IslandStudio.isOn, !frozen else { return }
        if fsm.state == .home { collapse() } else { expand(to: .overview) }
    }

    private func clickedOutside() {
        let approval = state.pendingApproval != nil
        guard OutsideClick.folds(islandOpen: fsm.state == .home, insideIsland: wasInIsland, approvalPending: approval,
                                 unsentDraft: model.hasDraft || IslandVoice.shared.active, pinned: state.isPinned || holdsOpen || frozen) else { return }
        collapse()
    }

    /// Yumi was dropped on a window: it becomes the context of the conversation.
    private func finishDrag() {
        guard inAttachDrag else { return }
        let mouse = NSEvent.mouseLocation
        inAttachDrag = false
        attachDragStart = nil
        hideDragGhost()
        #if !APPSTORE
        if let ctx = windowContextAtPoint(mouse) {
            IslandActions.newConversation()
            state.promptContext = ctx
            state.contextAttached = true
            state.contextExplicit = true
            SoundEngine.shared.play("approve")
            expand(to: .prompt)
        }
        #endif
    }

    // MARK: - Filming (IslandStudio)

    /// Back to the folded island at rest, whatever was playing.
    func studioRest() {
        leaving = false
        launch.cancel()
        model.leaving = false
        model.launchStage = nil
        model.greeting = .init()
        model.sparksStart = nil
        model.setLit(true)
        model.setGaze(nil)
        model.forgetCommands()
        NotificationCenter.default.post(name: .yumiMood, object: nil)
        NotificationCenter.default.post(name: .yumiRim, object: nil)
        switch fsm.state {
        case .greeting: fsm.greetComplete()
        case .home:     collapse()
        case .hidden:   fsm.reveal()
        case .petit:    break
        }
        fsm.cancelTimers()
    }

    /// The launch, from the notch, as at the start of the app.
    func studioLaunch() {
        if fsm.state == .greeting { launch.start() } else { fsm.launch() }
    }

    /// The goodbye, without ending the app.
    func studioGoodbye() {
        leaving = true
        if fsm.state == .greeting { startGoodbye(report: false) } else { fsm.leave() }
    }

    /// Yumi alone in his light, as in the greeting of the launch.
    func studioPortrait() {
        if fsm.state != .greeting {
            leaving = true      // the transition must not start the launch
            fsm.leave()
            leaving = false
        }
        launch.cancel()
        model.leaving = false
        model.greeting = .init()
        model.launchStage = .greet
        model.greeting.lit = true
        model.setLit(true)
        model.setHabit(nil)
        model.setMood(.happy, force: true)
        model.setRim(.joy)
    }

    // MARK: - Measuring

    /// `YUMI_ISLAND_HOLD=hidden|compact|open` keeps the island in one state after the launch,
    /// whatever the pointer does, so that its processor use at rest can be measured
    /// (also in Release builds, where IslandDemo does not exist).
    private func holdForMeasure() -> Bool {
        guard let hold = ProcessInfo.processInfo.environment["YUMI_ISLAND_HOLD"] else { return false }
        holdsOpen = true
        fsm.cancelTimers()
        fsm.petitToHiddenDelay = hold == "hidden" ? 0.5 : 86_400
        switch hold {
        case "open":   expand(to: .overview)
        case "hidden": fsm.mouseEntered(); fsm.mouseLeft()
        default:       fsm.mouseEntered()
        }
        frozen = true
        return true
    }

    // MARK: - First launch

    /// Once the launch is over, Yumi asks the first name if he does not know it, unless he
    /// asked not long ago. The core may still be loading its memory: he waits a moment.
    private func askFirstNameIfNeeded() {
        guard !holdsOpen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.leaving, self.fsm.state != .home, self.state.pendingApproval == nil else { return }
            let asked = UserDefaults.standard.object(forKey: IslandPrefs.nameAskedKey) as? Date
            guard FirstName.shouldAsk(name: self.state.userName, lastAsked: asked, now: .now) else { return }
            self.expand(to: .welcome)
        }
    }

    // MARK: - Leaving (Contracts/AppLifecycle.swift)

    /// The core holds the end of the app while Yumi says goodbye.
    func quitRequested() {
        guard !leaving else { return }
        leaving = true
        launch.cancel()
        if fsm.state == .greeting { startGoodbye() } else { fsm.leave() }
    }

    private func startGoodbye(report: Bool = true) {
        launch.leave {
            // Filming plays the goodbye without quitting
            if report && !IslandStudio.isOn { NotificationCenter.default.post(name: .yumiQuitReady, object: nil) }
        }
    }

    // MARK: - What the rest of the application asks of the island

    private func startObservers() {
        let center = NotificationCenter.default

        // A display plugged in or out, the lid closed on an external screen: the island moves to
        // the screen that has the notch, or the main one, instead of staying where no screen is.
        center.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.followScreens() }
            .store(in: &subscriptions)

        // Hook server expand requests (alerts only)
        center.publisher(for: .hookExpand)
            .sink { [weak self] note in
                guard let view = note.object as? IslandView, !IslandStudio.isOn else { return }
                self?.expand(to: view)
            }
            .store(in: &subscriptions)

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        center.publisher(for: .hookReveal)
            .sink { [weak self] _ in if self?.frozen == false, !IslandStudio.isOn { self?.fsm.reveal() } }
            .store(in: &subscriptions)

        center.publisher(for: .yumiQuitRequested)
            .sink { [weak self] _ in self?.quitRequested() }
            .store(in: &subscriptions)

        // Yumi has something to say while the island is hidden: it comes out, folded
        state.$remark
            .receive(on: DispatchQueue.main)
            .sink { [weak self] remark in
                guard let self, remark != nil, !self.leaving, !self.frozen else { return }
                self.fsm.reveal()
            }
            .store(in: &subscriptions)

        // Collapse requests from views (OK button, etc.)
        center.publisher(for: .islandCollapse)
            .sink { [weak self] _ in self?.collapse() }
            .store(in: &subscriptions)

        center.publisher(for: .islandVoice)
            .sink { [weak self] _ in
                guard let self, !self.leaving else { return }
                if self.state.view != .prompt || self.model.stage(for: self.state.mode) != .open { self.expand(to: .prompt) }
            }
            .store(in: &subscriptions)

        // The Context Engine: Yumi notices when the front application changes
        state.$context
            .map(\.presence)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] presence in
                guard let self, !self.leaving, !self.frozen else { return }
                self.model.contextPresenceChanged(presence, stage: self.model.stage(for: self.state.mode))
            }
            .store(in: &subscriptions)

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] note in
                if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   app.bundleIdentifier != ourBundle {
                    self?.state.lastExternalApp = app
                }
            }
            .store(in: &subscriptions)

        // The text field of the talk view needs a key window; a nonactivating panel never
        // becomes key by itself.
        state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] view in
                guard let self, self.fsm.state == .home else { return }
                let screen = IslandScreen.resolve(view: view, state: .idle, approvalPending: false)
                if screen == .talk || screen == .welcome || screen == .memory || screen == .quickTask {
                    self.islandPanel.makeKey()
                } else {
                    self.islandPanel.giveKeyboardBack()
                }
            }
            .store(in: &subscriptions)

        // A module that starts asking for the user opens the island on itself
        // (`ModuleSnapshot.needsAttention`: "the island may open by itself").
        state.$modules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] modules in self?.modulesChanged(modules) }
            .store(in: &subscriptions)
    }

    private func modulesChanged(_ modules: [ModuleSnapshot]) {
        let now = Set(modules.filter(\.needsAttention).map(\.id))
        defer { attentive = now }
        guard let fresh = modules.first(where: { $0.needsAttention && !attentive.contains($0.id) }),
              fsm.state != .greeting, state.pendingApproval == nil, !holdsOpen else { return }
        model.selectedModuleID = fresh.id
        expand(to: .module)
    }

    // MARK: - Drag ghost window (character follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Twice the compact size, for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    old.animator().alphaValue = 0
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(130))
                    old.close()
                }
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    /// The frontmost regular application window under a screen point (AppKit coordinates).
    private func externalWindow(at screenPoint: NSPoint) -> (bounds: CGRect, app: NSRunningApplication)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), app)
        }
        return nil
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        externalWindow(at: screenPoint).map { ($0.bounds, $0.app.processIdentifier) }
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        externalWindow(at: screenPoint).flatMap { WindowContextCapture.captureActive(from: $0.app) }
    }

    /// Puts the panel back at the top centre of the screen it belongs on, with that screen's notch.
    private func followScreens() {
        guard let panel = window, let screen = Self.notchScreen() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = panel.frame
        let origin = NSPoint(x: screen.frame.midX - frame.width / 2, y: screen.frame.maxY - frame.height)
        if frame.origin != origin { panel.setFrameOrigin(origin) }
        var layout = model.layout
        layout.fit(notchWidth: Self.notchWidth(for: screen), notchHeight: Self.notchHeight(for: screen),
                   hasNotch: screen.safeAreaInsets.top > 0)
        guard layout != model.layout else { return }
        model.layout = layout
        state.notchWidth = layout.notchWidth
        state.notchHeight = layout.notchHeight
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static func notchWidth(for screen: NSScreen) -> CGFloat {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            return IslandConst.notchWidth
        }
        let w = screen.frame.width - left.width - right.width
        return w > 0 ? w : IslandConst.notchWidth
    }

    static func notchHeight(for screen: NSScreen) -> CGFloat {
        let h = screen.safeAreaInsets.top
        return h > 0 ? h : IslandConst.notchHeight
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Gives the keyboard back to the application in front. `resignKey()` only tells a window
    /// it lost the keyboard: called by hand, AppKit and the window server stop agreeing on who
    /// has it, and the keys typed next could still come here. Ordering the panel out takes the
    /// keyboard away for real; it comes back at once, in the same place.
    func giveKeyboardBack() {
        guard isKeyWindow || NSApp.keyWindow === self else { return }
        let visible = isVisible
        orderOut(nil)
        if visible { orderFrontRegardless() }
    }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    // The character listens to these (BotCanvasView); the island itself now only uses
    // Contracts/CharacterCommands.swift.
    static let triggerEmote     = AppIdentity.notification("triggerEmote")
    static let triggerSlap      = AppIdentity.notification("triggerSlap")
    static let botGreet         = AppIdentity.notification("botGreet")
    static let botBlink         = AppIdentity.notification("botBlink")
    static let botSetTgEs       = AppIdentity.notification("botSetTgEs")
    static let botGulp          = AppIdentity.notification("botGulp")
    static let botMorphTo       = AppIdentity.notification("botMorphTo")
    // Requests to the island
    static let islandCollapse   = AppIdentity.notification("islandCollapse")
    /// Yumi listens or answers aloud: the island opens on it.
    static let islandVoice      = AppIdentity.notification("islandVoice")
    static let openFullSettings = AppIdentity.notification("openFullSettings")
    static let hookReveal       = AppIdentity.notification("hookReveal")
}
