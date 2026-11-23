import Testing
import Foundation

@Suite struct ShowMeTests {
    @Test func theWordsThatAskToPoint() {
        #expect(ShowMe.wants("Montre-moi où on change le fond d'écran"))
        #expect(ShowMe.wants("  où est le bouton exporter ?"))
        #expect(ShowMe.wants("Where do I click to share?"))
        #expect(!ShowMe.wants("Résume ce fichier"))
    }

    @Test func theCaptureGoesWithTheQuestion() {
        let capture = LLMImage(data: Data([1, 2, 3]))
        let request = ShowMe.request(question: "où est Exporter ?", capture: capture)
        #expect(request.hasImage)
        #expect(request.expectsJSON)
        #expect(request.messages.first?.content == "où est Exporter ?")
    }

    @Test func aPointInsideTheScreen() {
        let answer = ShowMe.parse(#"Voilà : {"answer": "Clique sur Fichier.", "x": 0.12, "y": 0.02, "label": "Menu Fichier"}"#)
        #expect(answer == ShowMe.Answer(text: "Clique sur Fichier.", point: .init(x: 0.12, y: 0.02), label: "Menu Fichier"))
    }

    @Test func aPointOutsideIsDropped() {
        let answer = ShowMe.parse(#"{"answer": "Ouvre Réglages.", "x": 1.4, "y": 0.5}"#)
        #expect(answer?.point == nil)
        #expect(answer?.text == "Ouvre Réglages.")
    }

    @Test func plainTextIsKept() {
        #expect(ShowMe.parse("Je ne le vois pas.") == ShowMe.Answer(text: "Je ne le vois pas."))
        #expect(ShowMe.parse("  ") == nil)
        #expect(ShowMe.parse(#"{"label": "x"}"#) == nil)
    }

    @Test func blindEnginesStepAside() async {
        let request = ShowMe.request(question: "où ?", capture: LLMImage(data: Data([0])))
        await #expect(throws: LLMProviderError.unavailable) {
            try await AppleLLMProvider().complete(request)
        }
    }
}

@Suite struct EngineImageTests {
    private let request = ShowMe.request(question: "où ?", capture: LLMImage(data: Data([0xFF, 0xD8])))

    @Test func anthropicSendsTheImageBlock() throws {
        let body = try AnthropicLLMProvider(model: "m", apiKey: { "k" }).urlRequest(for: request, key: "k").httpBody!
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains(#""type":"image""#))
        #expect(text.contains(#""media_type":"image\/jpeg""#) || text.contains(#""media_type":"image/jpeg""#))
        #expect(text.contains(#""data":"\/9g=""#) || text.contains(#""data":"/9g=""#))
    }

    @Test func openAISendsADataURL() throws {
        let body = try OpenAILLMProvider(model: "m", apiKey: { "k" }).urlRequest(for: request, key: "k").httpBody!
        #expect(String(decoding: body, as: UTF8.self).contains("base64,\\/9g=") || String(decoding: body, as: UTF8.self).contains("base64,/9g="))
    }
}

@Suite struct ClaudeCodePictureTests {
    @Test func thePictureGoesAsOneJSONLine() throws {
        let request = ShowMe.request(question: "où ?", capture: LLMImage(data: Data([0xFF, 0xD8])))
        let line = try ClaudeCodeLLMProvider.pictureInput(request)
        let object = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        let message = try #require(object["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])
        #expect(content.first?["type"] as? String == "image")
        #expect(content.last?["text"] as? String == "où ?")
        #expect(object["parent_tool_use_id"] is NSNull)
        #expect(object["session_id"] as? String == "")
        #expect(ClaudeCodeLLMProvider.arguments(system: "s", model: nil, picture: true).contains("stream-json"))
        #expect(!ClaudeCodeLLMProvider.arguments(system: "s", model: nil).contains("stream-json"))
    }

    @Test func theResultIsTheLastResultLine() {
        let output = Data("""
        {"type":"system","subtype":"init"}
        {"type":"assistant","message":{}}
        {"type":"result","subtype":"success","is_error":false,"result":"C'est en haut."}
        """.utf8)
        #expect(ClaudeCodeLLMProvider.resultLine(in: output)?["result"] as? String == "C'est en haut.")
        #expect(ClaudeCodeLLMProvider.resultLine(in: Data("{}".utf8)) == nil)
    }
}

@Suite struct ClaudeCodeLiveTests {
    @Test func onlyTheWebSearchIsAllowed() {
        let arguments = ClaudeCodeLLMProvider.liveArguments(system: "s", model: "haiku")
        let tools = arguments.firstIndex(of: "--tools").map { arguments[$0 + 1] }
        #expect(tools == "WebSearch")
        #expect(arguments.suffix(2) == ["--allowedTools", "WebSearch"])
        #expect(arguments.contains("--setting-sources"))
    }

    @Test func aWebSearchIsSeen() {
        let search: [String: Any] = ["type": "assistant", "message": ["content": [["type": "tool_use", "name": "WebSearch"]]]]
        let text: [String: Any] = ["type": "assistant", "message": ["content": [["type": "text", "text": "x"]]]]
        #expect(ClaudeCodeLive.usesWebSearch(search))
        #expect(!ClaudeCodeLive.usesWebSearch(text))
    }
}
