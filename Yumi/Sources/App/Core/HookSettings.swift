import Foundation

/// Reading and merging an agent's settings file for Yumi's hooks: Claude Code's
/// `~/.claude/settings.json`, Codex's `~/.codex/hooks.json`, Gemini CLI's `~/.gemini/settings.json`.
/// All three keep their hooks the same way (`hooks` → event → matchers → commands). Pure: the
/// caller reads and writes the file. What cannot be read safely is refused, never replaced:
/// the file is the person's, and only Yumi's own hooks may change in it.
enum HookSettings {
    enum Problem: Error, Equatable, LocalizedError {
        /// The file exists but is not valid JSON.
        case notJSON
        /// Valid JSON, but not an object at the top.
        case notAnObject
        /// "hooks" is there but is not an object, or one of its events is not a list.
        case unexpectedHooks(String)

        var errorDescription: String? {
            switch self {
            case .notJSON: loc("Ce fichier n'est pas un JSON valide. Corrige-le (ou supprime-le s'il est vide), puis réessaie : je n'y ai pas touché.")
            case .notAnObject: loc("Ce fichier ne contient pas un objet JSON. Je n'y ai pas touché.")
            case .unexpectedHooks(let key): loc("Dans ce fichier, « \(key) » n'a pas la forme attendue. Je n'y ai pas touché.")
            }
        }
    }

    /// The settings as an object. A missing or blank file is an empty object; anything else
    /// that is not a JSON object is a problem.
    static func parse(_ data: Data?) throws(Problem) -> [String: Any] {
        guard let data, !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) } catch { throw .notJSON }
        guard let settings = object as? [String: Any] else { throw .notAnObject }
        if let hooks = settings["hooks"] {
            guard let events = hooks as? [String: Any] else { throw .unexpectedHooks("hooks") }
            for (key, value) in events where !(value is [[String: Any]]) { throw .unexpectedHooks("hooks.\(key)") }
        }
        return settings
    }

    /// The settings with Yumi's hooks, once per event, and without the legacy ones of an earlier notch app.
    /// Everything else is kept as it was.
    static func merge(_ data: Data?, command: String, events: [(String, Int)],
                      isOwn: (String) -> Bool, isLegacy: (String) -> Bool) throws(Problem) -> (data: Data, legacyRemoved: Int) {
        var settings = try parse(data)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var legacy = 0
        for key in hooks.keys {
            guard var matchers = hooks[key] as? [[String: Any]] else { continue }
            legacy += strip(&matchers, where: isLegacy)
            _ = strip(&matchers, where: isOwn)
            if matchers.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = matchers }
        }
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.append(["hooks": [["type": "command", "command": command, "timeout": timeout]]])
            hooks[event] = existing
        }
        settings["hooks"] = hooks
        guard let out = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { throw .notAnObject }
        return (out, legacy)
    }

    /// Removes the hooks whose command matches; a matcher left empty is dropped. Returns how many.
    static func strip(_ matchers: inout [[String: Any]], where shouldRemove: (String) -> Bool) -> Int {
        var removed = 0
        matchers = matchers.compactMap { matcher in
            let list = matcher["hooks"] as? [[String: Any]] ?? []
            let kept = list.filter { !(($0["command"] as? String).map(shouldRemove) ?? false) }
            guard kept.count < list.count else { return matcher }
            removed += list.count - kept.count
            guard !kept.isEmpty else { return nil }
            var matcher = matcher
            matcher["hooks"] = kept
            return matcher
        }
        return removed
    }

    /// True when the settings hold one of Yumi's hooks on `event`. An unreadable file holds none.
    static func installed(_ data: Data?, event: String, isOwn: (String) -> Bool) -> Bool {
        guard let settings = try? parse(data), let hooks = settings["hooks"] as? [String: Any],
              let matchers = hooks[event] as? [[String: Any]] else { return false }
        return matchers.contains { matcher in
            (matcher["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String).map(isOwn) ?? false }
        }
    }

    /// The settings without Yumi's hooks; an event left empty is dropped. nil when there is none
    /// to remove (nothing to write).
    static func removing(_ data: Data?, isOwn: (String) -> Bool) throws(Problem) -> Data? {
        var settings = try parse(data)
        guard var hooks = settings["hooks"] as? [String: Any] else { return nil }
        var removed = 0
        for key in hooks.keys {
            guard var matchers = hooks[key] as? [[String: Any]] else { continue }
            let count = strip(&matchers, where: isOwn)
            guard count > 0 else { continue }
            removed += count
            if matchers.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = matchers }
        }
        guard removed > 0 else { return nil }
        settings["hooks"] = hooks
        guard let out = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else { throw .notAnObject }
        return out
    }

    /// A backup name that does not exist yet, beside the file: `settings.json.bak-20261005-1412`,
    /// `hooks.json.bak-20261005-1412`, then `-2`, `-3`…
    static func backupURL(for settings: URL, now: Date, exists: (URL) -> Bool) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let base = settings.deletingLastPathComponent().appendingPathComponent("\(settings.lastPathComponent).bak-\(formatter.string(from: now))")
        var candidate = base
        var index = 2
        while exists(candidate) {
            candidate = URL(fileURLWithPath: base.path + "-\(index)")
            index += 1
        }
        return candidate
    }
}

