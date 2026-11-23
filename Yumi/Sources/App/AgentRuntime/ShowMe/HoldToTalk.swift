import Foundation

/// The right Option key held alone: Yumi listens while it is down, and looks at the screen
/// when it is released. A short tap, or Option used with another key (to type « or œ),
/// does nothing.
struct HoldToTalk: Equatable, Sendable {
    /// Key code of the right Option key in `flagsChanged` events.
    static let rightOption: UInt16 = 61
    /// Held at least this long before Yumi starts listening: a tap stays a tap.
    static let delay: TimeInterval = 0.3
    static let defaultsKey = "holdToTalkEnabled"

    enum Step: Equatable, Sendable {
        case nothing
        /// Start listening now.
        case listen
        /// Stop and answer what was heard.
        case answer
        /// Stop and drop what was heard (another key came in).
        case cancel
    }

    private(set) var downSince: TimeInterval?
    private(set) var listening = false

    init() {}

    /// The modifiers changed. `rightOptionDown` is the state of the right Option key;
    /// `others` is true when any other modifier is held.
    mutating func modifiers(keyCode: UInt16, rightOptionDown: Bool, others: Bool, at time: TimeInterval) -> Step {
        if others { return stop(.cancel) }
        guard keyCode == Self.rightOption else { return .nothing }
        if rightOptionDown {
            if downSince == nil { downSince = time }
            return .nothing
        }
        return stop(listening ? .answer : .nothing)
    }

    /// Called a moment after the key went down: starts listening if it is still held alone.
    mutating func tick(at time: TimeInterval) -> Step {
        guard let since = downSince, !listening, time - since >= Self.delay else { return .nothing }
        listening = true
        return .listen
    }

    /// A key was typed while Option was down: it was a shortcut, not a question.
    mutating func keyTyped() -> Step {
        stop(listening ? .cancel : .nothing)
    }

    private mutating func stop(_ step: Step) -> Step {
        let was = listening
        downSince = nil
        listening = false
        return was || step == .nothing ? step : .nothing
    }
}
