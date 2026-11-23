import AVFoundation
import Speech

/// Turns what the person says into text while they hold the key, with Apple's speech
/// recognition forced on the Mac (`requiresOnDeviceRecognition`): the voice never leaves it
/// and nothing is recorded. Microphone and speech recognition are asked the first time only.
@MainActor
final class VoiceListener {
    enum Failure: Equatable {
        case microphoneRefused, speechRefused, unavailable
    }

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var heard = ""
    /// Called with the words heard so far, as they come.
    var onWords: ((String) -> Void)?

    /// Asks what is missing, then starts listening. Nil when it listens, the reason otherwise.
    func start() async -> Failure? {
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return .microphoneRefused }
        let speech = await Self.speechAuthorization()
        guard speech == .authorized else { return .speechRefused }
        guard let recognizer = Self.recognizer(), recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            return .unavailable
        }
        stop()
        heard = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.feeding(request))
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return .unavailable
        }
        task = recognizer.recognitionTask(with: request, resultHandler: Self.hearing { [weak self] text in
            self?.heard = text
            self?.onWords?(text)
        })
        return nil
    }

    /// Stops listening and gives the last words heard, after a short wait for the end of the sentence.
    func finish() async -> String {
        request?.endAudio()
        try? await Task.sleep(for: .milliseconds(250))
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        return text
    }

    func stop() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    // The audio and the recognizer call back on their own threads: these closures belong to no actor.

    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private nonisolated static func feeding(_ request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        { buffer, _ in request.append(buffer) }
    }

    private nonisolated static func hearing(_ words: @escaping @MainActor (String) -> Void)
        -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in words(text) }
        }
    }

    /// The recognizer for the app's language, or the Mac's when that one has none.
    private static func recognizer() -> SFSpeechRecognizer? {
        let preferred = Locale(identifier: AppLanguage.current == "en" ? "en-US" : "fr-FR")
        return SFSpeechRecognizer(locale: preferred) ?? SFSpeechRecognizer()
    }
}
