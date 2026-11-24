import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI

/// "Montre-moi" (AgentRuntime/ShowMe): one capture of the screen at the moment of the question,
/// sent to the engine of the settings that can see, then a pointer drawn over the screen where
/// the answer is. Nothing is clicked, and the capture is not kept.
@MainActor
final class ShowMeController {
    static let shared = ShowMeController()
    private let pointer = ShowMePointerWindow()

    /// What Yumi found: the sentence to show, and where he points (already drawn).
    struct Outcome {
        var text: String
        var engine: String?
        var pointed: Bool
    }

    /// Asked in the chat ("Montre-moi…"): the answer goes in the conversation.
    func answer(_ question: String, state: AppState) async {
        let outcome = await look(question)
        state.chatHistory.append(ChatMessage(role: .assistant, content: outcome.text,
                                             engine: Engine.named(outcome.engine)?.shortLabel))
        state.stateOverride = nil
        state.view = .prompt
    }

    /// Looks at the screen once, asks the engine, and draws the pointer when the place is visible.
    func look(_ question: String, prepared: (LLMImage, CGRect)? = nil) async -> Outcome {
        // The capture is tried first: `CGPreflightScreenCaptureAccess` can say no while the
        // permission is granted. Screen Recording is asked only when the capture fails, after
        // the person asked Yumi to look.
        guard let (capture, screen) = await { if let prepared { return prepared }; return await Self.capture() }() else {
            if !CGPreflightScreenCaptureAccess() {
                CGRequestScreenCaptureAccess()
                return Outcome(text: loc("Pour voir ton écran, autorise Yumi dans Réglages Système › Confidentialité › Enregistrement de l'écran, puis quitte-moi et rouvre-moi."), pointed: false)
            }
            return Outcome(text: loc("Je n'arrive pas à voir l'écran pour l'instant. Réessaie dans un instant."), pointed: false)
        }
        do {
            let response = try await Self.fastestProvider().complete(ShowMe.request(question: question, capture: capture))
            guard let answer = ShowMe.parse(response.text) else { return Outcome(text: ChatPhrases.noAnswer, pointed: false) }
            if let point = answer.point {
                pointer.show(at: point, label: answer.label, on: screen)
                lastPoint = (point, answer.label, screen)
                SoundEngine.shared.play("approve")
            }
            return Outcome(text: answer.text.isEmpty ? loc("C'est ici.") : answer.text, engine: response.engine,
                           pointed: answer.point != nil)
        } catch LLMProviderError.unavailable {
            return Outcome(text: loc("Pour voir l'écran, il me faut un moteur qui voit : Claude Code, une clé Anthropic, OpenAI ou Gemini, ou un modèle Ollama qui lit les images."), pointed: false)
        } catch LLMProviderError.failed(let reason) {
            return Outcome(text: ChatPhrases.engineFailed(loc("Le moteur"), reason: reason), pointed: false)
        } catch {
            return Outcome(text: ChatPhrases.noAnswer, pointed: false)
        }
    }

    /// Gemini answers a picture in a second or two when its key is set; Claude Code takes ten
    /// seconds or more. Otherwise the engines of the settings, in their order.
    private static func fastestProvider() -> any LLMProvider {
        let settings = EngineSettings.load()
        if EngineFactory.isReady(.gemini, settings), let gemini = EngineFactory.provider(.gemini, settings) {
            return ShowMeFallback(first: gemini, then: EngineFactory.planner, failedAt: geminiFailure.date)
        }
        return EngineFactory.planner
    }

    // MARK: Asked aloud (right Option held)

    private let listener = VoiceListener()
    private let bubble = ShowMeBubbleWindow()
    /// Where the last answer pointed, for « Montre-moi » in the island.
    private var lastPoint: (ShowMe.Answer.Point, String?, CGRect)?
    private var lastAnswer = ""
    private var voicePanel: IslandVoice { IslandVoice.shared }

