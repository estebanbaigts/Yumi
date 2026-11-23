import Foundation

// MARK: - Reducer (pure business rules)

/// Applies `YumiEvent`s to the session model. This is where the business
/// rules live, and it is a pure function, fully unit-testable without UI,
/// sockets or actors.
enum SessionReducer {
    /// Applies one event to the current session dictionary and returns the
    /// new dictionary.
    static func apply(_ event: YumiEvent, to sessions: [SessionID: Session]) -> [SessionID: Session] {
        var sessions = sessions

        switch event {
        case .agentRegistered:
            // Agents exist through their sessions for now. The event is part
            // of the contract so future features (agent presence, discovery)
            // can hook in without changing it.
            break

        case .sessionStarted(let id, let agent, let title):
            if sessions[id] == nil {
                sessions[id] = Session(id: id, agent: agent, title: title)
            }

        case .sessionEnded(let id):
            sessions.removeValue(forKey: id)

        case .sessionLocated(let id, let origin):
            var located = origin
            // A hook that does not name the model keeps the one already known
            if located.model == nil { located.model = sessions[id]?.origin?.model }
            sessions[id]?.origin = located

        case .promptSubmitted(let id, _):
            sessions[id]?.activity = .thinking
            sessions[id]?.status = .running
            sessions[id]?.isTurnActive = true

        case .toolStarted(let id, let tool):
            // Another tool of the same session (a sub-agent) must not hide a request still waiting.
            if case .requestingPermission = sessions[id]?.activity { break }
            sessions[id]?.activity = .working(tool)
            sessions[id]?.status = .running
            sessions[id]?.isTurnActive = true

        case .toolFinished(let id, _):
            // A tool ending must not erase a question or a permission request still on screen.
            if case .working = sessions[id]?.activity {
                sessions[id]?.activity = .idle
            }

        case .permissionRequested(let id, let request):
            sessions[id]?.activity = .requestingPermission(request)
            sessions[id]?.status = .waitingForUser
            sessions[id]?.isTurnActive = true

        case .permissionResolved(let id, let requestID):
            if case .requestingPermission(let request) = sessions[id]?.activity, request.id == requestID {
                sessions[id]?.activity = .idle
                sessions[id]?.status = .running
            }

        case .questionRequested(let id, let question):
            sessions[id]?.activity = .asking(question)
            sessions[id]?.status = .waitingForUser

        case .taskCompleted(let id):
            sessions[id]?.status = .completed
            sessions[id]?.activity = .idle
            sessions[id]?.isTurnActive = false

        case .sessionErrored(let id, _):
            sessions[id]?.status = .errored
            sessions[id]?.activity = .idle
            sessions[id]?.isTurnActive = false

        case .rateLimited(let id):
            sessions[id]?.status = .rateLimited
            sessions[id]?.activity = .idle

        case .activityNoted:
            break
        }

        // Whatever the event, the session it is about becomes the most recent one.
        if let id = event.sessionID, sessions[id] != nil {
            let latest = sessions.values.map(\.recency).max() ?? 0
            sessions[id]?.recency = latest + 1
        }

        return sessions
    }
}

// MARK: - Store (owns the truth)

/// Owns the authoritative session state. Multiple stores may consume the same
/// engine (the design supports several consumers, e.g. a debug recorder later).
actor SessionStore {
    private var sessions: [SessionID: Session] = [:]

    /// Applies one event and returns the resulting snapshot.
    func apply(_ event: YumiEvent) -> [SessionID: Session] {
        sessions = SessionReducer.apply(event, to: sessions)
        return sessions
    }

    /// Current state, for tests and debugging.
    func snapshot() -> [SessionID: Session] { sessions }
}