/// An agent whose settings file Yumi can add its hooks to, the events it listens to and how
/// long each may wait for Yumi. Gemini CLI counts in milliseconds, the others in seconds.
struct HookTarget: Equatable, Sendable, Identifiable {
    struct Event: Equatable, Sendable {
        let name: String
        let timeout: Int
    }

    let id: String
    let name: String
    /// The settings file, from the home folder.
    let file: String
    let events: [Event]
    /// The event that tells whether Yumi's hooks are there.
    let marker: String

    static let claudeCode = HookTarget(id: "claude-code", name: "Claude Code", file: ".claude/settings.json", events: [
        Event(name: "SessionStart", timeout: 10), Event(name: "SessionEnd", timeout: 10),
        Event(name: "UserPromptSubmit", timeout: 10),
        Event(name: "PreToolUse", timeout: 10), Event(name: "PostToolUse", timeout: 10), Event(name: "PostToolUseFailure", timeout: 10),
        Event(name: "PermissionRequest", timeout: 120),
        Event(name: "Notification", timeout: 10),
        Event(name: "Stop", timeout: 10), Event(name: "StopFailure", timeout: 10),
        Event(name: "SubagentStart", timeout: 10), Event(name: "SubagentStop", timeout: 10),
    ], marker: "SessionStart")

    /// The events Codex calls hooks for, the same names as Claude Code's.
    static let codex = HookTarget(id: "codex", name: "Codex", file: ".codex/hooks.json", events: [
        Event(name: "SessionStart", timeout: 10), Event(name: "SessionEnd", timeout: 10),
        Event(name: "UserPromptSubmit", timeout: 10),
        Event(name: "PreToolUse", timeout: 10), Event(name: "PostToolUse", timeout: 10),
        Event(name: "PermissionRequest", timeout: 120),
        Event(name: "Stop", timeout: 10),
        Event(name: "SubagentStart", timeout: 10), Event(name: "SubagentStop", timeout: 10),
    ], marker: "SessionStart")

    /// Gemini CLI has no permission hook: Yumi follows its sessions, the approvals stay in the terminal.
    static let gemini = HookTarget(id: "gemini-cli", name: "Gemini CLI", file: ".gemini/settings.json", events: [
        Event(name: "SessionStart", timeout: 10_000), Event(name: "SessionEnd", timeout: 10_000),
        Event(name: "BeforeAgent", timeout: 10_000), Event(name: "AfterAgent", timeout: 10_000),
        Event(name: "BeforeTool", timeout: 10_000), Event(name: "AfterTool", timeout: 10_000),
        Event(name: "Notification", timeout: 10_000),
    ], marker: "SessionStart")

    static let all = [claudeCode, codex, gemini]

    var pairs: [(String, Int)] { events.map { ($0.name, $0.timeout) } }

    /// "~/.codex/hooks.json", for the person.
    var shownPath: String { "~/" + file }

    func url(home: URL) -> URL { home.appendingPathComponent(file) }
}