    /// The island opens on what Yumi hears and answers.
    private func showInIsland(_ phase: IslandVoice.Phase) {
        voicePanel.phase = phase
        voicePanel.repeatAnswer = { [weak self] in self.map { $0.speak($0.lastAnswer) } }
        voicePanel.stopSpeaking = { [weak self] in self?.hush() }
        voicePanel.pointAgain = { [weak self] in
            guard let self, let (point, label, screen) = self.lastPoint else { return }
            self.pointer.show(at: point, label: label, on: screen)
        }
        NotificationCenter.default.post(name: .islandVoice, object: nil)
    }
    private var hold = HoldToTalk()
    private var holdTimer: Timer?
    /// Taken when the key goes down: what was on screen when the question started.
    private var earlyCapture: Task<(LLMImage, CGRect)?, Never>?

    /// While the person talks: the capture, and Claude Code started in advance when it answers.
    private func getReady() {
        earlyCapture = Task { await Self.capture() }
        #if !APPSTORE
        let settings = EngineSettings.load()
        if !EngineFactory.isReady(.gemini, settings),
           settings.active(isReady: { EngineFactory.isReady($0, settings) }) == .claudeCode, let binary = ClaudeCLI.find() {
            let folder = AppIdentity.supportDirectory.appendingPathComponent("planner").path
            Task.detached { ClaudeCodeLLMProvider.prepare(binary: binary, system: ShowMe.system, model: nil, folder: folder) }
        }
        #endif
    }

