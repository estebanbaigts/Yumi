import Testing
import Foundation

// An answer given on the iPhone is only a proposal: the Mac checks it again before acting.

@Suite struct YumiLinkTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var waiting: [LinkApproval] {
        [LinkApproval(id: "a1", sessionID: "s1", summary: "supprimer build", fingerprint: "f1",
                      expiresAt: now.addingTimeInterval(60))]
    }

    private func reply(_ id: String = "a1", fingerprint: String = "f1", answer: LinkReply.Answer = .allow,
                       sentAgo: TimeInterval = 5) -> LinkReply {
        LinkReply(approvalID: id, fingerprint: fingerprint, answer: answer, deviceName: "iPhone",
                  sentAt: now.addingTimeInterval(-sentAgo))
    }

    @Test func aFreshAnswerToAWaitingRequestIsAccepted() {
        #expect(LinkReplyCheck.verdict(for: reply(), waiting: waiting, now: now) == .accept(.allow))
        #expect(LinkReplyCheck.verdict(for: reply(answer: .deny), waiting: waiting, now: now) == .accept(.deny))
    }

    @Test func anUnknownRequestIsRefused() {
        #expect(LinkReplyCheck.verdict(for: reply("autre"), waiting: waiting, now: now) == .reject(.unknown))
        #expect(LinkReplyCheck.verdict(for: reply(), waiting: [], now: now) == .reject(.unknown))
    }

    @Test func aRequestThatChangedIsRefused() {
        #expect(LinkReplyCheck.verdict(for: reply(fingerprint: "f2"), waiting: waiting, now: now) == .reject(.changed))
    }

    @Test func anExpiredRequestIsRefused() {
        #expect(LinkReplyCheck.verdict(for: reply(), waiting: waiting, now: now.addingTimeInterval(61)) == .reject(.expired))
    }

    @Test func anOldOrFutureAnswerIsRefused() {
        #expect(LinkReplyCheck.verdict(for: reply(sentAgo: 121), waiting: waiting, now: now) == .reject(.stale))
        #expect(LinkReplyCheck.verdict(for: reply(sentAgo: -60), waiting: waiting, now: now) == .reject(.stale))
    }

    @Test func theLinkIsOffUntilThePersonTurnsItOn() {
        let defaults = UserDefaults(suiteName: "YumiLinkTests")!
        defaults.removePersistentDomain(forName: "YumiLinkTests")
        #expect(!LinkSetting.isOn(defaults))
        LinkSetting.set(true, defaults)
        #expect(LinkSetting.isOn(defaults))
        defaults.removePersistentDomain(forName: "YumiLinkTests")
    }

    @Test func theFingerprintIsStableAndFollowsTheRequest() {
        let a = LinkFingerprint.of(requestID: "r1", tool: "Bash", command: "rm -rf build")
        #expect(a == LinkFingerprint.of(requestID: "r1", tool: "Bash", command: "rm -rf build"))
        #expect(a != LinkFingerprint.of(requestID: "r1", tool: "Bash", command: "rm -rf src"))
        #expect(a != LinkFingerprint.of(requestID: "r2", tool: "Bash", command: "rm -rf build"))
    }
}
