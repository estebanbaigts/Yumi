import AppKit
import SwiftUI

// MARK: - Asking aloud, in the island (★ Proposition, `voix` and `reponse`)
//
// While the right Option key is held, the island listens: Yumi, a wave, the words heard. Let
// go, he looks and answers in the island with « Montre-moi », « Répéter » and « Continuer
// dans le chat ». ShowMeController drives it.

@MainActor
final class IslandVoice: ObservableObject {
    static let shared = IslandVoice()

    enum Phase: Equatable {
        case idle
        case listening(String)
        case looking(question: String, note: String)
        case answer(question: String, text: String, note: String?)
    }

    @Published var phase: Phase = .idle
    var active: Bool { phase != .idle }

    /// What the buttons of the answer do, given by ShowMeController.
    var repeatAnswer: (() -> Void)?
    var pointAgain: (() -> Void)?
    var canPoint = false
    var stopSpeaking: (() -> Void)?
    /// The links the answer gave, shown to click instead of read aloud.
    @Published var links: [URL] = []
    /// He is saying the answer aloud: « Arrêter » shows.
    @Published var speaking = false

    static let cyan = Color(hex: "#7FD8FF")

    /// The answer goes on in the chat: the question and the answer join the conversation.
    func continueInChat(state: AppState) {
        if case .answer(let question, let text, _) = phase {
            state.chatHistory.append(ChatMessage(role: .user, content: question))
            state.chatHistory.append(ChatMessage(role: .assistant, content: text))
        }
        phase = .idle
    }
}

/// The left side of the frame while Yumi listens or answers.
struct VoiceTitle: View {
    @ObservedObject var voice = IslandVoice.shared

    var body: some View {
        Text({
            if case .listening = voice.phase { return "● " + loc("Écoute") }
            return loc("Réponse à ta question")
        }())
        .font(IslandTheme.text(12, .semibold))
        .foregroundStyle(IslandVoice.cyan)
        .padding(.leading, 4)
    }
}

struct VoicePage: View {
    @ObservedObject var state: AppState
    @ObservedObject var voice = IslandVoice.shared

    var body: some View {
        Group {
            switch voice.phase {
            case .idle:
                EmptyView()
            case .listening(let words):
                listening(words, hint: loc("Yumi t'écoute tant que tu maintiens ⌥ droite"))
            case .looking(let question, let note):
                listening(question, hint: note, still: true)
            case .answer(let question, let text, let note):
                answer(question: question, text: text, note: note)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: IslandHome.height, alignment: .top)
        .padding(.horizontal, 14)
    }

    private func listening(_ words: String, hint: String, still: Bool = false) -> some View {
        VStack(spacing: 0) {
            YumiSlot(width: 80)
            VoiceWave(running: !still).frame(height: 30).padding(.top, 6)
            Text(words.isEmpty ? "…" : "« \(words) »")
                .font(IslandTheme.text(16))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 8)
            Text(hint)
                .font(IslandTheme.text(11.5))
                .foregroundStyle(Color(hex: "#8E8E93"))
                .padding(.top, 8)
        }
    }

    private func answer(question: String, text: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc("Tu as demandé :")).font(IslandTheme.text(12)).foregroundStyle(Color(hex: "#8E8E93"))
            Text("« \(question) »").font(IslandTheme.text(14)).lineLimit(1).padding(.bottom, 12)
            HStack(alignment: .top, spacing: 14) {
                YumiSlot(width: 60)
                VStack(alignment: .leading, spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        Text(text)
                            .font(IslandTheme.text(14))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                                .fill(IslandVoice.cyan.opacity(0.12)))
                            .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
                                .strokeBorder(IslandVoice.cyan.opacity(0.27)))
                    }
                    .frame(maxHeight: voice.links.isEmpty ? 92 : 70)
                    if !voice.links.isEmpty {
                        // Where he found it: to look at, not to hear
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(voice.links, id: \.self) { url in
                                    Button { NSWorkspace.shared.open(url) } label: {
                                        Label(url.host() ?? url.absoluteString, systemImage: "link")
                                            .font(IslandTheme.text(11, .medium))
                                            .foregroundStyle(IslandVoice.cyan)
                                            .padding(.horizontal, 9)
                                            .frame(height: 22)
                                            .background(Capsule().fill(IslandVoice.cyan.opacity(0.1)))
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        VoiceWave(running: true, bars: 5).frame(width: 22, height: 12)
                        Text(note ?? loc("Yumi le dit à voix haute"))
                    }
                    .font(IslandTheme.text(11.5))
                    .foregroundStyle(IslandVoice.cyan)
                }
            }
            HStack(spacing: 8) {
                if voice.canPoint {
                    pill(loc("Montre-moi"), filled: true) { voice.pointAgain?() }
                }
                if voice.speaking {
                    pill(loc("Arrêter"), filled: false) { voice.stopSpeaking?() }
                } else {
                    pill(loc("Répéter"), filled: false) { voice.repeatAnswer?() }
                }
                pill(loc("Continuer dans le chat"), filled: false) {
                    withAnimation(.islandSpring(0.4)) { voice.continueInChat(state: state) }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
        .frame(maxWidth: 500)
    }

    private func pill(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(IslandTheme.text(12.5, filled ? .semibold : .regular))
                .foregroundStyle(filled ? Color.black : .white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(filled ? IslandVoice.cyan : .clear))
                .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.3), lineWidth: 1.4))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Bars that rise and fall while Yumi hears.
struct VoiceWave: View {
    var running: Bool
    var bars = 22

    var body: some View {
        TimelineView(.animation(paused: !running)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<bars, id: \.self) { i in
                    let base = 0.2 + abs(sin(Double(i) * 1.7)) * 0.8
                    let wave = running ? 0.55 + 0.45 * sin(t * 2 * .pi / 0.9 + Double(i % 6) * 0.9) : 0.35
                    GeometryReader { geo in
                        Capsule().fill(IslandVoice.cyan)
                            .frame(height: max(3, geo.size.height * base * wave))
                            .frame(maxHeight: .infinity)
                    }
                    .frame(width: 3)
                }
            }
        }
    }
}
