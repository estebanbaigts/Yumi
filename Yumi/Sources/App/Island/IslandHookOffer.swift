import Foundation

/// Once, when Claude Code is on the Mac without Yumi's hooks: Yumi offers to install them. The
/// answer opens the settings on Claude Code, which show the change before anything is written:
/// nothing is ever written from here.
@MainActor
enum IslandHookOffer {
    nonisolated private static let remarkID = "hooks-offer"
    private static var observer: NSObjectProtocol?
    private static var dismissed: NSObjectProtocol?

    /// A moment after the launch, when Yumi has nothing else to say.
    static func startIfNeeded() {
        let defaults = UserDefaults.standard
        guard HookOffer.offers(claudeCodeInstalled: EngineFactory.hasClaudeCode, hooksInstalled: HookServer.hooksInstalled(),
                               alreadyOffered: defaults.bool(forKey: HookOffer.defaultsKey), filming: IslandStudio.isOn) else { return }
        observer = NotificationCenter.default.addObserver(forName: .remarkAccepted, object: nil, queue: .main) { note in
            guard note.userInfo?["id"] as? String == remarkID else { return }
            MainActor.assumeIsolated {
                IslandActions.openSettings(.claudeCode)
                if AppState.shared.remark?.id == remarkID { AppState.shared.remark = nil }
            }
        }
        dismissed = NotificationCenter.default.addObserver(forName: .remarkDismissed, object: nil, queue: .main) { note in
            guard note.userInfo?["id"] as? String == remarkID else { return }
            MainActor.assumeIsolated { if AppState.shared.remark?.id == remarkID { AppState.shared.remark = nil } }
        }
        Task {
            // After the launch and the greeting
            try? await Task.sleep(for: .seconds(20))
            // Wait for a quiet moment, a few minutes at most
            for _ in 0..<20 where AppState.shared.remark != nil { try? await Task.sleep(for: .seconds(15)) }
            guard AppState.shared.remark == nil else { return }
            defaults.set(true, forKey: HookOffer.defaultsKey)
            AppState.shared.remark = YumiRemark(id: remarkID, text: loc("Je peux suivre tes sessions Claude Code. Je m'installe ?"),
                                                mood: .curious, action: loc("Voir"), duration: 20)
        }
    }
}
