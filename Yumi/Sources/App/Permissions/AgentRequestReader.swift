import Foundation

/// What a coding agent's permission request does (Claude Code, Codex, Gemini CLI…), read from
/// its tool and its command, said in plain words before the person answers: "supprimer le
/// dossier build", "pousser sur GitHub". Pure.
///
/// `harmless` marks what changes nothing and may be let through on its own when the person
/// chose so in the settings (`AgentRules`): reading, looking at git, running the tests. The
/// reading errs on the safe side: a command it does not know, a redirection, a substitution,
/// `sudo`, anything that deletes, sends, pushes or installs is never harmless.
struct AgentRequestReading: Equatable, Sendable {
    var kind: ActionKind
    var risk: RiskLevel
    /// After "Codex veut …": "lancer les tests", "supprimer build".
    var action: String
    /// Whether it can be undone, when that is known: "Ça ne se défait pas."
    var undo: String?
    var harmless: Bool
}

enum AgentRequestReader {
    static func read(tool: String, command: String) -> AgentRequestReading {
        if shellTools.contains(tool) { return shell(command) }
        if readTools.contains(tool) {
            return AgentRequestReading(kind: .read, risk: .low, action: loc("lire des fichiers"), undo: nil, harmless: true)
        }
        if editTools.contains(tool) {
            return AgentRequestReading(kind: .modify, risk: .medium, action: loc("modifier des fichiers"),
                                       undo: loc("Ça se défait avec git si le projet est suivi."), harmless: false)
        }
        if webTools.contains(tool) {
            return AgentRequestReading(kind: .send, risk: .high, action: loc("aller sur le web"), undo: nil, harmless: false)
        }
        if tool == "Task" || tool == "Agent" {
            return AgentRequestReading(kind: .run, risk: .medium, action: loc("lancer un sous-agent"), undo: nil, harmless: false)
        }
        return AgentRequestReading(kind: .other, risk: .high, action: loc("utiliser \(tool)"), undo: nil, harmless: false)
    }

    // MARK: Tools

    static let shellTools: Set<String> = ["Bash", "shell", "exec_command", "local_shell", "run_shell_command"]
    static let readTools: Set<String> = ["Read", "Glob", "Grep", "LS", "NotebookRead", "read_file", "read_many_files",
                                         "list_directory", "glob", "grep", "search_file_content"]
    static let editTools: Set<String> = ["Edit", "MultiEdit", "Write", "NotebookEdit", "apply_patch", "replace",
                                         "edit_file", "write_file"]
    static let webTools: Set<String> = ["WebFetch", "WebSearch", "web_fetch", "web_search", "google_web_search"]

    // MARK: Shell

