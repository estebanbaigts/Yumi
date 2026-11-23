import Foundation
import Observation

/// Shows the agent's approvals on the iPhone, one at a time, as a sheet. An answer only ever
/// comes from a tap on one of its buttons (the same rule as the island on the Mac).
@MainActor
@Observable
final class PhoneApprovals: ApprovalPresenter {
    private(set) var current: ApprovalRequest? {
        didSet { character?.asking(current != nil) }
    }
    @ObservationIgnored weak var character: PhoneCharacter?

    @ObservationIgnored private var waiting: [(ApprovalRequest, @MainActor () -> Void, @MainActor (ApprovalAnswer) -> Void)] = []
    @ObservationIgnored private var answerCurrent: (@MainActor (ApprovalAnswer) -> Void)?

    func present(_ approval: ApprovalRequest, shown: @escaping @MainActor () -> Void,
                 answer: @escaping @MainActor (ApprovalAnswer) -> Void) {
        waiting.append((approval, shown, answer))
        showNext()
    }

    func withdraw(_ approvalID: UUID) {
        waiting.removeAll { $0.0.id == approvalID }
        if current?.id == approvalID {
            current = nil
            answerCurrent = nil
            showNext()
        }
    }

    /// From a button of the sheet only.
    func answer(_ answer: ApprovalAnswer) {
        let reply = answerCurrent
        current = nil
        answerCurrent = nil
        reply?(answer)
        showNext()
    }

    private func showNext() {
        guard current == nil, !waiting.isEmpty else { return }
        let (approval, shown, answer) = waiting.removeFirst()
        current = approval
        answerCurrent = answer
        shown()
    }
}
