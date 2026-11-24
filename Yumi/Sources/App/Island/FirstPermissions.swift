import AVFoundation
import Speech

/// The first launch, once the name is given: every permission Yumi may need is asked in a row,
/// instead of one module at a time later. Each module asks the way it always does (its
/// « Autoriser » button), then the microphone and the speech recognition for asking aloud.
/// Asked once; what is refused stays refused until the person changes it.
@MainActor
enum FirstPermissions {
    static let askedKey = "yumi.firstPermissionsAsked"

    static func askAll() {
        guard !StudioMode.isOn, !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        Task {
            // One dialog at a time: the next one waits until the person answered the last
            for module in AppState.shared.modules where module.primaryAction == loc("Autoriser") {
                NotificationCenter.default.post(name: .moduleAction, object: nil,
                                                userInfo: ["module": module.id, "action": "primary"])
                try? await Task.sleep(for: .seconds(2))
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    SFSpeechRecognizer.requestAuthorization { _ in done.resume() }
                }
            }
        }
    }
}
