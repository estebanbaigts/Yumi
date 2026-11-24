import Foundation

// The link between Yumi on the Mac and Yumi on the iPhone.
//
// Each app works alone. When the person turns the link on, on both devices, they meet in the
// person's own iCloud (CloudKit, private database): never a server of ours. The Mac publishes a
// summary of what it follows (agent sessions, approvals waiting, GitHub); the iPhone shows it
// and may send back an answer to an approval. That answer is only a proposal: the Mac checks it
// again (`LinkReplyCheck`) before anything happens, and refuses anything stale or unknown.
//
// Plain types only: the CloudKit transport lives in each app, behind `YumiLink`.

/// Whether the link is on, on this device. Off until the person turns it on.
enum LinkSetting {
    static let key = "yumiLinkEnabled"

    static func isOn(_ defaults: UserDefaults = .standard) -> Bool { defaults.bool(forKey: key) }
    static func set(_ on: Bool, _ defaults: UserDefaults = .standard) { defaults.set(on, forKey: key) }
}

/// One agent session the Mac follows, as the other device shows it.
struct LinkSession: Codable, Equatable, Sendable, Identifiable {
    var id: String
    /// "Claude Code", "Codex", "Gemini".
    var agent: String
    var project: String
    /// What it is doing, in a few words: « travaille », « attend ton accord », « terminé ».
    var status: String
    var updatedAt: Date
}

/// An approval waiting on the Mac. The text is what the Mac already shows; nothing more leaves it.
struct LinkApproval: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var sessionID: String
    /// What the request does, in plain words (Permissions/AgentRequestReader).
    var summary: String
    /// Ties an answer to this exact request: the Mac recomputes it before acting.
    var fingerprint: String
    var expiresAt: Date
}

/// What the Mac publishes. Small on purpose: a summary, never a file or a window.
struct LinkSnapshot: Codable, Equatable, Sendable {
    var deviceName: String
    var sentAt: Date
    var sessions: [LinkSession] = []
    var approvals: [LinkApproval] = []
    /// One line per recent GitHub event: « PR #30 fusionnée ».
    var github: [String] = []
}

/// An answer given on the other device, from a tap of the person.
struct LinkReply: Codable, Equatable, Sendable {
    enum Answer: String, Codable, Sendable { case allow, deny }

    var approvalID: String
    var fingerprint: String
    var answer: Answer
    var deviceName: String
    var sentAt: Date
}

/// Ties an answer to the exact request it was given for. Not a secret: CloudKit already keeps
/// the data private; this only makes a request that changed refuse an older answer.
enum LinkFingerprint {
    static func of(requestID: String, tool: String, command: String) -> String {
        // FNV-1a, 64 bits: stable across launches and devices, unlike `Hasher`
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(requestID)\u{1F}\(tool)\u{1F}\(command)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// What the Mac does with an answer that came through the link. It never acts on trust.
enum LinkReplyCheck {
    enum Verdict: Equatable, Sendable {
        case accept(LinkReply.Answer)
        case reject(Reason)
    }

    enum Reason: Equatable, Sendable {
        /// The Mac has no such approval waiting (answered here, expired, or made up).
        case unknown
        /// The request changed since the answer was given.
        case changed
        case expired
        /// Sent too long ago: the person answered a situation that is gone.
        case stale
    }

    /// An answer older than this is ignored, even when the approval is still waiting.
    static let maximumAge: TimeInterval = 120

    static func verdict(for reply: LinkReply, waiting: [LinkApproval], now: Date) -> Verdict {
        guard let approval = waiting.first(where: { $0.id == reply.approvalID }) else { return .reject(.unknown) }
        guard approval.fingerprint == reply.fingerprint else { return .reject(.changed) }
        guard now < approval.expiresAt else { return .reject(.expired) }
        let age = now.timeIntervalSince(reply.sentAt)
        // A date far in the future is as suspect as one too old
        guard age <= maximumAge, age >= -30 else { return .reject(.stale) }
        return .accept(reply.answer)
    }
}

/// The iPhone saying it is there, once, when it first sees the Mac: a reply to no request,
/// shown on the island and never acted on. Its fingerprint carries the iPhone's name.
enum LinkHello {
    static let id = "yumi-hello"
}

/// The transport. Each app gives its own (CloudKit); `OffLink` when the link is off or iCloud
/// is not there, so that nothing ever depends on the other device.
protocol YumiLink: Sendable {
    /// False without an iCloud account, or with the link turned off.
    func isAvailable() async -> Bool
    /// The Mac: publish what it follows.
    func publish(_ snapshot: LinkSnapshot) async throws
    /// The iPhone: what the Mac published last, nil when nothing came yet.
    func latestSnapshot() async throws -> LinkSnapshot?
    /// The iPhone: send an answer. The Mac decides what to do with it.
    func send(_ reply: LinkReply) async throws
    /// The Mac: the answers that came, taken once.
    func takeReplies() async throws -> [LinkReply]
}

/// The link turned off: every device on its own.
struct OffLink: YumiLink {
    func isAvailable() async -> Bool { false }
    func publish(_ snapshot: LinkSnapshot) async throws {}
    func latestSnapshot() async throws -> LinkSnapshot? { nil }
    func send(_ reply: LinkReply) async throws {}
    func takeReplies() async throws -> [LinkReply] { [] }
}
