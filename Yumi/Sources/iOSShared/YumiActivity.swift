import ActivityKit
import AppIntents
import SwiftUI

/// A request of a coding agent on the Mac, shown on the iPhone's Lock Screen and in the Dynamic
/// Island. Shared by the app (which starts and updates it) and the widget extension (which draws it).
struct YumiApprovalActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var approvalID: String
        var fingerprint: String
        /// « supprimer build », « pousser sur le serveur git »
        var summary: String
        /// « Claude Code · Yumi »
        var source: String
        var expiresAt: Date
        /// Set once answered here: the buttons give way to the answer until the Mac confirms.
        var answered: String?
    }

    var deviceName: String
}

/// The buttons of the Live Activity. It runs in the app's process; on a locked iPhone, iOS asks
/// Face ID or the code first. The answer goes to the Mac, which checks it before doing anything.
struct LinkAnswerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Répondre à une demande du Mac"
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication
    static let isDiscoverable = false

    @Parameter(title: "Demande") var approvalID: String
    @Parameter(title: "Empreinte") var fingerprint: String
    @Parameter(title: "Autoriser") var allow: Bool

    init() {}

    init(approvalID: String, fingerprint: String, allow: Bool) {
        self.approvalID = approvalID
        self.fingerprint = fingerprint
        self.allow = allow
    }

    func perform() async throws -> some IntentResult {
        await LinkAnswers.send(approvalID: approvalID, fingerprint: fingerprint, allow: allow)
        return .result()
    }
}

/// Sends an answer given on the iPhone (a notification button, a Live Activity button, the app).
enum LinkAnswers {
    static func send(approvalID: String, fingerprint: String, allow: Bool) async {
        let reply = LinkReply(approvalID: approvalID, fingerprint: fingerprint, answer: allow ? .allow : .deny,
                              deviceName: "iPhone", sentAt: Date())
        try? await YumiLinks.current().send(reply)
        // The activity shows the answer at once; the next picture of the Mac closes it
        for activity in Activity<YumiApprovalActivity>.activities where activity.content.state.approvalID == approvalID {
            var state = activity.content.state
            state.answered = allow ? "allow" : "deny"
            await activity.update(ActivityContent(state: state, staleDate: state.expiresAt))
        }
    }
}

/// Yumi, small: the same dome, eyes and rim as the character, as plain shapes (a widget cannot
/// run the animated renderer).
struct YumiBadge: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            UnevenRoundedRectangle(topLeadingRadius: size * 0.5, bottomLeadingRadius: size * 0.18,
                                   bottomTrailingRadius: size * 0.18, topTrailingRadius: size * 0.5)
                .fill(.black)
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: size * 0.5, bottomLeadingRadius: size * 0.18,
                                           bottomTrailingRadius: size * 0.18, topTrailingRadius: size * 0.5)
                        .strokeBorder(LinearGradient(colors: [Color(red: 0.36, green: 0.55, blue: 1), Color(red: 0.93, green: 0.45, blue: 0.85)],
                                                     startPoint: .leading, endPoint: .trailing), lineWidth: size * 0.06)
                )
            HStack(spacing: size * 0.12) {
                eye
                eye
            }
            .offset(y: size * 0.04)
        }
        .frame(width: size, height: size * 0.82)
        .accessibilityHidden(true)
    }

    private var eye: some View {
        Ellipse().fill(.white).frame(width: size * 0.2, height: size * 0.24)
            .overlay(Circle().fill(.black).frame(width: size * 0.1).offset(x: size * 0.015, y: size * 0.02))
    }
}

/// Yumi living in the Dynamic Island: his face and the next thing of the day. Started by the app
/// when the person keeps it on (Réglages), updated each time the day changes while the app runs.
/// Without a server of ours, it cannot change on its own: its texts count down by themselves.
struct YumiDayActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// His picture (`happy`, `asking`, `asleep`…), drawn by the app.
        var face: String
        /// « Point avec Camille », « Acheter du pain », « Rien d'autre aujourd'hui »
        var title: String
        /// « 14:00 · Salle B », « Rappel en retard »
        var detail: String
        /// When it starts: the island counts down to it.
        var at: Date?
        /// A reminder past due, or a request of the Mac: shown in Yumi's warm colour.
        var urgent: Bool
        /// The SF Symbol of the kind: calendar, checklist, hand.raised.
        var symbol: String
    }
}
