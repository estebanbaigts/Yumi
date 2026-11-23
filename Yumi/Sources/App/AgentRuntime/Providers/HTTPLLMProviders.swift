import Foundation

// OpenAI, Google Gemini and Ollama as `LLMProvider`s. Like `AnthropicLLMProvider`, each one only
// carries the request the runtime built: no tools, no context, no memory are added. A key is read
// from whoever created the provider (the app reads the Keychain) when a request is sent, and never
// appears in a log, an error or the audit.

typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// What every HTTP provider does with an answer: the status says whether the key was refused,
/// the body is read only when it went through.
enum HTTPProviderSupport {
    static let session: HTTPTransport = { try await URLSession.shared.data(for: $0) }

    static func send(_ request: URLRequest, with transport: HTTPTransport) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost].contains(error.code) && request.url?.host == "127.0.0.1" {
            // Ollama not started: as if it were not installed.
            throw LLMProviderError.unavailable
        } catch {
            throw LLMProviderError.failed("network: \((error as? URLError)?.code.rawValue.description ?? "unreachable")")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        // The body can echo the request: only the status is kept.
        case 401, 403: throw LLMProviderError.failed("key refused (HTTP \(status))")
        // Google answers an invalid key with 400 and the reason API_KEY_INVALID.
        case 400 where String(decoding: data, as: UTF8.self).contains("API_KEY_INVALID"):
            throw LLMProviderError.failed("key refused (HTTP 400)")
        case 404: throw LLMProviderError.failed("model not found (HTTP 404)")
        case 429:
            // Google says which quota blocks, and how long to wait; others only that it is a limit.
            if let quota = GeminiQuota(errorBody: data) { throw LLMProviderError.failed(quota.reason) }
            throw LLMProviderError.failed("quota or rate limit (HTTP 429)")
        default: throw LLMProviderError.failed("HTTP \(status)")
        }
    }

    static func text(_ value: String?) throws -> LLMResponse {
        guard let text = value?.nonEmptyTrimmed else { throw LLMProviderError.failed("empty answer") }
        return LLMResponse(text: text)
    }
}

/// OpenAI's Chat Completions API. Billed by OpenAI per use.
struct OpenAILLMProvider: LLMProvider {
    static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let defaultModel = "gpt-4o-mini"

    var model: String = OpenAILLMProvider.defaultModel
    var apiKey: @Sendable () -> String?
    var timeout: TimeInterval = 60
    var transport: HTTPTransport = HTTPProviderSupport.session

    var name: String { "openai:\(model)" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let key = apiKey()?.nonEmptyTrimmed else { throw LLMProviderError.unavailable }
        let data = try await HTTPProviderSupport.send(try urlRequest(for: request, key: key), with: transport)
        guard let body = try? JSONDecoder().decode(Answer.self, from: data) else { throw LLMProviderError.failed("unreadable answer") }
        return try HTTPProviderSupport.text(body.choices.first?.message.content)
    }

    func urlRequest(for request: LLMRequest, key: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "authorization")
        let messages = [Body.Message(role: "system", content: [.init(type: "text", text: request.system)])]
            + request.messages.map { message in
                var parts = [Body.Part(type: "text", text: message.content)]
                if let image = message.image {
                    parts.append(.init(type: "image_url", image_url: .init(url: "data:\(image.mediaType);base64,\(image.base64)")))
                }
                return Body.Message(role: message.role.rawValue, content: parts)
            }
        urlRequest.httpBody = try JSONEncoder().encode(Body(
            model: model, messages: messages, max_completion_tokens: request.maxOutputTokens,
            response_format: request.expectsJSON ? .init(type: "json_object") : nil))
        return urlRequest
    }

    private struct Body: Encodable {
        struct ImageURL: Encodable { var url: String }
        struct Part: Encodable { var type: String; var text: String? = nil; var image_url: ImageURL? = nil }
        struct Message: Encodable { var role: String; var content: [Part] }
        struct Format: Encodable { var type: String }
        var model: String
        var messages: [Message]
        var max_completion_tokens: Int
        var response_format: Format?
    }

    private struct Answer: Decodable {
        struct Choice: Decodable { struct Message: Decodable { var content: String? }; var message: Message }
        var choices: [Choice]
    }
}

/// Google's Gemini API (generateContent). Its free tier is enough to try Yumi.
struct GeminiLLMProvider: LLMProvider {
    static let defaultModel = "gemini-2.5-flash"

    var model: String = GeminiLLMProvider.defaultModel
    var apiKey: @Sendable () -> String?
    var timeout: TimeInterval = 60
    var transport: HTTPTransport = HTTPProviderSupport.session
    /// Called with the model that worked when the one asked for did not (the app saves it in
    /// the settings, where the person sees it).
    var remember: @Sendable (String) -> Void = { _ in }