    /// The modifiers changed (from the island's keyboard monitor).
    func flagsChanged(keyCode: UInt16, rawFlags: UInt, at time: TimeInterval) {
        guard !StudioMode.isOn, LaunchPlan.current.chat,
              UserDefaults.standard.object(forKey: HoldToTalk.defaultsKey) as? Bool ?? true else { return }
        // NX_DEVICERALTKEYMASK: the right Option key alone, without the left one.
        let right = rawFlags & 0x40 != 0
        let others = rawFlags & 0x20 != 0
            || !NSEvent.ModifierFlags(rawValue: rawFlags).intersection([.command, .control, .shift]).isEmpty
        let step = hold.modifiers(keyCode: keyCode, rightOptionDown: right, others: others, at: time)
        if right, hold.downSince != nil, holdTimer == nil {
            let timer = Timer(timeInterval: HoldToTalk.delay, repeats: false) { _ in
                MainActor.assumeIsolated {
                    let shared = ShowMeController.shared
                    shared.holdTimer = nil
                    shared.perform(shared.hold.tick(at: ProcessInfo.processInfo.systemUptime))
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            holdTimer = timer
        }
        if !right { holdTimer?.invalidate(); holdTimer = nil }
        perform(step)
    }

    /// A key was typed somewhere: Option was part of a shortcut.
    func keyTyped() {
        perform(hold.keyTyped())
    }

    private func perform(_ step: HoldToTalk.Step) {
        switch step {
        case .nothing:
            break
        case .listen:
            voice.stopSpeaking(at: .immediate)
            player?.stop()
            getReady()
            lastPoint = nil
            voicePanel.canPoint = false
            showInIsland(.listening(""))
            listener.onWords = { [weak self] words in self?.voicePanel.phase = .listening(words) }
            Task {
                if let failure = await listener.start() {
                    hold = HoldToTalk()
                    showInIsland(.answer(question: loc("…"), text: Self.sentence(for: failure), note: ""))
                }
            }
        case .answer:
            Task {
                let clock = ContinuousClock(), start = clock.now
                func trace(_ step: String) {
                    #if DEBUG
                    print("[voix] \(step) +\((clock.now - start).formatted(.units(allowed: [.milliseconds])))")
                    fflush(stdout)
                    #endif
                }
                let question = await listener.finish()
                trace("question « \(question) »")
                let prepared = await earlyCapture?.value
                trace("capture prête")
                earlyCapture = nil
                guard !question.isEmpty else {
                    voicePanel.phase = .idle
                    ClaudeCodeLLMProvider.discardPrepared()
                    return
                }
                showInIsland(.looking(question: question, note: loc("Je regarde…")))
                ClaudeCodeLive.shared.onSearch = {
                    Task { @MainActor in
                        ShowMeController.shared.voicePanel.phase = .looking(question: question, note: loc("Je cherche sur internet…"))
                    }
                }
                let outcome = await look(question, prepared: prepared)
                trace("réponse (\(outcome.engine ?? "?")) « \(outcome.text) »")
                // The links are shown to click, never read aloud
                let parts = SpokenAnswer.split(outcome.text)
                lastAnswer = parts.text
                voicePanel.links = parts.links
                voicePanel.canPoint = outcome.pointed
                showInIsland(.answer(question: question, text: parts.text, note: nil))
                // Asked aloud, answered aloud: the voice of the Mac, nothing sent anywhere.
                speak(parts.text)
            }
        case .cancel:
            earlyCapture?.cancel()
            earlyCapture = nil
            ClaudeCodeLLMProvider.discardPrepared()
            listener.stop()
            voicePanel.phase = .idle
        }
    }

    private let voice = AVSpeechSynthesizer()

    private var player: AVAudioPlayer?

    /// The ElevenLabs voice when one is chosen and its key is set, the Mac's voice otherwise
    /// (and whenever ElevenLabs does not answer).
    private func speak(_ text: String) {
        voice.stopSpeaking(at: .immediate)
        player?.stop()
        voicePanel.speaking = true
        let choice = YumiVoice.stored()
        guard let id = choice.voiceID(), let key = KeychainStore.shared.get(YumiVoice.keychainKey)?.nonEmptyTrimmed,
              let request = try? YumiVoice.speechRequest(text: text, voiceID: id, key: key) else {
            speakLocally(text)
            return
        }
        Task {
            let asked = ContinuousClock.now
            let result = try? await URLSession.shared.data(for: request)
            let status = (result?.1 as? HTTPURLResponse)?.statusCode
            if let (data, _) = result, status == 200, let player = try? AVAudioPlayer(data: data) {
                // Stopped while ElevenLabs was answering: stay quiet
                guard self.voicePanel.speaking else { return }
                self.player = player
                player.play()
                self.watchSpeech()
                #if DEBUG
                print("[voix] ElevenLabs +\((ContinuousClock.now - asked).formatted(.units(allowed: [.milliseconds])))")
                #endif
            } else {
                // Said once under the answer, so a refused key does not pass for the Mac's choice
                let why = status == 401 ? loc("ElevenLabs refuse ta clé. Je parle avec la voix du Mac en attendant.")
                    : loc("ElevenLabs ne répond pas. Je parle avec la voix du Mac.")
                if case .answer(let question, let shown, _) = voicePanel.phase {
                    voicePanel.phase = .answer(question: question, text: shown, note: why)
                }
                if voicePanel.speaking { speakLocally(text) }
            }
        }
    }

    /// « Arrêter » turns back into « Répéter » once he has said it all.
    private func watchSpeech() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            while let self, self.voicePanel.speaking {
                if !self.voice.isSpeaking, self.player?.isPlaying != true {
                    self.voicePanel.speaking = false
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    /// Quiet at once: the person asked him to stop.
    func hush() {
        voice.stopSpeaking(at: .immediate)
        player?.stop()
        voicePanel.speaking = false
    }

    private func speakLocally(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(language: AppLanguage.current == "en" ? "en" : "fr")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.prefersAssistiveTechnologySettings = false
        voice.speak(utterance)
        watchSpeech()
    }

    /// The most natural voice installed for the language: Premium, then Enhanced (downloaded
    /// in Réglages Système › Accessibilité › Contenu énoncé), never the novelty voices.
    static func bestVoice(language: String) -> AVSpeechSynthesisVoice? {
        let region = language == "fr" ? "fr-FR" : "en-US"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(language) && !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis")
        }
        return voices.max { a, b in
            (a.quality.rawValue, a.language == region ? 1 : 0, a.identifier.contains("super-compact") ? 0 : 1)
                < (b.quality.rawValue, b.language == region ? 1 : 0, b.identifier.contains("super-compact") ? 0 : 1)
        } ?? AVSpeechSynthesisVoice(language: region)
    }

    private static func sentence(for failure: VoiceListener.Failure) -> String {
        switch failure {
        case .microphoneRefused: return loc("Pour t'écouter, autorise le micro pour Yumi dans Réglages Système › Confidentialité.")
        case .speechRefused:     return loc("Pour t'écouter, autorise la reconnaissance vocale pour Yumi dans Réglages Système › Confidentialité.")
        case .unavailable:       return loc("La reconnaissance vocale sur le Mac n'est pas prête. Ajoute la dictée dans Réglages Système › Clavier.")
        }
    }

    /// The screen under the pointer, without Yumi's own windows, as a JPEG at most 1280 points wide.
    private static func capture() async -> (LLMImage, CGRect)? {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == number }) else { return nil }
        let mine = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        // 1280 points wide is enough to find a button, and travels faster than the full screen
        // 1024 wide: about a third fewer picture tokens than 1280, and still readable
        let scale = min(1, 1024 / CGFloat(display.width))
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.showsCursor = false
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
              let jpeg = NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.55])
        else { return nil }
        return (LLMImage(data: jpeg), screen.frame)
    }
}

