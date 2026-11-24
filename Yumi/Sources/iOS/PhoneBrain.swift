import Foundation

/// Who thinks and answers in the conversation: Apple's model on the iPhone, or one of the
/// person's own accounts (Claude, ChatGPT, Gemini), with its key kept in this iPhone's keychain.
/// Only the conversation goes to that service. Codex and Claude Code run on the Mac: they come
/// through the link with the Mac.
enum PhoneBrain: String, CaseIterable, Sendable {
    /// The best one there: the Mac's Claude Code, else Gemini with its free key, else Apple's.
    case auto
    /// The person's own Claude Code, on their Mac, through iCloud: their subscription, no key.
    case mac
    case apple
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"
    case chatgpt = "openai"
    case gemini = "gemini"

    enum Service: String { case auto, mac, apple, anthropic, openai, gemini }

    static let defaultsKey = "phoneBrain"

    var service: Service {
        switch self {
        case .auto: .auto
        case .mac: .mac
        case .apple: .apple
        case .haiku, .sonnet, .opus: .anthropic
        case .chatgpt: .openai
        case .gemini: .gemini
        }
    }

    /// The same keychain names as the Mac's engines.
    var keyName: String? {
        switch service {
        case .auto, .mac, .apple: nil
        case .anthropic: "anthropic-api-key"
        case .openai: "openai-api-key"
        case .gemini: "gemini-api-key"
        }
    }

    var label: String {
        switch self {
        case .auto: loc("Automatique")
        case .mac: loc("Mon Mac · Claude Code")
        case .apple: loc("Modèle d'Apple")
        case .haiku: "Claude Haiku"
        case .sonnet: "Claude Sonnet"
        case .opus: "Claude Opus"
        case .chatgpt: "ChatGPT"
        case .gemini: "Gemini"
        }
    }

    var detail: String {
        switch self {
        case .auto: loc("Ton Mac s'il est allumé, sinon Gemini, sinon Apple")
        case .mac: loc("Ton abonnement Claude Code, par ton Mac")
        case .apple: loc("Sur l'iPhone, rien ne sort")
        case .haiku: loc("Le plus rapide")
        case .sonnet: loc("Rapide et malin")
        case .opus: loc("Le plus réfléchi")
        case .chatgpt: loc("Avec ta clé OpenAI")
        case .gemini: loc("Clé Google AI Studio gratuite")
        }
    }

    /// Where the person creates the key.
    var keyHelp: String {
        switch service {
        case .auto, .mac, .apple: ""
        case .anthropic: "console.anthropic.com › API Keys"
        case .openai: "platform.openai.com › API keys"
        case .gemini: "aistudio.google.com › Get API key"
        }
    }

    static var current: PhoneBrain {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(PhoneBrain.init) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var hasKey: Bool { keyName.flatMap { PhoneKeychain.get($0)?.nonEmptyTrimmed } != nil }

    /// Who answers now: the chosen one when it can, nil for Apple's model.
    @MainActor static var remote: (any LLMProvider)? { remote(for: current) }

    /// The one that answers right now, for the screens: « Mon Mac », « Gemini »…
    @MainActor static var answering: PhoneBrain {
        // Filming: the Mac answers, as it does once linked
        if StudioMode.isOn { return current == .auto ? .mac : current }
        switch current {
        case .auto: return macReady ? .mac : (gemini.hasKey ? .gemini : .apple)
        case .mac: return macReady ? .mac : .apple
        default: return current.hasKey ? current : .apple
        }
    }

    /// The Mac is there, recently, and can think with Claude Code.
    @MainActor static var macReady: Bool {
        guard LinkSetting.isOn(), let mac = PhoneLink.shared.mac else { return false }
        return Date().timeIntervalSince(mac.sentAt) < 90 && (mac.thinks ?? []).contains("claude-code")
    }

    @MainActor private static func remote(for brain: PhoneBrain) -> (any LLMProvider)? {
        switch brain {
        case .auto: return macReady ? PhoneMacThinker() : remote(for: .gemini)
        case .mac: return macReady ? PhoneMacThinker() : nil
        case .apple: return nil
        default: break
        }
        guard let name = brain.keyName, brain.hasKey else { return nil }
        let key: @Sendable () -> String? = { PhoneKeychain.get(name) }
        switch brain.service {
        case .anthropic: return AnthropicLLMProvider(model: brain.rawValue, apiKey: key)
        case .openai: return OpenAILLMProvider(apiKey: key)
        case .gemini: return GeminiLLMProvider(apiKey: key)
        default: return nil
        }
    }
}

/// Asks the Mac (`LinkAsk`) and waits for its answer, two minutes at most. Text only: a picture
/// goes to another model.
struct PhoneMacThinker: LLMProvider {
    var name: String { "mac:claude-code" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard !request.hasImage else { throw LLMProviderError.unavailable }
        let link = YumiLinks.current()
        let ask = LinkAsk(id: UUID().uuidString, system: request.system,
                          lines: request.messages.map { .init(fromPerson: $0.role == .user, text: $0.content) }, sentAt: Date())
        do { try await link.ask(ask) } catch { throw LLMProviderError.failed("link") }
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            try await Task.sleep(for: .milliseconds(1500))
            if let answer = try? await link.takeAnswer(for: ask.id) {
                if let text = answer.text { return LLMResponse(text: text, engine: "mac") }
                throw LLMProviderError.failed(answer.failure ?? "mac")
            }
        }
        throw LLMProviderError.failed("timeout")
    }
}

/// The model the agent plans with on the iPhone: the same as the conversation's (the Mac's
/// Claude Code, Gemini…) when there is one, Apple's otherwise. Every step it plans still waits
/// for the person's tap (`PhoneApprovals`).
struct PhoneBrainProvider: LLMProvider {
    var name: String { "phone-brain" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        if let remote = await MainActor.run(body: { PhoneBrain.remote }) {
            do { return try await remote.complete(request) } catch { /* Apple's below */ }
        }
        return try await AppleLLMProvider().complete(request)
    }
}
