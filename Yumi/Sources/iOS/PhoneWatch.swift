import ARKit
import CoreMotion
import SwiftUI

/// « Yumi te regarde »: his eyes follow the tilt of the iPhone (CoreMotion), or, if the person
/// turned it on, their face (ARKit, the front camera). The gaze goes through the same path as the
/// mouse on the Mac: `BotEngine.setGaze`. Nothing is recorded; the camera runs only while the app
/// is in front, and stops at once otherwise. A finger on Yumi wins over both (`PhoneYumi`).
@MainActor
final class PhoneWatcher: NSObject {
    private let motion = CMMotionManager()
    private var session: ARSession?
    private weak var character: PhoneCharacter?
    private var active = false

    /// The setting or the app's state changed: start what is asked, stop the rest.
    func update(phone: Phone) {
        character = phone.character
        let wantsFace = phone.watchesOn && phone.watchesFace && ARFaceTrackingConfiguration.isSupported && !phone.studio
        let wantsTilt = phone.watchesOn && !wantsFace
        if active, wantsFace { startFace() } else { stopFace() }
        if active, wantsTilt { startTilt() } else { stopTilt() }
        if !phone.watchesOn || !active { phone.character.look(at: nil) }
    }

    /// The app came in front or went away.
    func setActive(_ on: Bool, phone: Phone) {
        active = on
        update(phone: phone)
    }

    // MARK: Tilt

    private func startTilt() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
            // Held upright, gravity points down the screen (y ≈ -0.7): that is « looking ahead »
            let x = max(-1, min(1, data.gravity.x * 1.6))
            let y = max(-1, min(1, (data.gravity.y + 0.7) * -1.6))
            MainActor.assumeIsolated { self.character?.look(at: CGPoint(x: x, y: y)) }
        }
    }

    private func stopTilt() {
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
    }

    // MARK: Face

    private func startFace() {
        guard session == nil else { return }
        Task { [weak self] in
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            do {
                guard granted, let self, self.session == nil, self.active else { return }
                let session = ARSession()
                session.delegate = self
                let configuration = ARFaceTrackingConfiguration()
                configuration.isLightEstimationEnabled = false
                session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                self.session = session
            }
        }
    }

    private func stopFace() {
        session?.pause()
        session = nil
    }

    fileprivate func saw(x: Double, y: Double) {
        character?.look(at: CGPoint(x: max(-1, min(1, x)), y: max(-1, min(1, y))))
    }
}

extension PhoneWatcher: ARSessionDelegate {
    /// Where the face is in front of the screen: its position from the camera, turned into a
    /// direction for his eyes. The picture of the camera is never kept.
    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard let face = anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else { return }
        let position = face.transform.columns.3
        let distance = max(0.2, Double(-position.z))
        // Mirrored: the person moving to their left is seen on the right of the camera
        let x = Double(-position.x) / distance * 3
        let y = Double(-position.y) / distance * 3
        Task { @MainActor [weak self] in self?.saw(x: x, y: y) }
    }
}
