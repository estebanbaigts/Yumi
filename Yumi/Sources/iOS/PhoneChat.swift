import Foundation
import Observation

/// One line of the conversation, kept on the iPhone between launches.
struct PhoneMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case person, yumi }

    var id = UUID()
    var role: Role
    var text: String
    var date = Date()
}

/// The conversation with Yumi on the iPhone, on its own.
///
/// A message first goes to the agent: when it plans an action (a reminder, an event), the action
/// waits for the person's tap (`PhoneApprovals`) and is checked afterwards. Otherwise Yumi
/// answers with Apple's on-device model when this iPhone has it, and says plainly what he can
/// still do when it does not (older iPhone, Apple Intelligence off, model downloading).
@MainActor
@Observable
final class PhoneChat {
    private(set) var messages: [PhoneMessage] = []
    private(set) var isThinking = false

    /// Yumi on screen: he thinks while the answer comes, and shows how it went.
    @ObservationIgnored weak var character: PhoneCharacter?
    @ObservationIgnored private let agent: RuntimeAgent?
    @ObservationIgnored private let memory: MemoryStore?
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let model: any LLMProvider

    /// The live chat. `agent`, `memory` and `fileURL` are nil while filming.
    init(agent: RuntimeAgent?, memory: MemoryStore?, fileURL: URL?, model: any LLMProvider = AppleLLMProvider()) {
        self.agent = agent
        self.memory = memory
        self.fileURL = fileURL
        self.model = model
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([PhoneMessage].self, from: data) {
            messages = saved
        }
    }

    /// Filming mode: a conversation already there, nothing read or written.
    static func studio() -> PhoneChat {
        let chat = PhoneChat(agent: nil, memory: nil, fileURL: nil, model: UnavailableLLMProvider())
        chat.messages = PhoneStudio.conversation
        return chat
    }

    func send(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isThinking else { return }
        append(.init(role: .person, text: text))
        isThinking = true
        character?.thinking(true)
        var succeeded = true
        defer {
            isThinking = false
            character?.finished(success: succeeded)
        }
        guard let agent else {
            append(.init(role: .yumi, text: loc("En mode tournage, je fais semblant d'écouter.")))
            return
        }

        let request = AgentRequest(userIntent: text, conversation: conversation)
        let planned = await agent.plan(for: request)
        switch ChatRoute.route(planned, message: text) {
        case .agent(let plan):
            let result = await agent.execute(plan, for: request)
            // The same verdict as the island: written from the result, never by a model alone
            if let remark = AgentLook.remark(for: result) { append(.init(role: .yumi, text: remark.text)) }
            succeeded = result.status.succeeded
        case .blocked(let reason):
            succeeded = false
            append(.init(role: .yumi, text: reason))
        case .agendaKeptFromChat, .chat:
            succeeded = AppleModelAvailability.current.isAvailable
            append(.init(role: .yumi, text: await converse(text)))
        }
    }

    func clear() {
        messages = []
        save()
    }

    // MARK: - Conversation

    private var conversation: [ConversationTurn] {
        messages.suffix(8).map { ConversationTurn(role: $0.role == .person ? .person : .yumi, text: $0.text) }
    }

    private func converse(_ text: String) async -> String {
        let availability = AppleModelAvailability.current
        guard availability.isAvailable else { return Self.withoutModel(availability) }
        var system = ChatPhrases.engineSystemPrompt(characterName: AppIdentity.characterName)
        if let memory { system += "\n\n" + MemoryPrompt.knowledge(memory.book) + "\n\n" + MemoryNotes.instructions }
        let history = messages.suffix(8).map {
            LLMMessage(role: $0.role == .person ? .user : .assistant, content: $0.text)
        }
        let request = LLMRequest(system: system, messages: Array(history), expectsJSON: false, maxOutputTokens: 800)
        do {
            let answer = try await model.complete(request)
            let (visible, learnt) = MemoryNotes.extract(from: answer.text)
            if !learnt.isEmpty { memory?.change { MemoryNotes.apply(learnt, to: &$0) } }
            return VoiceRules.withoutLongDashes(visible)
        } catch {
            return loc("Je n'ai pas réussi à répondre. Redemande-moi.")
        }
    }

    /// What Yumi says when this iPhone cannot run Apple's model: why, and what still works.
    static func withoutModel(_ availability: AppleModelAvailability) -> String {
        let still = loc("Sans modèle, je sais déjà noter un rappel ou un rendez-vous : « rappelle-moi d'appeler maman demain 18 h ».")
        guard let why = whyNoModel(availability) else { return still }
        return why + "\n" + still
    }

    /// The same reasons as on the Mac, said for an iPhone.
    static func whyNoModel(_ availability: AppleModelAvailability) -> String? {
        switch availability {
        case .available: nil
        case .systemTooOld: loc("Pour discuter de tout, il me faut iOS 26 ou plus récent.")
        case .deviceNotEligible: loc("Cet iPhone ne peut pas faire tourner le modèle d'Apple.")
        case .appleIntelligenceOff: loc("Active Apple Intelligence dans Réglages, Apple Intelligence et Siri, et je pourrai discuter de tout.")
        case .modelDownloading: loc("Le modèle d'Apple se télécharge sur ton iPhone. Je m'en sers dès qu'il est prêt.")
        case .languageNotSupported: loc("Le modèle d'Apple ne parle pas encore ma langue sur cet iPhone.")
        }
    }

    private func append(_ message: PhoneMessage) {
        guard !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        messages.append(message)
        save()
    }

    private func save() {
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(messages.suffix(200))) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        }
    }
}
