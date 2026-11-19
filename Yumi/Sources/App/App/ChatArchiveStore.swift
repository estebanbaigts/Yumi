import Foundation

/// Reads and writes the archive in Yumi's support folder. Nothing in the studio mode.
@MainActor final class ChatArchiveStore: ObservableObject {
    static let shared = ChatArchiveStore()

    @Published private(set) var chats: [SavedChat] = []
    /// The archived conversation the current chat continues, so it is put back in its place.
    var resumedID: UUID?

    private var file: URL { AppIdentity.supportDirectory.appendingPathComponent("conversations.json") }

    private init() {
        guard !StudioMode.isOn, let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([SavedChat].self, from: data) else { return }
        chats = list
    }

    /// Keeps the conversation on screen before it is cleared.
    func keep(_ messages: [ChatMessage]) {
        let lines = messages.map { SavedChat.Line(mine: $0.role == .user, text: $0.content) }
        let chat = SavedChat(id: resumedID ?? UUID(), date: .now, lines: lines)
        resumedID = nil
        chats = ChatArchive.adding(chat, to: chats)
        save()
    }

    func remove(_ id: UUID) {
        chats.removeAll { $0.id == id }
        save()
    }

    private func save() {
        guard !StudioMode.isOn, let data = try? JSONEncoder().encode(chats) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: [.atomic, .completeFileProtection])
    }
}
