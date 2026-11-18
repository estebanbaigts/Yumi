import Foundation

// MARK: - Memory contract
// What Yumi remembers about the person (see design/voix.md). The core owns the
// store: it learns, saves and fills `AppState.memory` and `AppState.userName`. The island
// shows the memory and lets the person correct or erase it through the notifications
// below. Both sides rely on this file, so neither edits it during the parallel work.

/// One thing Yumi remembers, written as a short sentence in French.
struct MemoryEntry: Identifiable, Equatable, Sendable, Codable {
    enum Kind: String, Sendable, Codable, CaseIterable {
        /// About the person: habits, tastes, the way they work.
        case person
        /// About a project: its name, what is being done on it.
        case project
        /// The thread: what was asked lately, what is still open.
        case thread
    }
    let id: String
    var kind: Kind
    var text: String
    /// When it was learnt or last changed.
    var date: Date
}

extension Notification.Name {
    /// Posted by the island when the person gives or changes their first name.
    /// userInfo: ["name": String]
    static let memorySetName = AppIdentity.notification("memorySetName")
    /// Posted by the island for something the person said about themselves (their activity, at
    /// the first launch). userInfo: ["text": String]
    static let memoryRemember = AppIdentity.notification("memoryRemember")
    /// Posted by the island to correct one entry. userInfo: ["id": String, "text": String]
    static let memoryEdit = AppIdentity.notification("memoryEdit")
    /// Posted by the island to erase one entry. userInfo: ["id": String]
    static let memoryDelete = AppIdentity.notification("memoryDelete")
    /// Posted by the island to erase everything Yumi remembers, first name included.
    static let memoryClear = AppIdentity.notification("memoryClear")
}
