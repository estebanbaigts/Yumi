import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// The conversation with Apple's on-device model, the way it works well: short instructions,
/// short answers, and a tool that reads the person's real day instead of letting the model
/// guess it. One session keeps the thread until the conversation is cleared.
@available(iOS 26, *)
@MainActor
final class PhoneAppleChat {
    private var session: LanguageModelSession?
    private var dayGiven = ""

    /// `day` is today told from the real data (events, reminders, weather). It goes in the
    /// instructions: the small model names a tool more often than it calls it.
    func reply(to text: String, knowledge: String, day: String) async throws -> String {
        // A new day (or a changed agenda) starts a new thread with the right facts
        if session == nil || day != dayGiven {
            session = LanguageModelSession(instructions: Self.instructions(knowledge, day: day))
            dayGiven = day
        }
        guard let session else { return "" }
        do {
            let answer = try await session.respond(to: text, options: GenerationOptions(maximumResponseTokens: 300))
            return answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            self.session = nil
            return try await reply(to: text, knowledge: knowledge, day: day)
        }
    }

    /// Forget the thread (the conversation was cleared).
    func reset() { session = nil }

    private static func instructions(_ knowledge: String, day: String) -> String {
        """
        Tu es Yumi, un petit compagnon chaleureux qui vit dans l'iPhone de la personne.
        Réponds en français, en une à trois phrases courtes, simplement, en la tutoyant.
        Voici sa journée, telle que son agenda la donne. C'est la seule source pour ses rendez-vous, ses rappels et la météo :
        \(day)
        N'invente jamais un rendez-vous, un rappel, un souvenir ou une information sur elle. Si tu ne sais pas, dis-le simplement.
        Ne répète pas la même phrase. Pas de tiret long.
        \(knowledge)
        """
    }
}
#endif
