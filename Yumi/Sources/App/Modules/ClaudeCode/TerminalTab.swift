import AppKit

/// The very tab a session runs in, for the terminals that can be asked which one it is:
/// Terminal and iTerm2, through AppleScript. The others only come forward as an application,
/// and so does every terminal in the App Store build (sandboxed, it sends no Apple Event).
enum TerminalTab {
    static let terminal = "com.apple.Terminal"
    static let iTerm = "com.googlecode.iterm2"

    /// Only these characters reach a script: a tty path and a UUID need nothing else.
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/-")

    private static func safe(_ value: String) -> String? {
        value.isEmpty || value.unicodeScalars.contains(where: { !allowed.contains($0) }) ? nil : value
    }

    /// The script that selects the session's tab and brings its window forward, or nil when the
    /// terminal cannot be asked or the session did not say where it is.
    static func script(for origin: SessionOrigin, bundleID: String) -> String? {
        let tty = safe(origin.tty)
        switch bundleID {
        case iTerm:
            var tests: [String] = []
            if let id = safe(origin.terminalSessionID) { tests.append("unique id of s is \"\(id)\"") }
            if let tty { tests.append("tty of s is \"\(tty)\"") }
            guard !tests.isEmpty else { return nil }
            return """
            tell application id "\(iTerm)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if \(tests.joined(separator: " or ")) then
                                select w
                                select t
                                select s
                                activate
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        case terminal:
            guard let tty else { return nil }
            return """
            tell application id "\(terminal)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end tell
            return "missing"
            """
        default:
            return nil
        }
    }

    /// A path as the shell reads it, in single quotes: `'/Users/me/My file.png'`.
    static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The script that types `text` at the prompt of the session, without pressing Return, or nil
    /// when the terminal cannot be asked. Only iTerm2 can write into one session through AppleScript.
    static func typeScript(_ text: String, for origin: SessionOrigin, bundleID: String) -> String? {
        guard bundleID == iTerm else { return nil }
        var tests: [String] = []
        if let id = safe(origin.terminalSessionID) { tests.append("unique id of s is \"\(id)\"") }
        if let tty = safe(origin.tty) { tests.append("tty of s is \"\(tty)\"") }
        guard !tests.isEmpty else { return nil }
        let quoted = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        tell application id "\(iTerm)"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if \(tests.joined(separator: " or ")) then
                            tell s to write text "\(quoted)" newline no
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "missing"
        """
    }

    /// Types `text` at the session's prompt. False when the terminal cannot do it (or in the
    /// App Store build), so the caller falls back to the clipboard.
    static func type(_ text: String, into origin: SessionOrigin, bundleID: String) -> Bool {
        #if APPSTORE
        return false
        #else
        guard let source = typeScript(text, for: origin, bundleID: bundleID) else { return false }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil && result?.stringValue == "ok"
        #endif
    }

    private static let queue = DispatchQueue(label: "app.yumi.terminal-tab")

    /// Selects the session's tab in its running terminal. The application is already in front:
    /// when the tab cannot be found or Automation is refused, it stays as it is.
    static func select(_ origin: SessionOrigin, bundleID: String) {
        #if !APPSTORE
        guard let source = script(for: origin, bundleID: bundleID) else { return }
        queue.async {
            var error: NSDictionary?
            _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        }
        #endif
    }
}
