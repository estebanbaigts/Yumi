import Foundation

/// The voice Yumi answers with when he is asked aloud: the Mac's own voice, or a natural
/// ElevenLabs voice (a man's or a woman's) with the person's key. Only Yumi's answer is sent
/// to ElevenLabs, never the question nor the screen.
enum YumiVoice: String, CaseIterable, Sendable {
    case mac, man, woman

    static let defaultsKey = "yumiVoice"
    static let keychainKey = "elevenlabs-api-key"
    /// The voice identifiers, changeable in the settings.
    static let manIDKey = "yumiVoice.man"
    static let womanIDKey = "yumiVoice.woman"
    static let defaultManID = "eVG5iZDsJ688yOVAzHya"
    static let defaultWomanID = "2Bw6lGa1gtuLBxobWyaD"
    /// ElevenLabs' natural multilingual model that still starts quickly (Flash sounds flatter).
    static let model = "eleven_turbo_v2_5"

    var label: String {
        switch self {
        case .mac:   return loc("Voix du Mac")
        case .man:   return loc("Voix d'homme (ElevenLabs)")
        case .woman: return loc("Voix de femme (ElevenLabs)")
        }
    }

    static func stored(_ defaults: UserDefaults = .standard) -> YumiVoice {
        defaults.string(forKey: defaultsKey).flatMap(YumiVoice.init) ?? .mac
    }

    /// The ElevenLabs voice identifier of this choice, nil for the Mac's voice.
    func voiceID(_ defaults: UserDefaults = .standard) -> String? {
        switch self {
        case .mac:   return nil
        case .man:   return defaults.string(forKey: Self.manIDKey)?.nonEmptyTrimmed ?? Self.defaultManID
        case .woman: return defaults.string(forKey: Self.womanIDKey)?.nonEmptyTrimmed ?? Self.defaultWomanID
        }
    }

    /// The request that turns `text` into speech (MP3).
    static func speechRequest(text: String, voiceID: String, key: String) throws -> URLRequest {
        let allowed = CharacterSet.alphanumerics
        let id = voiceID.unicodeScalars.filter { allowed.contains($0) }.map(String.init).joined()
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100_128")!,
                                 timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "model_id": model,
            "language_code": "fr",
            // Steady and warm: a low stability makes the voice jump between moods
            "voice_settings": ["stability": 0.6, "similarity_boost": 0.8, "style": 0.0, "use_speaker_boost": true],
        ])
        return request
    }
}