    /// A command line: each part of a chain is read, and the riskiest one speaks for all.
    static func shell(_ line: String) -> AgentRequestReading {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return AgentRequestReading(kind: .run, risk: .medium, action: loc("lancer une commande"), undo: nil, harmless: false)
        }
        // Writing to a file, a substitution or a second line hide what really runs.
        let hidden = ["`", "$(", "<(", ">(", "\n"].contains { trimmed.contains($0) } || redirects(trimmed)
        if lowered(trimmed).contains("| sh") || lowered(trimmed).contains("| bash") || lowered(trimmed).contains("|sh") {
            return AgentRequestReading(kind: .run, risk: .critical, action: loc("lancer un script venu d'internet"),
                                       undo: loc("Ça ne se défait pas."), harmless: false)
        }
        let parts = split(trimmed).map(part).filter { !($0.kind == .read && $0.action.isEmpty) }
        guard var worst = parts.max(by: { $0.risk < $1.risk }) else {
            return AgentRequestReading(kind: .run, risk: .medium, action: loc("lancer une commande"), undo: nil, harmless: false)
        }
        worst.harmless = !hidden && parts.allSatisfy(\.harmless)
        if hidden && worst.risk < .medium { worst.risk = .medium }
        let meaningful = parts.filter { !$0.harmless }
        if meaningful.count > 1 {
            worst.action = loc("lancer \(meaningful.count) commandes, dont : \(worst.action)")
        }
        return worst
    }

    /// The parts of a chain: `a && b`, `a; b`, `a | b`, `a || b`. `cd` only moves, it says nothing.
    static func split(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if let open = quote {
                if char == open { quote = nil }
                current.append(char)
            } else if char == "\"" || char == "'" {
                quote = char
                current.append(char)
            } else if char == ";" || char == "|" || char == "&" {
                parts.append(current)
                current = ""
                // "&&" and "||" are one separator.
                let next = line.index(after: index)
                if next < line.endIndex, line[next] == char { index = next }
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// One command of a chain.
    static func part(_ text: String) -> AgentRequestReading {
        var words = text.split(separator: " ").map(String.init)
        // VAR=value before the command, and env.
        while let first = words.first, first.contains("="), !first.hasPrefix("-") { words.removeFirst() }
        if words.first == "env" { words.removeFirst() }
        guard let first = words.first else {
            return AgentRequestReading(kind: .read, risk: .safe, action: "", undo: nil, harmless: true)
        }
        let name = (first as NSString).lastPathComponent
        let rest = Array(words.dropFirst())
        let target = rest.last { !$0.hasPrefix("-") }.map(shortName) ?? ""

        // `bash -c 'rm -rf build'`: what counts is the script it runs.
        if ["bash", "sh", "zsh"].contains(name), let flag = rest.firstIndex(where: { ["-c", "-lc", "-ic", "-cl"].contains($0) }),
           flag + 1 < rest.count {
            let script = rest[(flag + 1)...].joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return shell(script)
        }
        switch name {
        case "cd":
            return AgentRequestReading(kind: .read, risk: .safe, action: "", undo: nil, harmless: true)
        case "sudo", "doas":
            return AgentRequestReading(kind: .other, risk: .critical, action: loc("agir en administrateur du Mac"),
                                       undo: loc("Ça peut toucher tout le Mac."), harmless: false)
        case "rm", "rmdir", "trash", "unlink", "shred":
            return delete(rest, target: target)
        case "git":
            return git(rest)
        case "curl", "wget", "http", "https", "ssh", "scp", "rsync", "ftp", "nc", "telnet":
            return AgentRequestReading(kind: .send, risk: .high, action: loc("contacter internet"),
                                       undo: nil, harmless: false)
        case "mv":
            return AgentRequestReading(kind: .modify, risk: .medium, action: loc("déplacer \(target)"), undo: nil, harmless: false)
        case "cp", "ditto":
            return AgentRequestReading(kind: .create, risk: .medium, action: loc("copier \(target)"), undo: nil, harmless: false)
        case "mkdir", "touch":
            return AgentRequestReading(kind: .create, risk: .medium, action: loc("créer \(target)"), undo: nil, harmless: false)
        case "chmod", "chown", "ln":
            return AgentRequestReading(kind: .modify, risk: .medium, action: loc("changer les droits de \(target)"), undo: nil, harmless: false)
        case "open":
            return AgentRequestReading(kind: .other, risk: .medium, action: loc("ouvrir \(target)"), undo: nil, harmless: false)
        case "kill", "killall", "pkill":
            return AgentRequestReading(kind: .other, risk: .high, action: loc("arrêter un programme"), undo: nil, harmless: false)
        default:
            break
        }
        if isTest(name, rest) {
            return AgentRequestReading(kind: .run, risk: .low, action: loc("lancer les tests"), undo: nil, harmless: true)
        }
        if let reading = install(name, rest) { return reading }
        if isBuild(name, rest) {
            return AgentRequestReading(kind: .run, risk: .medium, action: loc("compiler le projet"),
                                       undo: loc("Ça se refait."), harmless: false)
        }
        // find can delete, run or write; sed -i changes the file it reads.
        let writes = (name == "find" && rest.contains { ["-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"].contains($0) })
            || (name == "sed" && rest.contains { $0 == "-i" || $0.hasPrefix("-i") || $0 == "--in-place" || $0.hasPrefix("--in-place=") })
        if readCommands.contains(name), !writes {
            return AgentRequestReading(kind: .read, risk: .low, action: loc("lire des fichiers"), undo: nil, harmless: true)
        }
        return AgentRequestReading(kind: .run, risk: .medium, action: loc("lancer \(name)"), undo: nil, harmless: false)
    }

    /// Commands that only read and print.
    static let readCommands: Set<String> = ["ls", "cat", "head", "tail", "wc", "pwd", "echo", "printf", "grep", "egrep", "rg",
                                            "ag", "find", "fd", "which", "type", "file", "stat", "du", "df", "tree", "less",
                                            "more", "diff", "sort", "uniq", "date", "whoami", "uname", "basename", "dirname",
                                            "realpath", "true", "jq", "sed", "cut", "tr", "column", "nl"]

    private static func delete(_ args: [String], target: String) -> AgentRequestReading {
        let targets = args.filter { !$0.hasPrefix("-") }
        let wide = targets.contains { ["/", "~", "~/", "*", ".", "..", "$HOME"].contains($0) || $0.hasSuffix("/*") }
        if wide || targets.count > 25 {
            return AgentRequestReading(kind: .delete, risk: .critical, action: loc("supprimer beaucoup de fichiers"),
                                       undo: loc("Ça ne se défait pas."), harmless: false)
        }
        let rebuilt: Set<String> = ["build", "dist", "out", "node_modules", ".build", "DerivedData", "target", ".next",
                                    "__pycache__", ".cache", "coverage", ".pytest_cache"]
        if !targets.isEmpty, targets.allSatisfy({ rebuilt.contains(shortName($0)) }) {
            return AgentRequestReading(kind: .delete, risk: .medium, action: loc("supprimer \(target)"),
                                       undo: loc("Ça se reconstruit."), harmless: false)
        }
        return AgentRequestReading(kind: .delete, risk: .high, action: target.isEmpty ? loc("supprimer des fichiers") : loc("supprimer \(target)"),
                                   undo: loc("Ça ne se défait pas."), harmless: false)
    }

    private static func git(_ args: [String]) -> AgentRequestReading {
        let sub = args.first ?? ""
        let flags = Set(args.dropFirst())
        let looking = AgentRequestReading(kind: .read, risk: .low, action: loc("regarder l'historique git"), undo: nil, harmless: true)
        let reads: Set<String> = ["status", "log", "diff", "show", "blame", "rev-parse", "ls-files", "describe", "shortlog", "reflog"]
        if reads.contains(sub) { return looking }
        if sub == "branch", flags.isDisjoint(with: ["-d", "-D", "--delete", "-m", "-M", "-c", "-C"]) { return looking }
        if sub == "remote", flags.isEmpty || flags == ["-v"] { return looking }
        if sub == "tag", flags.isEmpty { return looking }
        if sub == "stash", args.dropFirst().first == "list" { return looking }

        if sub == "push" {
            if !flags.isDisjoint(with: ["--force", "-f", "--force-with-lease", "--delete", "-d"]) {
                return AgentRequestReading(kind: .publish, risk: .critical, action: loc("écraser l'historique sur le serveur"),
                                           undo: loc("Ça ne se défait pas, et les autres le verront."), harmless: false)
            }
            return AgentRequestReading(kind: .publish, risk: .high, action: loc("pousser sur le serveur git"),
                                       undo: loc("Les autres le verront."), harmless: false)
        }
        let discards = (sub == "reset" && flags.contains("--hard")) || sub == "clean" || sub == "restore"
            || (sub == "checkout" && (flags.contains("--") || flags.contains(".")))
        if discards {
            return AgentRequestReading(kind: .delete, risk: .high, action: loc("effacer des changements pas encore enregistrés"),
                                       undo: loc("Ça ne se défait pas."), harmless: false)
        }
        if sub == "commit" {
            return AgentRequestReading(kind: .modify, risk: .medium, action: loc("enregistrer un commit"),
                                       undo: loc("Ça se défait tant que ce n'est pas poussé."), harmless: false)
        }
        if ["fetch", "pull", "clone"].contains(sub) {
            return AgentRequestReading(kind: .read, risk: .medium, action: loc("récupérer du code depuis le serveur"), undo: nil, harmless: false)
        }
        return AgentRequestReading(kind: .modify, risk: .medium, action: loc("changer le dépôt git (\(sub))"), undo: nil, harmless: false)
    }

    /// Running the tests: they may run the project's code, but change nothing it keeps.
    static func isTest(_ name: String, _ args: [String]) -> Bool {
        let first = args.first ?? ""
        switch name {
        case "pytest", "jest", "vitest", "rspec", "phpunit", "mocha", "ava", "tap": return true
        case "npm", "pnpm", "yarn", "bun": return first == "test" || first == "t" || (first == "run" && args.dropFirst().first?.hasPrefix("test") == true)
        case "swift", "cargo", "go", "mvn", "gradle", "./gradlew", "dotnet", "deno", "mix", "make", "rake": return first == "test"
        case "xcodebuild": return args.contains("test")
        case "python", "python3": return args.starts(with: ["-m", "pytest"]) || args.starts(with: ["-m", "unittest"])
        default: return false
        }
    }

    private static func isBuild(_ name: String, _ args: [String]) -> Bool {
        let first = args.first ?? ""
        switch name {
        case "make", "xcodebuild", "xcodegen", "tsc", "vite", "webpack": return true
        case "swift", "cargo", "go", "dotnet": return first == "build"
        case "npm", "pnpm", "yarn", "bun": return first == "run" && args.dropFirst().first?.hasPrefix("build") == true || first == "build"
        default: return false
        }
    }

    private static func install(_ name: String, _ args: [String]) -> AgentRequestReading? {
        let first = args.first ?? ""
        let installs: Bool = switch name {
        case "npm", "pnpm", "yarn", "bun": ["install", "i", "add", "ci"].contains(first)
        case "pip", "pip3", "pipx", "gem", "brew", "cargo", "go", "uv", "poetry", "composer": ["install", "add", "get"].contains(first)
        case "npx", "bunx", "pnpx": true
        default: false
        }
        guard installs else { return nil }
        return AgentRequestReading(kind: .run, risk: .high, action: loc("installer des paquets depuis internet"),
                                   undo: loc("Ça se désinstalle."), harmless: false)
    }

    /// `> file`, `>> file` outside quotes; `2>&1` and `>/dev/null` only redirect what is printed.
    private static func redirects(_ line: String) -> Bool {
        var quote: Character?
        let chars = Array(line)
        for (i, char) in chars.enumerated() {
            if let open = quote { if char == open { quote = nil }; continue }
            if char == "\"" || char == "'" { quote = char; continue }
            guard char == ">" else { continue }
            let after = String(chars[(i + 1)...]).trimmingCharacters(in: CharacterSet(charactersIn: "> "))
            if after.hasPrefix("&") || after.hasPrefix("/dev/null") { continue }
            return true
        }
        return false
    }

    private static func lowered(_ text: String) -> String { text.lowercased() }

    /// The last part of a path, quotes removed: "build", "main.swift".
    static func shortName(_ path: String) -> String {
        let clean = path.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        let trimmed = clean.hasSuffix("/") ? String(clean.dropLast()) : clean
        let last = (trimmed as NSString).lastPathComponent
        return last.isEmpty ? clean : last
    }
}

/// The person's rule for agents' requests (Settings › Claude Code): let through on its own what
/// changes nothing. Off until the person turns it on. Deleting, pushing, sending, installing or
/// paying always waits for a click.
enum AgentRules {
    static let harmlessKey = "agents.letHarmlessThrough"

    static func letsThrough(_ reading: AgentRequestReading, enabled: Bool) -> Bool {
        enabled && reading.harmless && reading.risk <= .low
    }
}
