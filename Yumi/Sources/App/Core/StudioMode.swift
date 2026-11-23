import Foundation

/// Filming mode: `YUMI_STUDIO=1` shows Yumi without anything personal. Nothing real starts,
/// nothing is read from or written to Yumi's folder or the Keychain, and no permission can be
/// asked: `AppState` is left entirely to the island. Available in every build, Release included.
enum StudioMode {
    static let variable = "YUMI_STUDIO"

    /// True for this run of the app. Read once.
    static let isOn: Bool = {
        #if os(iOS)
        // An app opened from the home screen has no environment: the iPhone also reads the
        // launch argument `-YUMI_STUDIO 1` and its own setting (applied at the next launch).
        if isOn(in: ["YUMI_STUDIO": UserDefaults.standard.string(forKey: variable) ?? ""]) { return true }
        #endif
        return isOn(in: ProcessInfo.processInfo.environment)
    }()

    #if os(iOS)
    /// The iPhone's setting. Takes effect at the next launch: nothing real may start and stop.
    static func setForNextLaunch(_ on: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(on ? "1" : "0", forKey: variable)
    }

    static func isSetForNextLaunch(_ defaults: UserDefaults = .standard) -> Bool {
        isOn(in: ["YUMI_STUDIO": defaults.string(forKey: variable) ?? ""])
    }
    #endif

    /// Any value turns it on, except an empty one, "0", "false" and "no".
    static func isOn(in environment: [String: String]) -> Bool {
        guard let value = environment[variable]?.trimmingCharacters(in: .whitespaces).lowercased() else { return false }
        return !["", "0", "false", "no"].contains(value)
    }
}

/// What the app starts at launch. Everything in an ordinary run, nothing while filming.
struct LaunchPlan: Equatable, Sendable {
    /// The socket of the Claude Code hooks, and the hook script written in Yumi's folder.
    var hookServer: Bool
    /// The modules: calendar, reminders, location, music, GitHub, weather.
    var modules: Bool
    /// The memory file.
    var memory: Bool
    /// The remarks Yumi makes on his own.
    var initiative: Bool
    /// The chat, through Claude Code or the API.
    var chat: Bool
    /// The secrets of the Keychain.
    var keychain: Bool
    /// The Context Engine: which application and window are in front.
    var context: Bool

    init(studio: Bool) {
        let real = !studio
        hookServer = real
        modules = real
        memory = real
        initiative = real
        chat = real
        keychain = real
        context = real
    }

    /// The plan of this run.
    static let current = LaunchPlan(studio: StudioMode.isOn)

    /// True when nothing at all starts.
    var startsNothing: Bool {
        !(hookServer || modules || memory || initiative || chat || keychain || context)
    }
}
