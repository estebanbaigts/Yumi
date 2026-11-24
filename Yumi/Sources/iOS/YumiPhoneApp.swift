import SwiftUI
import UserNotifications

@main
struct YumiPhoneApp: App {
    @UIApplicationDelegateAdaptor(PhoneAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var phone = Phone()
    @State private var opening = true

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .top) {
                PhoneRootView(phone: phone)
                // On black, the island opens, he says hello and lands at his place on the home
                // screen; its cover then goes, and the cards come in under him
                if opening {
                    PhoneSplash(character: phone.character,
                                name: { phone.memoryBook.name ?? (phone.studio ? "Esteban" : nil) },
                                reveal: { phone.revealed = true },
                                landed: { phone.orbShown = true }) {
                        opening = false
                    }
                    // Removed at once: by then it draws nothing
                    .transition(.identity)
                }
            }
            .preferredColorScheme(.dark)
            .task { await phone.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await phone.cameBack() } }
            // His eyes follow only while the app is in front: the camera stops at once otherwise
            phone.watcher.setActive(phase == .active, phone: phone)
        }
    }
}

/// Everything Yumi has on the iPhone. Built once at launch; nothing is read or asked before the
/// person does something, and nothing at all while filming.
@MainActor
@Observable
final class Phone {
    let studio = StudioMode.isOn
    /// The link with the Mac can be turned on. The iPhone says « En attente du Mac » until a Mac
    /// with the link on publishes its picture.
    static let linkReady = true
    let chat: PhoneChat
    let today: PhoneToday
    let mail: PhoneMail
    let approvals = PhoneApprovals()
    let github = PhoneGitHub()
    let character = PhoneCharacter()
    /// The home screen's content shows once the opening is over.
    var revealed = false
    /// The circle at the bottom shows once he landed in it (the opening).
    var orbShown = false
    /// The screen shown, chosen from the menu of the title.
    var page: PhonePage = .today
    /// Today's cards are being arranged.
    var editingToday = false
    /// An ambiance was chosen by hand on the weather screen: its ground follows.
    var weatherChanged = false
    let listener = PhoneListener()
    @ObservationIgnored let memory: MemoryStore?
    @ObservationIgnored private let permissions: LocalPermissionManager?
    /// What Yumi remembers, as the screens show it.
    var memoryBook: MemoryBook { memoryMirror.book }
    private let memoryMirror = MemoryMirror()
    /// What the Mac published, when the link is on. Nil without a Mac: nothing about it is shown.
    var mac: LinkSnapshot? { studio ? PhoneStudio.mac : PhoneLink.shared.mac }
    var linkOn: Bool {
        didSet {
            guard !studio, linkOn != oldValue else { return }
            LinkSetting.set(linkOn)
            if linkOn { Task { await PhoneLink.shared.turnedOn() } } else { PhoneLink.shared.turnedOff() }
        }
    }
    /// The sounds of the character, as on the Mac (same key).
    var soundOn: Bool = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundOn, forKey: "soundEnabled") }
    }
    /// Yumi in the Dynamic Island (on by default).
    var islandOn: Bool = PhoneDayActivity.isOn {
        didSet {
            PhoneDayActivity.isOn = islandOn
            if islandOn { updateRemarks() }
        }
    }
    /// « Yumi te regarde »: his eyes follow the tilt of the iPhone (on by default)…
    var watchesOn: Bool = UserDefaults.standard.object(forKey: "phoneWatches") as? Bool ?? true {
        didSet { UserDefaults.standard.set(watchesOn, forKey: "phoneWatches"); watcher.update(phone: self) }
    }
    /// …or the face, with the camera (off by default; nothing is recorded).
    var watchesFace: Bool = UserDefaults.standard.bool(forKey: "phoneWatchesFace") {
        didSet { UserDefaults.standard.set(watchesFace, forKey: "phoneWatchesFace"); watcher.update(phone: self) }
    }
    @ObservationIgnored let watcher = PhoneWatcher()
    /// Filming mode for the next launch (the iPhone has no environment variables).
    var studioNextLaunch: Bool = StudioMode.isSetForNextLaunch() {
        didSet { StudioMode.setForNextLaunch(studioNextLaunch) }
    }

    init() {
        if studio {
            chat = .studio()
            today = .studio()
            mail = PhoneMail(studio: true)
            memory = nil
            permissions = nil
            linkOn = true
            character.greetedAtLaunch()
            return
        }
        let folder = AppIdentity.supportDirectory
        let permissions = LocalPermissionManager(
            store: FilePermissionStore(url: folder.appendingPathComponent("permissions.json")),
            audit: PermissionAuditLog(sink: FileAuditSink(url: folder.appendingPathComponent("permissions-audit.jsonl"))))
        self.permissions = permissions
        let mirror = memoryMirror
        let memory = MemoryStore { mirror.book = $0 }
        self.memory = memory
        chat = PhoneChat(agent: Self.makeAgent(permissions: permissions), memory: memory,
                         fileURL: folder.appendingPathComponent("conversation.json"))
        today = PhoneToday(live: true, notesURL: folder.appendingPathComponent("notes.md"))
        mail = PhoneMail(studio: false)
        let today = today
        chat.day = { tomorrow in today.told(tomorrow: tomorrow) }
        // Off until the Mac's side is switched on (Phone.linkReady), whatever was chosen before
        linkOn = Self.linkReady && LinkSetting.isOn()
        // The opening says hello (PhoneSplash): the screens do not greet a second time
        character.greetedAtLaunch()
    }

    func start() async {
        chat.character = character
        approvals.character = character
        today.changed = { [weak self] in self?.updateRemarks() }
        today.watch()
        #if DEBUG
        // `-YumiPage agents` opens a screen at launch, to check it
        if let raw = UserDefaults.standard.string(forKey: "YumiPage"), let page = PhonePage(rawValue: raw) { self.page = page }
        #endif
        if studio {
            PhoneLink.shared.showStudio(PhoneStudio.mac)
            updateRemarks()
            return
        }
        permissions?.presenter = approvals
        Task { await PhoneLink.shared.watch() }
        memory?.start()
        // All at once: the Mac's agents do not wait for the calendar, nor the mails
        Task { await mail.refresh() }
        Task { await github.refresh() }
        let link = linkOn ? Task { await PhoneLink.shared.refresh() } : nil
        await today.refresh()
        updateRemarks()
        await link?.value
        updateRemarks()
        #if DEBUG
        // As on the Mac: `YUMI_CHAT_PROMPT="a||b"` sends messages at launch and prints the answers
        if let prompts = ProcessInfo.processInfo.environment["YUMI_CHAT_PROMPT"] {
            print("[chat] modèle d'Apple : \(AppleModelAvailability.current)")
            for prompt in prompts.components(separatedBy: "||") {
                await chat.send(prompt)
                print("[chat] > \(prompt)\n[chat] < \(chat.messages.last?.text ?? "")")
            }
        }
        #endif
    }

    /// Back in front: what changed meanwhile (the Mac's picture first, it may hold a request).
    func cameBack() async {
        guard !studio else { return }
        widgetsFreshened = false
        let link = linkOn ? Task { await PhoneLink.shared.refresh() } : nil
        await today.refresh()
        await link?.value
        Task { await mail.refresh() }
        updateRemarks()
    }

    /// What Yumi has to say, from the day as it is now.
    /// The widgets are rewritten at each launch and each return, whatever they held: never a day old.
    @ObservationIgnored private var widgetsFreshened = false

    func updateRemarks() {
        character.update(from: today, name: memoryBook.name ?? (studio ? "Esteban" : nil), mac: linkOn ? mac : nil)
        PhoneWidgets.publish(remark: character.remark, today: today, mac: linkOn ? mac : nil, force: !widgetsFreshened)
        widgetsFreshened = true
        let today = today, mac = linkOn ? mac : nil
        Task { await PhoneDayActivity.update(today: today, mac: mac) }
    }

    /// The first launch: Yumi asks the person's first name, once (never while filming).
    var asksName: Bool {
        revealed && !studio && memoryBook.name == nil && !UserDefaults.standard.bool(forKey: Self.nameAskedKey)
    }
    static let nameAskedKey = "phoneNameAsked"

    /// The answer, or « plus tard »: asked once either way (the settings keep the memory).
    func answerName(_ name: String?) {
        UserDefaults.standard.set(true, forKey: Self.nameAskedKey)
        if let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            memory?.change { $0.setName(name) }
            character.engine.play(.celebrate)
            SoundEngine.shared.play("love")
        }
        nameAsked.toggle()
        updateRemarks()
        Task { await askEverything() }
    }
    /// Seen by the screens when the question has been answered.
    private(set) var nameAsked = false

    /// The screens left, for « back », and the ones left by going back, for « forward ».
    private(set) var behind: [PhonePage] = []
    private(set) var ahead: [PhonePage] = []

    func go(_ page: PhonePage) {
        guard page != self.page else { return }
        behind.append(self.page)
        if behind.count > 30 { behind.removeFirst() }
        ahead.removeAll()
        show(page, from: .trailing)
    }

    /// A swipe to the right, or the ‹ next to the title: the screen before.
    func back() {
        guard let page = behind.popLast() else { return }
        ahead.append(self.page)
        show(page, from: .leading)
    }

    /// A swipe to the left: the screen one went back from.
    func forward() {
        guard let page = ahead.popLast() else { return }
        behind.append(self.page)
        show(page, from: .trailing)
    }

    /// Where the new screen comes from, for its slide.
    private(set) var arrival: Edge = .trailing

    private func show(_ page: PhonePage, from edge: Edge) {
        if page != .talk, listener.listening { listener.stop() }
        editingToday = false
        arrival = edge
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { self.page = page }
    }

    /// A touch on Yumi: to the conversation and he listens; a second touch sends what he heard.
    func talk() {
        if page != .talk { go(.talk) }
        if listener.listening {
            let text = listener.stop()
            // Asked aloud, answered aloud
            if !text.isEmpty {
                Task {
                    await chat.send(text)
                    if let answer = chat.messages.last, answer.role == .yumi { await PhoneSpeaker.shared.say(answer.text) }
                }
            }
            character.engine.setState(.idle)
        } else {
            PhoneSpeaker.shared.stop()
            character.engine.setState(.question)
            Task { await listener.start(); if !listener.listening { character.engine.setState(.idle) } }
        }
    }

    /// The first launch, right after the first name: every permission asked once, one after the
    /// other, so that nothing asks again in the middle of something.
    func askEverything() async {
        guard !studio else { return }
        await today.askCalendar()
        await today.askReminders()
        await today.loadWeather()
        _ = await listener.ask()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        updateRemarks()
    }

    func forget(_ entry: MemoryEntry) {
        memory?.change { _ = $0.forget(id: entry.id) }
    }

    /// The agent of the iPhone: the simple mode first, Apple's model for what it cannot read, and
    /// only what an iPhone can do (reminders, calendar). Every step goes through `permissions`.
    private static func makeAgent(permissions: LocalPermissionManager) -> RuntimeAgent {
        let planner = PhonePlanner(simple: SimplePlanner(taskDestination: { (.reminders, nil) }),
                                   llm: LLMAgentPlanner(provider: AppleLLMProvider()))
        var tools = ToolRegistry.standard
        try? tools.register(AddReminderTool(store: EventKitReminderStore()))
        try? tools.register(AddEventTool(store: EventKitEventStore()))
        return RuntimeAgent(planner: planner, tools: tools, permissions: permissions,
                            policy: AgentPolicy(maximumRisk: .write))
    }
}

/// Holds the memory the store reports, so that the screens follow every change.
@MainActor
@Observable
final class MemoryMirror {
    var book = MemoryBook()
}
