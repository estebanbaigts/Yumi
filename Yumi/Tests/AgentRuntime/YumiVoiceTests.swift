import Testing
import Foundation

@Suite struct YumiVoiceTests {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "yumi-voice-tests")!
        d.removePersistentDomain(forName: "yumi-voice-tests")
        return d
    }

    @Test func theMacVoiceByDefault() {
        #expect(YumiVoice.stored(defaults()) == .mac)
        #expect(YumiVoice.mac.voiceID(defaults()) == nil)
    }

    @Test func theChosenIdentifiers() {
        let d = defaults()
        #expect(YumiVoice.man.voiceID(d) == "eVG5iZDsJ688yOVAzHya")
        #expect(YumiVoice.woman.voiceID(d) == "2Bw6lGa1gtuLBxobWyaD")
        d.set("  abc123  ", forKey: YumiVoice.womanIDKey)
        #expect(YumiVoice.woman.voiceID(d) == "abc123")
    }

    @Test func onlyTheAnswerGoesToElevenLabs() throws {
        let request = try YumiVoice.speechRequest(text: "Là, en haut à gauche.", voiceID: "eVG5/../x", key: "k")
        #expect(request.url?.path == "/v1/text-to-speech/eVG5x")
        #expect(request.value(forHTTPHeaderField: "xi-api-key") == "k")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["text"] as? String == "Là, en haut à gauche.")
        #expect(body["model_id"] as? String == "eleven_turbo_v2_5")
    }
}
