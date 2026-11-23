import Foundation

/// `LLMProvider` over Anthropic's Messages API. It only carries the request the runtime built:
/// what goes out is exactly `LLMRequest`, nothing else is added (no context, no memory, no
/// tools). The key is read when a request is sent, from whoever created the provider (the app
/// reads the Keychain); it never lives in this type, a log or an error.
struct AnthropicLLMProvider: LLMProvider {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    var model: String
    /// nil or empty: no key configured, the provider answers `unavailable`.
    var apiKey: @Sendable () -> String?
    var timeout: TimeInterval = 60
    var transport: Transport = { try await URLSession.shared.data(for: $0) }

    var name: String { "anthropic:\(model)" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let key = apiKey()?.nonEmptyTrimmed else { throw LLMProviderError.unavailable }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(try urlRequest(for: request, key: key))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw LLMProviderError.failed("network: \((error as? URLError)?.code.rawValue.description ?? "unreachable")")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // The body can echo the request: only the status and the API's error type are kept.
            let type = (try? JSONDecoder().decode(APIError.self, from: data))?.error.type
            throw LLMProviderError.failed("HTTP \(status)" + (type.map { " \($0)" } ?? ""))
        }
        guard let body = try? JSONDecoder().decode(MessageResponse.self, from: data) else {
            throw LLMProviderError.failed("unreadable answer")
        }
        let text = body.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        guard text.nonEmptyTrimmed != nil else { throw LLMProviderError.failed("empty answer") }
        return LLMResponse(text: text)
    }

    func urlRequest(for request: LLMRequest, key: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(key, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        let body = MessageRequest(
            model: model, max_tokens: request.maxOutputTokens, system: request.system,
            messages: request.messages.map { message in
                var blocks: [MessageRequest.Block] = []
                if let image = message.image {
                    blocks.append(.init(type: "image", source: .init(type: "base64", media_type: image.mediaType, data: image.base64)))
                }
                blocks.append(.init(type: "text", text: message.content))
                return .init(role: message.role.rawValue, content: blocks)
            })
        urlRequest.httpBody = try JSONEncoder().encode(body)
        return urlRequest
    }

    private struct MessageRequest: Encodable {
        struct Source: Encodable {
            var type: String
            var media_type: String
            var data: String
        }
        struct Block: Encodable {
            var type: String
            var text: String? = nil
            var source: Source? = nil
        }
        struct Message: Encodable {
            var role: String
            var content: [Block]
        }
        var model: String
        var max_tokens: Int
        var system: String
        var messages: [Message]
    }

    private struct MessageResponse: Decodable {
        struct Block: Decodable {
            var type: String
            var text: String?
        }
        var content: [Block]
    }

    private struct APIError: Decodable {
        struct Detail: Decodable { var type: String }
        var error: Detail
    }
}
