import Foundation

/// Keeps the memory in a file of Yumi's support folder and answers the island's requests
/// (Contracts/MemoryTypes.swift). Every change is saved at once and reported through `onChange`.
@MainActor
final class MemoryStore {
    private let fileURL: URL
    private let onChange: @MainActor (MemoryBook) -> Void
    private var observers: [NSObjectProtocol] = []

    private(set) var book = MemoryBook()

    init(fileURL: URL = AppIdentity.supportDirectory.appendingPathComponent("memoire.md"),
         onChange: @escaping @MainActor (MemoryBook) -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    /// Where an unreadable memory file is moved: `memoire.illisible-20261005-141200.md`.
    var unreadableCopy: URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return fileURL.deletingLastPathComponent()
            .appendingPathComponent("memoire.illisible-\(formatter.string(from: Date())).md")
    }

    /// Reads the file and starts listening to the island.
    func start() {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            book = MemoryBook(markdown: text)
        } else if FileManager.default.fileExists(atPath: fileURL.path) {
            // There but unreadable (not UTF-8, no permission): put aside, so that the next change
            // starts a new file instead of writing over what the person wrote.
            try? FileManager.default.moveItem(at: fileURL, to: unreadableCopy)
        }
        onChange(book)

        listen(.memorySetName) { store, info in
            guard let name = info["name"] as? String else { return }
            store.change { $0.setName(name) }
        }
        listen(.memoryRemember) { store, info in
            guard let text = info["text"] as? String else { return }
            store.change { $0.remember(text, kind: .person) }
        }
        listen(.memoryEdit) { store, info in
            guard let id = info["id"] as? String, let text = info["text"] as? String else { return }
            store.change { $0.edit(id: id, text: text) }
        }
        listen(.memoryDelete) { store, info in
            guard let id = info["id"] as? String else { return }
            store.change { $0.forget(id: id) }
        }
        listen(.memoryClear) { store, _ in
            store.change { $0.clear() }
        }
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    /// Applies a change, saves it and reports it. Nothing is written when nothing changed.
    func change(_ edit: (inout MemoryBook) -> Void) {
        var next = book
        edit(&next)
        guard next != book else { return }
        book = next
        save()
        onChange(book)
    }

    /// Writes the whole file through a temporary one, so a crash never leaves it half written.
    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try book.markdown.write(to: fileURL, atomically: true, encoding: .utf8)
            // Only the person may read what Yumi knows about them.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            // The memory stays in the app for this session; the next change tries again.
        }
    }

    private func listen(_ name: Notification.Name, _ handle: @escaping @MainActor (MemoryStore, [String: any Sendable]) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
            var info: [String: any Sendable] = [:]
            for (key, value) in note.userInfo ?? [:] {
                if let key = key as? String, let value = value as? String { info[key] = value }
            }
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self, info)
            }
        })
    }
}
