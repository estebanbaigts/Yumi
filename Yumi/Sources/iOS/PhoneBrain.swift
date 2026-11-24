import Foundation

/// Who thinks and answers in the conversation: Apple's model on the iPhone, or one of the
/// person's own accounts (Claude, ChatGPT, Gemini), with its key kept in this iPhone's keychain.
/// Only the conversation goes to that service. Codex and Claude Code run on the Mac: they come
/// through the link with the Mac.
enum PhoneBrain: String, CaseIterable, Sendable {
    case apple
    case haiku = "claude-haiku-5-5"
    case sonnet = "claude-sonnet-5-5"
    case opus = "claude-opus-5-5"
    case chatgpt = "openai"
    case gemini = "gemini"

    enum Service: String { case apple, anthropic, openai, gemini }

    static let defaultsKey = "phoneBrain"

    var service: Service {
        switch self {
        case .apple: .apple
        case .haiku, .sonnet, .opus: .anthropic
        case .chatgpt: .openai
        case .gemini: .gemini
        }
    }

    /// The same keychain names as the Mac's engines.
    var keyName: String? {
        switch service {
        case .apple: nil
        case .anthropic: "anthropic-api-key"
        case .openai: "openai-api-key"
        case .gemini: "gemini-api-key"
        }
    }

    var label: String {
        switch self {
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
        case .apple: loc("Sur l'iPhone, rien ne sort")
        case .haiku: loc("Le plus rapide")
        case .sonnet: loc("Rapide et malin")
        case .opus: loc("Le plus réfléchi")
        case .chatgpt: loc("Avec ta clé OpenAI")
        case .gemini: loc("Avec ta clé Google AI Studio")
        }
    }

    /// Where the person creates the key.
    var keyHelp: String {
        switch service {
        case .apple: ""
        case .anthropic: "console.anthropic.com › API Keys"
        case .openai: "platform.openai.com › API keys"
        case .gemini: "aistudio.google.com › Get API key"
        }
    }

    static var current: PhoneBrain {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(PhoneBrain.init) ?? .apple }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var hasKey: Bool { keyName.flatMap { PhoneKeychain.get($0)?.nonEmptyTrimmed } != nil }

    /// The chosen account when its key is there, nil for Apple's model or without a key.
    static var remote: (any LLMProvider)? {
        let brain = current
        guard let name = brain.keyName, brain.hasKey else { return nil }
        let key: @Sendable () -> String? = { PhoneKeychain.get(name) }
        switch brain.service {
        case .anthropic: return AnthropicLLMProvider(model: brain.rawValue, apiKey: key)
        case .openai: return OpenAILLMProvider(apiKey: key)
        case .gemini: return GeminiLLMProvider(apiKey: key)
        case .apple: return nil
        }
    }
}
