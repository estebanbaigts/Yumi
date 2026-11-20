import SwiftUI

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
                                name: { phone.memoryBook.name ?? (phone.studio ? "Esteban" : nil) }) {
                        opening = false
                        phone.revealed = true
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
        }
    }
}

/// Everything Yumi has on the iPhone. Built once at launch; nothing is read or asked before the
/// person does something, and nothing at all while filming.
@MainActor
@Observable
final class Phone {
    let studio = StudioMode.isOn
    let chat: PhoneChat
    let today: PhoneToday
    let approvals = PhoneApprovals()
    let character = PhoneCharacter()
    /// The home screen's content shows once the opening is over.
    var revealed = false
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
    /// Filming mode for the next launch (the iPhone has no environment variables).
    var studioNextLaunch: Bool = StudioMode.isSetForNextLaunch() {
        didSet { StudioMode.setForNextLaunch(studioNextLaunch) }
    }

    init() {
        if studio {
            chat = .studio()
            today = .studio()
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
        let today = today
        chat.day = { tomorrow in today.told(tomorrow: tomorrow) }
        linkOn = LinkSetting.isOn()
        // The opening says hello (PhoneSplash): the screens do not greet a second time
        character.greetedAtLaunch()
    }

    func start() async {
        chat.character = character
        approvals.character = character
        if studio {
            PhoneLink.shared.showStudio(PhoneStudio.mac)
            updateRemarks()
            return
        }
        permissions?.presenter = approvals
        memory?.start()
        await today.refresh()
        if linkOn, !studio { await PhoneLink.shared.refresh() }
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
        if linkOn { await PhoneLink.shared.refresh() }
        await today.refresh()
        updateRemarks()
    }

    /// What Yumi has to say, from the day as it is now.
    func updateRemarks() {
        character.update(from: today, name: memoryBook.name ?? (studio ? "Esteban" : nil), mac: linkOn ? mac : nil)
        PhoneWidgets.publish(remark: character.remark, today: today, mac: linkOn ? mac : nil)
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
