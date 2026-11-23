import Foundation

/// Where an agent works and on what model: the repository and its branch, read from the files
/// of `.git` (no `git` process), and the model named by the hook or the session's transcript.
enum AgentPlace {
    struct Place: Equatable {
        var name: String
        var isRepository: Bool
        var branch: String?
    }

    /// The repository holding `directory` (its top folder's name and branch), or the folder itself.
    static func place(of directory: String, fileManager: FileManager = .default) -> Place? {
        guard !directory.isEmpty else { return nil }
        var url = URL(fileURLWithPath: directory).standardizedFileURL
        while url.path != "/" {
            let git = url.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: git.path, isDirectory: &isDirectory) {
                let gitDir = isDirectory.boolValue ? git : linkedGitDir(git, base: url)
                return Place(name: url.lastPathComponent, isRepository: true, branch: gitDir.flatMap(branch(in:)))
            }
            url.deleteLastPathComponent()
        }
        return Place(name: URL(fileURLWithPath: directory).lastPathComponent, isRepository: false, branch: nil)
    }

    /// A worktree's `.git` is a file: `gitdir: /path/to/repo/.git/worktrees/name`.
    private static func linkedGitDir(_ file: URL, base: URL) -> URL? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
    }

    /// `ref: refs/heads/main` gives "main"; a detached head gives its short hash.
    static func branch(in gitDir: URL) -> String? {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else { return nil }
        return branch(fromHead: head)
    }

    static func branch(fromHead head: String) -> String? {
        let text = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("ref: refs/heads/") { return String(text.dropFirst("ref: refs/heads/".count)) }
        return text.isEmpty ? nil : String(text.prefix(7))
    }

    /// The model a hook names (`model` as text, or `{ id, display_name }`), else the last one
    /// written in the session's transcript.
    static func model(in payload: [String: Any]) -> String? {
        if let text = payload["model"] as? String, !text.isEmpty { return text }
        if let object = payload["model"] as? [String: Any], let id = object["id"] as? String { return id }
        guard let path = payload["transcript_path"] as? String else { return nil }
        return model(inTranscript: URL(fileURLWithPath: path))
    }

    /// Reads only the end of the transcript: the last `"model":"…"` it holds.
    static func model(inTranscript url: URL, tail: UInt64 = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > tail ? size - tail : 0)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        return lastModel(in: text)
    }

    static func lastModel(in text: String) -> String? {
        guard let range = text.range(of: "\"model\":\"", options: .backwards) else { return nil }
        let rest = text[range.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let model = String(rest[..<end])
        return model.isEmpty || model == "<synthetic>" ? nil : model
    }

    /// "claude-opus-4-5-20251101" reads "Opus 4.5"; another name stays as it is.
    static func modelName(_ id: String) -> String {
        let parts = id.lowercased().split(separator: "-").map(String.init)
        guard parts.first == "claude", parts.count >= 2 else { return id }
        let family = ["opus", "sonnet", "haiku", "fable"].first { parts.contains($0) }
        guard let family else { return id }
        let numbers = parts.filter { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
        let name = family.prefix(1).uppercased() + family.dropFirst()
        return numbers.isEmpty ? name : name + " " + numbers.joined(separator: ".")
    }
}
