import AppKit
import SwiftUI

// MARK: - NSView drag destination
// Wired at the AppKit level in IslandWindowController (not via SwiftUI NSViewRepresentable)
// so it never interferes with SwiftUI hit-testing.

final class FileDropNSView: NSView {
    var onDragEntered: (() -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    // Pass all mouse events through — drag-drop uses NSDraggingDestination, not hitTest
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragExited?() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - File drop handler

enum FileDropHandler {
    /// Yumi was handed a file: he swallows it with a bounce, keeps a copy in his inbox, and
    /// the drop view asks what to do with it (summarize, send, put away).
    @MainActor
    static func handle(urls: [URL], state: AppState) {
        guard let url = urls.first else { return }
        let name = url.lastPathComponent

        // A new file is a new subject for the conversation
        IslandActions.newConversation()

        // Use the original URL first; swap to the inbox copy once the background copy finishes.
        state.droppedFile = DroppedFile(url: url, name: name)
        state.fileDragOver = false
        state.promptContext = .file(name: name, fileURL: url)
        state.contextAttached = true
        state.contextExplicit = true

        let inbox = AppIdentity.inboxDirectory
        Task.detached {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                await MainActor.run {
                    // Still the same file: the user may have dropped another one meanwhile
                    guard state.droppedFile?.url == url else { return }
                    state.droppedFile = DroppedFile(url: dest, name: name)
                    state.promptContext = .file(name: name, fileURL: dest)
                }
            }
        }

        // He swallows it first; the island opens once it is gone (IslandWindowController)
        BlackHole.shared.swallow(name)
        state.lastActivity = .now
    }
}

// MARK: - Swallowing a dropped file
//
// While a file is dragged over the island, Yumi opens his mouth. Let go, the file rises into
// it and is gone, he gulps, and only then the island opens on « J'en fais quoi ? ».

@MainActor
final class BlackHole: ObservableObject {
    static let shared = BlackHole()
    /// A file is over the island.
    @Published var open = false
    /// The file being swallowed, and when it started.
    @Published var swallowing: (name: String, start: Date)?

    static let swallowDuration: TimeInterval = 0.85
    /// The filming mode holds the swallow at this point to take its picture.
    var heldAt: Double?

    func swallow(_ name: String) {
        open = true
        swallowing = (name, .now)
        SoundEngine.shared.play("approve")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.swallowDuration) { [weak self] in
            NotificationCenter.default.post(name: .botGulp, object: nil)
            IslandModel.shared.pose(.boing)
            withAnimation(.easeOut(duration: 0.3)) {
                self?.open = false
                self?.swallowing = nil
            }
        }
    }
}

/// Yumi swallows the dropped file: his mouth open while it is over him, the file rises into
/// it and shrinks to nothing, then he gulps.
struct IslandBlackHole: View {
    @ObservedObject var hole = BlackHole.shared
    /// Yumi's size on screen (1 = 100 points wide).
    let scale: CGFloat
    private let green = Color(hex: "#3DDC97")

    var body: some View {
        TimelineView(.animation(paused: hole.swallowing == nil)) { context in
            let progress: Double = hole.heldAt ?? hole.swallowing.map { min(1, context.date.timeIntervalSince($0.start) / BlackHole.swallowDuration) } ?? 0
            if let swallowing = hole.swallowing { file(swallowing.name, progress: progress) }
        }
        .allowsHitTesting(false)
        .onChange(of: hole.open) { _, open in
            // He opens his mouth while a file is over him
            IslandModel.shared.setMood(open ? .surprised : nil, force: true)
        }
    }

    /// The file comes up from under him, slows down at his mouth and is gone.
    private func file(_ name: String, progress: Double) -> some View {
        let eased = 1 - pow(1 - progress, 3)
        let start = 70 + 120 * scale
        let mouth = 18 * scale
        return HStack(spacing: 5) {
            Image(systemName: "doc.fill").foregroundStyle(green)
            Text(name).lineLimit(1)
        }
        .font(IslandTheme.text(11, .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: "#1C1C20")))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(green.opacity(0.5)))
        .fixedSize()
        .scaleEffect(x: max(0.02, 1 - eased), y: max(0.02, 1 - eased * 0.9))
        .rotationEffect(.degrees(sin(progress * .pi * 3) * 8 * (1 - progress)))
        .offset(y: start + (mouth - start) * eased)
        .opacity(progress > 0.92 ? (1 - progress) * 12 : 1)
    }
}