    var name: String { "gemini:\(model)" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let key = apiKey()?.nonEmptyTrimmed else { throw LLMProviderError.unavailable }
        let data: Data
        do {
            data = try await HTTPProviderSupport.send(try urlRequest(for: request, key: key), with: transport)
        } catch LLMProviderError.failed(let reason)
                    where reason.hasPrefix("model not found") || reason == GeminiQuota.freeTierZero.reason {
            // Google renames and retires models, and gives some no free quota: ask once which
            // models this key can call, try one other (Flash-Lite, then Flash), and remember it.
            let freeTier = reason == GeminiQuota.freeTierZero.reason
            guard let other = await Self.usableModel(key: key, transport: transport, excluding: model, preferLite: freeTier) else {
                throw LLMProviderError.failed(freeTier ? GeminiQuota.noFreeModel : reason)
            }
            var retry = self
            retry.model = other
            do {
                data = try await HTTPProviderSupport.send(try retry.urlRequest(for: request, key: key), with: transport)
            } catch LLMProviderError.failed(let again) where again == GeminiQuota.freeTierZero.reason {
                throw LLMProviderError.failed(GeminiQuota.noFreeModel)
            }
            remember(other)
        }
        guard let body = try? JSONDecoder().decode(Answer.self, from: data) else { throw LLMProviderError.failed("unreadable answer") }
        let text = body.candidates?.first?.content?.parts?.compactMap(\.text).joined()
        return try HTTPProviderSupport.text(text)
    }

    func urlRequest(for request: LLMRequest, key: String) throws -> URLRequest {
        let path = "https://generativelanguage.googleapis.com/v1beta/models/\(model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model):generateContent"
        guard let url = URL(string: path) else { throw LLMProviderError.failed("invalid model name") }
        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        // In a header, never in the URL: a URL can end up in a log.
        urlRequest.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.httpBody = try JSONEncoder().encode(Body(
            systemInstruction: .init(parts: [.init(text: request.system)]),
            contents: request.messages.map { message in
                var parts = [Body.Part(text: message.content)]
                if let image = message.image {
                    parts.insert(.init(inline_data: .init(mime_type: image.mediaType, data: image.base64)), at: 0)
                }
                return .init(role: message.role == .user ? "user" : "model", parts: parts)
            },
            generationConfig: .init(maxOutputTokens: request.maxOutputTokens,
                                    responseMimeType: request.expectsJSON ? "application/json" : nil,
                                    // An answer awaited right now: no thinking first, it costs seconds
                                    thinkingConfig: request.fast ? .init(thinkingBudget: 0) : nil)))
        return urlRequest
    }

    private struct Body: Encodable {
        struct InlineData: Codable { var mime_type: String; var data: String }
        struct Part: Codable { var text: String? = nil; var inline_data: InlineData? = nil }
        struct System: Encodable { var parts: [Part] }
        struct Content: Encodable { var role: String; var parts: [Part] }
        struct Thinking: Encodable { var thinkingBudget: Int }
        struct Config: Encodable { var maxOutputTokens: Int; var responseMimeType: String?; var thinkingConfig: Thinking? = nil }
        var systemInstruction: System
        var contents: [Content]
        var generationConfig: Config
    }

    private struct Answer: Decodable {
        struct Candidate: Decodable { struct Content: Decodable { var parts: [Body.Part]? }; var content: Content? }
        var candidates: [Candidate]?
    }

    /// A model this key can call with generateContent, a Flash one first, the newest version first.
    static func usableModel(key: String, transport: HTTPTransport, excluding: String, preferLite: Bool = false) async -> String? {
        guard let models = await listModels(key: key, transport: transport) else { return nil }
        return pick(from: models, excluding: excluding, preferLite: preferLite)
    }

    /// A stable Flash model (Flash-Lite first when the free quota is the problem: it has the
    /// most generous one), newest version first.
    static func pick(from models: [String], excluding: String, preferLite: Bool = false) -> String? {
        let candidates = models.filter { $0 != excluding && !$0.contains("embedding") && !$0.contains("vision") }
        let stable = candidates.filter { !$0.contains("preview") && !$0.contains("exp") && !$0.contains("tts") && !$0.contains("image") }
        let lite = stable.filter { $0.contains("flash-lite") }
        let flash = stable.filter { $0.contains("flash") && !$0.contains("lite") }
        let order = preferLite ? [lite, flash, stable] : [flash, stable]
        return order.first(where: { !$0.isEmpty })?.sorted(by: >).first ?? candidates.first
    }

