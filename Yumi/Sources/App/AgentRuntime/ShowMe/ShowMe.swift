import Foundation

/// "Montre-moi": the person asks where something is on the screen, Yumi looks at one capture
/// taken at that moment and points at the place. He only points; he never clicks for them.
/// The capture goes to the engine of the settings (or stays on the Mac with Ollama) and is
/// not kept.
enum ShowMe {
    /// The words that ask Yumi to look and point, at the start of a message.
    private static let openers = [
        "montre-moi", "montre moi", "montres-moi", "où est", "ou est", "où se trouve", "où je clique",
        "où cliquer", "où dois-je cliquer", "où il faut cliquer", "comment je trouve",
        "show me", "where is", "where's", "where do i click", "where should i click",
    ]

    /// True when the message asks Yumi to look at the screen and point.
    static func wants(_ text: String) -> Bool {
        let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        return openers.contains { lowered.hasPrefix($0) }
    }

    static let system = """
    You are Yumi, a small character who lives in the notch of the person's Mac: a calm, warm, \
    loyal flatmate, not an assistant. The person talks to you out loud; their words were \
    transcribed, so they may have small mistakes: understand what they mean. You also see a \
    screenshot of their Mac taken as they spoke. Use it only when it helps; most of the time \
    they just want to talk, ask something or think out loud with you.
    Your answer is spoken by a voice. Talk the way a relaxed friend talks next to them: tutoie in \
    French, one to three short sentences (40 words at most), simple everyday words, calm and \
    even. No exclamation marks, no interjection like "Ha" or "Oh", no list, no symbol, no \
    parenthesis, no emoji, no assistant formula ("Bien sûr", "N'hésite pas", "Je suis là pour"), \
    no jargon. Match their mood: a joke when they are playful, plain and short when they are busy.
    When they ask about the world (a fact, a definition, news, a price, the weather) and the \
    answer is not on the screen, search the web if you can, then tell them the gist in your own \
    words, without links or sources read aloud. If you still do not know, say it simply.
    Answer with one JSON object and nothing else:
    {"answer": "what you say", "x": 0.0, "y": 0.0, "label": "two to four words"}
    Give x, y and label only when they ask where something is on the screen and you can see it: \
    the centre of that element, as fractions of the screenshot's width and height (0,0 is the \
    top-left corner). Otherwise leave them out. Never invent what you cannot see. Answer in the \
    language they speak.
    """

    /// The request for one question and one capture.
    static func request(question: String, capture: LLMImage) -> LLMRequest {
        LLMRequest(system: system, messages: [LLMMessage(role: .user, content: question, image: capture)],
                   expectsJSON: true, maxOutputTokens: 300, fast: true)
    }

    /// What Yumi says, and where he points when he found it.
    struct Answer: Equatable, Sendable {
        var text: String
        /// The place, as fractions of the screen from its top-left corner. Nil when not visible.
        var point: Point?
        /// A few words shown next to the pointer.
        var label: String?

        struct Point: Equatable, Sendable {
            var x: Double
            var y: Double
        }
    }

    /// Reads the model's answer. Tolerates text around the JSON; a point outside the screen
    /// is dropped; plain text without JSON is kept as the answer.
    static func parse(_ raw: String) -> Answer? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}"), start < end,
              let object = try? JSONSerialization.jsonObject(with: Data(trimmed[start...end].utf8)) as? [String: Any] else {
            return Answer(text: trimmed)
        }
        let text = (object["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let label = (object["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var point: Answer.Point?
        if let x = number(object["x"]), let y = number(object["y"]), (0...1).contains(x), (0...1).contains(y) {
            point = Answer.Point(x: x, y: y)
        }
        guard !text.isEmpty || point != nil else { return nil }
        return Answer(text: text, point: point, label: label?.isEmpty == false ? label : nil)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
