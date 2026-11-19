import Foundation

/// A past conversation with Yumi, kept on this Mac so it can be read and resumed.
struct SavedChat: Codable, Identifiable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable {
        var mine: Bool
        var text: String
    }

    var id: UUID
    var date: Date
    var lines: [Line]

    /// Its first sentence, shortened: what the person asked first.
    var title: String {
        let first = lines.first { $0.mine }?.text ?? lines.first?.text ?? ""
        let clean = first.split(whereSeparator: \.isNewline).first.map(String.init) ?? first
        return clean.count > 60 ? String(clean.prefix(59)) + "…" : clean
    }
}

/// The list of past conversations. Pure: the file is read and written by `ChatArchiveStore`.
enum ChatArchive {
    /// The newest conversations kept; older ones go.
    static let limit = 40

    /// The list with one more conversation at its head. An empty one is not kept, and one
    /// resumed then put back replaces its earlier copy.
    static func adding(_ chat: SavedChat, to list: [SavedChat]) -> [SavedChat] {
        guard chat.lines.contains(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return list }
        return Array(([chat] + list.filter { $0.id != chat.id }).prefix(limit))
    }
}