    /// The names (without « models/ ») of the models that support generateContent for this key.
    static func listModels(key: String, transport: HTTPTransport) async -> [String]? {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        guard let data = try? await HTTPProviderSupport.send(request, with: transport),
              let list = try? JSONDecoder().decode(ModelList.self, from: data) else { return nil }
        return list.models.filter { $0.supportedGenerationMethods?.contains("generateContent") ?? false }
            .map { $0.name.hasPrefix("models/") ? String($0.name.dropFirst(7)) : $0.name }
    }

    private struct ModelList: Decodable {
        struct Model: Decodable { var name: String; var supportedGenerationMethods: [String]? }
        var models: [Model]
    }
}

/// A model run by Ollama on this Mac. Nothing leaves the Mac; free.
struct OllamaLLMProvider: LLMProvider {
    static let base = URL(string: "http://127.0.0.1:11434")!

    /// nil or empty: no model chosen, the provider answers `unavailable`.
    var model: @Sendable () -> String?
    var timeout: TimeInterval = 180
    var transport: HTTPTransport = HTTPProviderSupport.session

    var name: String { "ollama:\(model() ?? "none")" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let model = model()?.nonEmptyTrimmed else { throw LLMProviderError.unavailable }
        var urlRequest = URLRequest(url: Self.base.appendingPathComponent("api/chat"), timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        let messages = [Body.Message(role: "system", content: request.system)]
            + request.messages.map { Body.Message(role: $0.role.rawValue, content: $0.content, images: $0.image.map { [$0.base64] }) }
        urlRequest.httpBody = try JSONEncoder().encode(Body(model: model, messages: messages, stream: false,
                                                            format: request.expectsJSON ? "json" : nil,
                                                            options: .init(num_predict: request.maxOutputTokens)))
        let data = try await HTTPProviderSupport.send(urlRequest, with: transport)
        guard let body = try? JSONDecoder().decode(Answer.self, from: data) else { throw LLMProviderError.failed("unreadable answer") }
        return try HTTPProviderSupport.text(body.message?.content)
    }

    /// The models installed in Ollama, or nil when it does not answer.
    static func installedModels(transport: HTTPTransport = HTTPProviderSupport.session) async -> [String]? {
        let request = URLRequest(url: base.appendingPathComponent("api/tags"), timeoutInterval: 2)
        guard let (data, response) = try? await transport(request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return nil }
        return tags.models.map(\.name)
    }

    private struct Body: Encodable {
        struct Message: Encodable { var role: String; var content: String; var images: [String]? = nil }
        struct Options: Encodable { var num_predict: Int }
        var model: String
        var messages: [Message]
        var stream: Bool
        var format: String?
        var options: Options
    }

    private struct Answer: Decodable {
        struct Message: Decodable { var content: String? }
        var message: Message?
    }

    private struct Tags: Decodable {
        struct Model: Decodable { var name: String }
        var models: [Model]
    }
}

/// What a Google 429 says, read from the standard error details (google.rpc.QuotaFailure and
/// google.rpc.RetryInfo). Only the kind of limit and the delay are kept: never the message,
/// which can quote the project.
enum GeminiQuota: Equatable {
    /// The free tier gives this model no requests at all for this project.
    case freeTierZero
    /// Too many requests this minute; wait `seconds` when Google says.
    case perMinute(seconds: Int?)
    /// The daily quota is used up (reset at midnight Pacific time).
    case perDay

    static let noFreeModel = "quota no-free-model"

    var reason: String {
        switch self {
        case .freeTierZero: "quota free-tier-zero"
        case .perMinute(let seconds): "quota per-minute" + (seconds.map { " \($0)" } ?? "")
        case .perDay: "quota per-day"
        }
    }

    init?(errorBody data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let details = error["details"] as? [[String: Any]] else { return nil }
        var violations: [[String: Any]] = []
        var delay: Int?
        for detail in details {
            let type = detail["@type"] as? String ?? ""
            if type.hasSuffix("QuotaFailure") { violations += detail["violations"] as? [[String: Any]] ?? [] }
            if type.hasSuffix("RetryInfo"), let text = detail["retryDelay"] as? String {
                delay = Double(text.trimmingCharacters(in: CharacterSet(charactersIn: "s"))).map { Int($0.rounded(.up)) }
            }
        }
        guard !violations.isEmpty else { return nil }
        let ids = violations.map { (($0["quotaId"] as? String) ?? "") + " " + (($0["quotaMetric"] as? String) ?? "") }
        let zero = violations.contains { ($0["quotaValue"] as? String) == "0" || ($0["quotaValue"] as? Int) == 0 }
        if zero && ids.contains(where: { $0.lowercased().contains("free") }) { self = .freeTierZero }
        else if ids.contains(where: { $0.contains("PerDay") }) { self = .perDay }
        else { self = .perMinute(seconds: delay) }
    }
}
