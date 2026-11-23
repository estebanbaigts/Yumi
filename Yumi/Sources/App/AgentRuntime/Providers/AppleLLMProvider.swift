import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can answer on this Mac, and if not, why, in words for the
/// person. Read from `SystemLanguageModel.default` on macOS 26 and later.
enum AppleModelAvailability: Equatable, Sendable {
    case available
    /// macOS 15, or a build made without the framework.
    case systemTooOld
    /// An Intel Mac, or a Mac Apple Intelligence does not support.
    case deviceNotEligible
    case appleIntelligenceOff
    /// Apple Intelligence is on and the model is still downloading.
    case modelDownloading
    /// The model does not speak the language Yumi speaks.
    case languageNotSupported

    var isAvailable: Bool { self == .available }

    /// Apple Intelligence can be turned on, or will be ready soon: worth a word at first launch.
    var canBecomeAvailable: Bool { self == .appleIntelligenceOff || self == .modelDownloading }

    /// The pane of System Settings where Apple Intelligence is turned on.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!

    /// One or two sentences for the island, without jargon. nil when the model is ready.
    var message: String? {
        switch self {
        case .available: nil
        case .systemTooOld:
            loc("Le modèle d'Apple demande macOS 26 ou plus récent. En attendant, je fonctionne en mode simple.")
        case .deviceNotEligible:
            loc("Ce Mac ne peut pas faire tourner le modèle d'Apple. Je fonctionne en mode simple : rappels, tâches, agenda et musique.")
        case .appleIntelligenceOff:
            loc("Pour me rendre plus malin gratuitement, active Apple Intelligence : Réglages Système, Apple Intelligence et Siri. En attendant, je fonctionne en mode simple.")
        case .modelDownloading:
            loc("Le modèle d'Apple est en cours de téléchargement sur ton Mac. Je m'en sers dès qu'il est prêt ; en attendant, je fonctionne en mode simple.")
        case .languageNotSupported:
            loc("Le modèle d'Apple ne parle pas encore ma langue sur ce Mac. Je fonctionne en mode simple.")
        }
    }

    /// The state of the settings: short.
    var detail: String {
        switch self {
        case .available: loc("Prêt, sur ce Mac.")
        case .systemTooOld: loc("Demande macOS 26.")
        case .deviceNotEligible: loc("Ce Mac n'est pas compatible.")
        case .appleIntelligenceOff: loc("Apple Intelligence est désactivé.")
        case .modelDownloading: loc("Modèle en cours de téléchargement.")
        case .languageNotSupported: loc("Langue pas encore prise en charge.")
        }
    }

    /// What this Mac says now.
    static var current: AppleModelAvailability {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return AppleFoundationModel.availability() }
        #endif
        return .systemTooOld
    }
}

