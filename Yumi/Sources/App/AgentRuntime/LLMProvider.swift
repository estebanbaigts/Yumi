import Foundation

/// A language model, whoever provides it (Anthropic, OpenAI, Gemini, a local model). Text in,
/// text out: the runtime builds the request and reads the answer itself, so a provider only
/// has to carry them. A provider never sees the tools' code, the policy or the permissions,
/// and nothing it answers is run without going through `PlanValidator` and the executor.
protocol LLMProvider: Sendable {
    /// Shown in the debug panel and recorded with each plan.
    var name: String { get }
    func complete(_ request: LLMRequest) async throws -> LLMResponse
}

struct LLMRequest: Equatable, Sendable {
    /// The rules for the model.
    var system: String
    var messages: [LLMMessage]
    /// The answer must be a single JSON object. Providers with a JSON mode can turn it on.
    var expectsJSON: Bool
    var maxOutputTokens: Int
    /// For a plan: the tools it may use, so that a provider able to constrain its answer (Apple's
    /// guided generation) can do so. The prompt already lists them for the others.
    var tools: [ToolDescriptor] = []
    var maxSteps = 12
    /// An answer is awaited right now (a question asked aloud): the engines that can choose
    /// take their fastest model.
    var fast = false
}

struct LLMMessage: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var content: String
    /// A picture that goes with the text (a capture of the screen for "Montre-moi"). The engines
    /// that cannot see answer `unavailable`, so the next one that can is asked.
    var image: LLMImage? = nil
}

/// A picture sent to a model, already encoded (JPEG or PNG).
struct LLMImage: Equatable, Sendable {
    var data: Data
    var mediaType: String = "image/jpeg"
    var base64: String { data.base64EncodedString() }
}

extension LLMRequest {
    /// True when one of the messages carries a picture.
    var hasImage: Bool { messages.contains { $0.image != nil } }
}

struct LLMResponse: Equatable, Sendable {
    var text: String
    /// The engine that answered, when several were tried (`EngineLLMProvider`).
    var engine: String? = nil
}

enum LLMProviderError: Error, Equatable, Sendable {
    /// No model is configured.
    case unavailable
    /// The model was reached but could not answer (network, quota, refusal).
    case failed(String)
}

/// What the runtime uses while no model is connected: it says so, it never invents a plan.
struct UnavailableLLMProvider: LLMProvider {
    var name: String { "none" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        throw LLMProviderError.unavailable
    }
}
