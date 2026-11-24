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
    /// The day told from the real data (`PhoneToday.told`): answers about the agenda come from
    /// there, never from a model. `true` for tomorrow.
    @ObservationIgnored var day: (@MainActor (Bool) -> String)?
    /// Apple's model with its tools, one thread until the conversation is cleared (iOS 26).
    @ObservationIgnored private var apple: AnyObject?

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
        let route = ChatRoute.route(planned, message: text)
        // Deleting or ticking off is not something he does on iPhone yet: he says so
        if case .agent = route {} else if Self.asksToDelete(text) {
            succeeded = false
            append(.init(role: .yumi, text: loc("Je ne sais pas encore effacer ou cocher tes rappels depuis ici. Touche la carte Rappels sur l'accueil pour les cocher dans l'app Rappels.")))
            return
        }
        // A question about the day: answered from the calendar itself, never guessed
        if case .agent = route {} else if let day, Self.asksAboutTheDay(text) {
            append(.init(role: .yumi, text: day(Self.meansTomorrow(text))))
            return
        }
        switch route {
        case .agent(let plan):
            let result = await agent.execute(plan, for: request)
            // The same verdict as the island: written from the result, never by a model alone
            if let remark = AgentLook.remark(for: result) { append(.init(role: .yumi, text: remark.text)) }
            succeeded = result.status.succeeded
        case .blocked(let reason):
            succeeded = false
            append(.init(role: .yumi, text: Self.readable(reason)))
        case .agendaKeptFromChat, .chat:
            succeeded = PhoneBrain.remote != nil || AppleModelAvailability.current.isAvailable
            append(.init(role: .yumi, text: await converse(text)))
        }
    }

    /// « qu'est-ce que j'ai aujourd'hui », « j'ai quoi de prévu demain », « mon agenda »...
    static func asksAboutTheDay(_ text: String) -> Bool {
        if ChatRoute.isPersonalAgenda(text) { return true }
        // A short follow-up: « et demain ? », « et aujourd'hui ? »
        let words = text.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" })
        if words.count <= 4, ["demain", "aujourd", "tomorrow", "today"].contains(where: text.lowercased().contains) { return true }
        let folded = " " + text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "’", with: "'") + " "
        let asks = ["de prevu", "j'ai quoi", "ma journee", "mes rappels", "mon programme", "what's on", "my day"]
        return asks.contains(where: folded.contains)
    }

    /// « efface mes rappels », « supprime le rendez-vous », « coche tout »...
    static func asksToDelete(_ text: String) -> Bool {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return ["efface", "supprime", "enleve", "retire", "coche", "annule", "delete", "remove"].contains(where: folded.contains)
    }

    static func meansTomorrow(_ text: String) -> Bool {
        let folded = text.lowercased()
        return folded.contains("demain") || folded.contains("tomorrow")
    }

    /// A reason meant for a person, not a code: « cannotPlan » never reaches the screen.
    static func readable(_ reason: String) -> String {
        let clean = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.contains(" ") else {
            return loc("Je ne sais pas encore faire ça sur iPhone. Je sais ajouter un rappel ou un rendez-vous, et te dire ce que tu as de prévu.")
        }
        return clean
    }

    func clear() {
        messages = []
        apple = nil
        save()
    }

    // MARK: - Conversation

    private var conversation: [ConversationTurn] {
        messages.suffix(8).map { ConversationTurn(role: $0.role == .person ? .person : .yumi, text: $0.text) }
    }

    private func converse(_ text: String) async -> String {
        if let remote = PhoneBrain.remote { return await converse(text, with: remote) }
        let availability = AppleModelAvailability.current
        guard availability.isAvailable else { return Self.withoutModel(availability) }
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            let chat = (apple as? PhoneAppleChat) ?? PhoneAppleChat()
            apple = chat
            do {
                let answer = try await chat.reply(to: text, knowledge: knowledge, day: day?(false) ?? "")
                return VoiceRules.withoutLongDashes(MemoryNotes.extract(from: answer).visible)
            } catch {
                return loc("Je n'ai pas réussi à répondre. Redemande-moi.")
            }
        }
        #endif
        return Self.withoutModel(availability)
    }

    /// A model of the person's own account: Yumi's voice, what he knows of the person and of the day, the last exchanges.
    private func converse(_ text: String, with remote: any LLMProvider) async -> String {
        let system = (AppLanguage.isEnglish
            ? "You are Yumi, a small friendly character living on the person's iPhone. Answer briefly and warmly, in plain sentences, without markdown, without long dashes. Your answer may be read aloud."
            : "Tu es Yumi, un petit personnage bienveillant qui vit dans l'iPhone de la personne. Réponds brièvement et chaleureusement, en phrases simples, sans markdown, sans tirets longs, en la tutoyant. Ta réponse peut être lue à voix haute.")
            + (knowledge.isEmpty ? "" : "\n" + knowledge)
            + ((day?(false)).map { "\n" + $0 } ?? "")
        var history = messages.suffix(12).map { LLMMessage(role: $0.role == .person ? .user : .assistant, content: $0.text) }
        if history.first?.role == .assistant { history.removeFirst() }
        if history.last?.content != text { history.append(LLMMessage(role: .user, content: text)) }
        do {
            let answer = try await remote.complete(LLMRequest(system: system, messages: history, expectsJSON: false, maxOutputTokens: 700))
            return VoiceRules.withoutLongDashes(MemoryNotes.extract(from: answer.text).visible)
        } catch {
            return loc("Je n'arrive pas à joindre \(PhoneBrain.current.label). Vérifie ta clé dans Réglages › Cerveau, ou ta connexion.")
        }
    }

    /// What Yumi knows of the person, short: a small model drowns in long instructions.
    private var knowledge: String {
        guard let memory else { return "" }
        var lines: [String] = []
        if let name = memory.book.name { lines.append("Elle s'appelle \(name).") }
        lines += memory.book.entries.prefix(6).map(\.text)
        return lines.isEmpty ? "" : "Ce que tu sais d'elle : " + lines.joined(separator: " ")
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