/// Apple's on-device model (Foundation Models): free, no account, nothing leaves the Mac. Only
/// used when `AppleModelAvailability.current` is `.available`; otherwise it answers
/// `unavailable` and the next engine is tried, down to the simple mode.
struct AppleLLMProvider: LLMProvider {
    var name: String { "apple" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        // Apple's on-device model reads text only.
        guard !request.hasImage else { throw LLMProviderError.unavailable }
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return try await AppleFoundationModel.complete(request) }
        #endif
        throw LLMProviderError.unavailable
    }

    /// The answer of guided generation, as `PlannerPrompt.parse` reads it: the keys whose value
    /// is null are dropped, so that an argument left out stays out.
    static func withoutNulls(_ json: String) -> String {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data),
              let cleaned = try? JSONSerialization.data(withJSONObject: dropNulls(object)),
              let text = String(data: cleaned, encoding: .utf8) else { return json }
        return text
    }

    private static func dropNulls(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.filter { !($0.value is NSNull) }.mapValues(dropNulls)
        }
        if let array = value as? [Any] { return array.filter { !($0 is NSNull) }.map(dropNulls) }
        return value
    }

    /// The conversation as one prompt: the small model keeps no session between two messages,
    /// and its context is short, so only the last turns are given.
    static func prompt(for messages: [LLMMessage], keepingLast count: Int = 6) -> String {
        let recent = messages.suffix(count)
        guard let last = recent.last else { return "" }
        let earlier = recent.dropLast()
        guard !earlier.isEmpty else { return last.content }
        let transcript = earlier.map { "\($0.role == .user ? "Person" : "Yumi"): \($0.content)" }.joined(separator: "\n")
        return "Earlier in the conversation:\n\(transcript)\n\nNow:\n\(last.content)"
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
enum AppleFoundationModel {
    static func availability() -> AppleModelAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            let language = Locale(identifier: AppLanguage.isEnglish ? "en_US" : "fr_FR")
            return model.supportsLocale(language) ? .available : .languageNotSupported
        case .unavailable(.deviceNotEligible): return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
        case .unavailable(.modelNotReady): return .modelDownloading
        case .unavailable: return .deviceNotEligible
        }
    }

    static func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard availability() == .available else { throw LLMProviderError.unavailable }
        let session = LanguageModelSession(instructions: request.system)
        let prompt = AppleLLMProvider.prompt(for: request.messages)
        let options = GenerationOptions(maximumResponseTokens: request.maxOutputTokens)
        do {
            // A plan: the answer is held to the shape of a plan and to the tools given.
            if request.expectsJSON, !request.tools.isEmpty, let schema = try? planSchema(request.tools, maxSteps: request.maxSteps) {
                let response = try await session.respond(to: prompt, schema: schema, includeSchemaInPrompt: false, options: options)
                return LLMResponse(text: AppleLLMProvider.withoutNulls(response.content.jsonString))
            }
            let response = try await session.respond(to: prompt, options: options)
            return LLMResponse(text: response.content)
        } catch let error as LanguageModelSession.GenerationError {
            throw LLMProviderError.failed(reason(error))
        }
    }

    private static func reason(_ error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .exceededContextWindowSize: loc("la conversation est trop longue pour le modèle d'Apple, efface-la et recommence")
        case .guardrailViolation: loc("le modèle d'Apple a préféré ne pas répondre à ça")
        case .unsupportedLanguageOrLocale: loc("le modèle d'Apple ne parle pas encore cette langue")
        case .assetsUnavailable: loc("le modèle d'Apple n'est pas encore prêt sur ce Mac")
        case .rateLimited: loc("le modèle d'Apple est occupé, réessaie dans un instant")
        default: error.localizedDescription
        }
    }

    /// A plan, as `PlanProposal` decodes it: a goal and steps, each step one of the tools with
    /// its own arguments, or `cannotPlan`.
    static func planSchema(_ tools: [ToolDescriptor], maxSteps: Int) throws -> GenerationSchema {
        let steps = tools.map { tool -> DynamicGenerationSchema in
            var properties: [DynamicGenerationSchema.Property] = [
                .init(name: "description", description: "what this step does, in a few words", schema: .init(type: String.self)),
                .init(name: "tool", schema: .init(name: "tool_\(tool.id)", anyOf: [tool.id])),
            ]
            if !tool.inputSchema.fields.isEmpty {
                let fields = tool.inputSchema.fields.map { field -> DynamicGenerationSchema.Property in
                    let type: DynamicGenerationSchema = switch field.type {
                    case .string: .init(type: String.self)
                    case .number: .init(type: Double.self)
                    case .bool: .init(type: Bool.self)
                    }
                    return .init(name: field.name, description: field.description, schema: type, isOptional: !field.required)
                }
                properties.append(.init(name: "arguments", schema: .init(name: "arguments_\(tool.id)", properties: fields)))
            }
            return DynamicGenerationSchema(name: "step_\(tool.id)", description: tool.description, properties: properties)
        }
        let root = DynamicGenerationSchema(name: "plan", properties: [
            .init(name: "goal", description: "the goal, in one short sentence", schema: .init(type: String.self), isOptional: true),
            .init(name: "steps", schema: .init(arrayOf: .init(name: "step", anyOf: steps), minimumElements: 1, maximumElements: maxSteps),
                  isOptional: true),
            .init(name: "cannotPlan", description: "why the tools cannot do it, instead of goal and steps", schema: .init(type: String.self),
                  isOptional: true),
            .init(name: "isAction", description: "with cannotPlan: true when the person asked to change something on the Mac",
                  schema: .init(type: Bool.self), isOptional: true),
        ])
        return try GenerationSchema(root: root, dependencies: [])
    }
}
#endif
