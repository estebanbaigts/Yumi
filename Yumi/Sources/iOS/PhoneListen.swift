import AVFoundation
import Speech
import SwiftUI

/// Yumi listens: a touch on him starts the microphone, a second touch sends what he heard. The
/// words are recognized on the iPhone when it can (`requiresOnDeviceRecognition` when supported);
/// nothing is recorded.
@MainActor
@Observable
final class PhoneListener {
    enum Access { case unknown, granted, denied }

    private(set) var listening = false
    /// What he understood so far.
    private(set) var heard = ""
    /// The sound level, 0…1, for the waves.
    private(set) var level: Double = 0
    private(set) var access: Access = .unknown

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: AppLanguage.locale)

    /// Asked once, at the first launch, with the other permissions.
    func ask() async -> Bool {
        let speech = await Self.askSpeech()
        let mic = await AVAudioApplication.requestRecordPermission()
        access = speech && mic ? .granted : .denied
        return speech && mic
    }

    func start() async {
        guard !listening else { return }
        if SFSpeechRecognizer.authorizationStatus() != .authorized || AVAudioApplication.shared.recordPermission != .granted {
            guard await ask() else { return }
        }
        guard let recognizer, recognizer.isAvailable else { access = .denied; return }
        heard = ""
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.removeTap(onBus: 0)
        Self.tap(input, format: format, request: request) { [weak self] level in self?.level = level }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); return }
        listening = true
        task = Self.recognize(recognizer, request) { [weak self] text, over in
            guard let self else { return }
            if let text { self.heard = text }
            if over, self.listening { self.halt() }
        }
    }

    /// Stops and gives what was heard (empty if nothing).
    @discardableResult
    func stop() -> String {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        halt()
        return text
    }

    private func halt() {
        guard listening else { return }
        listening = false
        level = 0
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The system calls these back on its own threads: they must not belong to the main actor.

    private nonisolated static func askSpeech() async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
    }

    private nonisolated static func tap(_ input: AVAudioInputNode, format: AVAudioFormat,
                                        request: SFSpeechAudioBufferRecognitionRequest,
                                        level: @escaping @MainActor @Sendable (Double) -> Void) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let value = Self.level(of: buffer)
            Task { @MainActor in level(value) }
        }
    }

    private nonisolated static func recognize(_ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
                                              heard: @escaping @MainActor @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let over = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in heard(text, over) }
        }
    }

    private nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return min(1, Double(sqrt(sum / Float(count))) * 12)
    }
}
