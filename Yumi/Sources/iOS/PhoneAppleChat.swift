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
    private let day: @Sendable () async -> String

    /// `day` describes today (events, reminders, weather) from what the person allowed.
    init(day: @escaping @Sendable () async -> String) {
        self.day = day
    }

    func reply(to text: String, knowledge: String) async throws -> String {
        let session = session ?? LanguageModelSession(tools: [DayTool(day: day)], instructions: Self.instructions(knowledge))
        self.session = session
        do {
            let answer = try await session.respond(to: text, options: GenerationOptions(maximumResponseTokens: 300))
            return answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // A long thread: start a new one rather than fail
            self.session = nil
            return try await reply(to: text, knowledge: knowledge)
        }
    }

    /// Forget the thread (the conversation was cleared).
    func reset() { session = nil }

    private static func instructions(_ knowledge: String) -> String {
        """
        Tu es Yumi, un petit compagnon chaleureux qui vit dans l'iPhone de la personne.
        Réponds en français, en une à trois phrases courtes, simplement, en la tutoyant.
        Pour tout ce qui touche à sa journée, son agenda, ses rendez-vous, ses rappels ou la météo, appelle l'outil « journee » et réponds seulement avec ce qu'il renvoie.
        N'invente jamais un rendez-vous, un rappel, une recette, un souvenir ou une information sur elle. Si tu ne sais pas, dis-le simplement.
        Ne répète pas la même phrase. Pas de tiret long.
        \(knowledge)
        """
    }
}

/// What the person has today, read from their calendar, reminders and weather (only what they
/// allowed the app to read). The model calls it instead of guessing.
@available(iOS 26, *)
private struct DayTool: FoundationModels.Tool {
    let name = "journee"
    let description = "Lit l'agenda, les rappels et la météo de la personne pour aujourd'hui."
    let day: @Sendable () async -> String

    @Generable
    struct Arguments {
        @Guide(description: "ce que la personne veut savoir de sa journée, en quelques mots")
        var question: String
    }

    @concurrent func call(arguments: Arguments) async throws -> String {
        await day()
    }
}
#endif
