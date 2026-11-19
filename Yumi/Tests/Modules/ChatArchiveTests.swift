import Foundation
import Testing

// The archive of past conversations.

@Suite struct ChatArchiveTests {
    @Test func theArchiveKeepsTheNewestFirstAndNoEmptyChat() {
        let a = SavedChat(id: UUID(), date: .now, lines: [.init(mine: true, text: "Une idée de dessert ?"), .init(mine: false, text: "Une tarte.")])
        let b = SavedChat(id: UUID(), date: .now, lines: [.init(mine: true, text: "Bonjour")])
        var list = ChatArchive.adding(a, to: [])
        list = ChatArchive.adding(b, to: list)
        #expect(list.map(\.id) == [b.id, a.id])
        #expect(ChatArchive.adding(SavedChat(id: UUID(), date: .now, lines: [.init(mine: true, text: "  ")]), to: list) == list)
        // Resumed then put back: one copy, at the head
        #expect(ChatArchive.adding(a, to: list).map(\.id) == [a.id, b.id])
        #expect(a.title == "Une idée de dessert ?")
        let many = (0..<50).reduce([SavedChat]()) { list, _ in ChatArchive.adding(b.with(UUID()), to: list) }
        #expect(many.count == ChatArchive.limit)
    }
}

private extension SavedChat {
    func with(_ id: UUID) -> SavedChat { SavedChat(id: id, date: date, lines: lines) }
}
