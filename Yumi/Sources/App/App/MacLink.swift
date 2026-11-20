import Foundation

/// The Mac's side of the link with the iPhone (Contracts/YumiLink.swift). Off unless this build
/// carries an iCloud container and the person turned it on in the settings.
///
/// It publishes a summary of what the island already shows (sessions, coding agents' requests
/// waiting, GitHub), and reads the answers given on the iPhone. An answer is checked again by
/// `HookServer.answerFromLink` against what is really waiting before anything happens.
@MainActor
final class MacLink {
    static let shared = MacLink()

    private var loop: Task<Void, Never>?
    private var lastPublished: LinkSnapshot?
    private var lastPublishedAt = Date.distantPast

    func start() {
        guard loop == nil, YumiLinks.isBuiltIn, !StudioMode.isOn else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let waiting = await self?.tick() ?? false
                // Every 4 s while a request waits (the iPhone may answer), every 30 s otherwise
                try? await Task.sleep(for: .seconds(waiting ? 4 : 30))
            }
        }
    }

    /// One round: publish when something changed, read the answers. True when a request waits.
    private func tick() async -> Bool {
        let link = YumiLinks.current()
        guard await link.isAvailable() else { return false }
        let snapshot = Self.snapshot()
        var compared = snapshot
        compared.sentAt = lastPublished?.sentAt ?? snapshot.sentAt
        // A picture that did not change is sent again once a minute, so the iPhone knows the Mac is there
        if compared != lastPublished || Date().timeIntervalSince(lastPublishedAt) > 60 {
            do {
                try await link.publish(snapshot)
                lastPublished = snapshot
                lastPublishedAt = Date()
            } catch {
                return !snapshot.approvals.isEmpty
            }
        }
        for reply in (try? await link.takeReplies()) ?? [] {
            HookServer.shared.answerFromLink(reply)
        }
        return !snapshot.approvals.isEmpty
    }

    private static func snapshot() -> LinkSnapshot {
        let state = AppState.shared
        let sessions = state.tasks.filter { !$0.isIntegration || $0.state != .idle }.map { task in
            LinkSession(id: task.id, agent: task.agentName, project: task.name,
                        status: status(of: task.state), updatedAt: Date())
        }
        let github = state.modules.first { $0.id == "github" }.map { [$0.title, $0.subtitle].filter { !$0.isEmpty } } ?? []
        return LinkSnapshot(deviceName: Host.current().localizedName ?? "Mac", sentAt: Date(),
                            sessions: sessions, approvals: HookServer.shared.linkWaiting(), github: github)
    }

    private static func status(of state: BotState) -> String {
        switch state {
        case .working, .thinking, .searching: loc("travaille")
        case .approval: loc("attend ton accord")
        case .question: loc("te pose une question")
        case .error, .ratelimit: loc("bloqué")
        case .finished: loc("terminé")
        case .idle, .sleeping, .dizzy: loc("au repos")
        }
    }
}