/// A small black bubble just under the notch: what Yumi hears, then what he answers.
@MainActor
final class ShowMeBubbleWindow {
    private var panel: NSPanel?
    private var hideLater: DispatchWorkItem?

    /// `keep`: stays until the next text. Otherwise it goes after a time that fits the text.
    func show(_ text: String, dim: Bool, keep: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let panel = self.panel ?? ShowMePointerWindow.makePanel()
        self.panel = panel
        let width: CGFloat = 460, height: CGFloat = 260
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - 40 - height,
                              width: width, height: height), display: false)
        panel.contentView = NSHostingView(rootView: ShowMeBubbleView(text: text, dim: dim))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hideLater?.cancel()
        guard !keep else { return }
        let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.hide() } }
        hideLater = item
        DispatchQueue.main.asyncAfter(deadline: .now() + min(12, 4 + Double(text.count) / 18), execute: item)
    }

    func hide() {
        hideLater?.cancel()
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }
}

private struct ShowMeBubbleView: View {
    let text: String
    let dim: Bool

    var body: some View {
        VStack {
            Text(text)
                .font(IslandTheme.round(14, .medium))
                .foregroundStyle(dim ? IslandTheme.fg.opacity(0.6) : IslandTheme.fg)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.9)))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A transparent window over the whole screen that draws the pointer, lets every click through
/// and goes away by itself.
@MainActor
final class ShowMePointerWindow {
    private var panel: NSPanel?
    private var hide: DispatchWorkItem?

    func show(at point: ShowMe.Answer.Point, label: String?, on frame: CGRect) {
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        panel.setFrame(frame, display: false)
        let spot = CGPoint(x: point.x * frame.width, y: point.y * frame.height)
        panel.contentView = NSHostingView(rootView: ShowMePointerView(spot: spot, label: label))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        hide?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
        hide = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: item)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; panel.animator().alphaValue = 0 },
                                             completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
    }

    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

/// The pointer: two soft rings that breathe around the place, and its name in a small black tag.
private struct ShowMePointerView: View {
    let spot: CGPoint
    let label: String?
    @State private var breathe = false

    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathe = true }
        }
    }

    private func content(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ZStack {
                Circle()
                    .strokeBorder(IslandTheme.blue.opacity(breathe ? 0.15 : 0.5), lineWidth: 2)
                    .frame(width: breathe ? 74 : 52, height: breathe ? 74 : 52)
                Circle()
                    .strokeBorder(IslandTheme.blue, lineWidth: 3)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 80, height: 80)
            .position(spot)
            if let label {
                Text(label)
                    .font(IslandTheme.round(13, .semibold))
                    .foregroundStyle(IslandTheme.fg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.85)))
                    .fixedSize()
                    // Kept inside the screen: a place in a corner (the Apple menu) still shows its name
                    .position(x: min(max(spot.x, 90), width - 90), y: spot.y + 44)
            }
        }
    }
}

/// Gemini first, and the engines of the settings whenever it fails, its daily limit
/// included: a question asked aloud always gets an answer.
/// When Gemini last failed (its daily limit, mostly): it is left aside for an hour.
private final class FailureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    var date: Date {
        get { lock.withLock { last } }
        set { lock.withLock { last = newValue } }
    }
}
private let geminiFailure = FailureClock()

private struct ShowMeFallback: LLMProvider {
    let first: any LLMProvider
    let then: any LLMProvider
    let failedAt: Date
    var name: String { "\(first.name) > \(then.name)" }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        if Date().timeIntervalSince(failedAt) < 3600 { return try await then.complete(request) }
        do {
            var response = try await first.complete(request)
            response.engine = response.engine ?? Engine.gemini.rawValue
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            geminiFailure.date = Date()
            return try await then.complete(request)
        }
    }
}
