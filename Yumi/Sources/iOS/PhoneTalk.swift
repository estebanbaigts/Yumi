import AVFoundation
import SwiftUI

/// « Parler »: the last questions in grey, Yumi's answers large, and at the bottom the field, the
/// « + » and Yumi, whom one touches to talk. While he listens, the waves and what he hears.
struct PhoneChatView: View {
    @Bindable var phone: Phone
    @State private var draft = ""
    @State private var adding: PhoneAddKind?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            if phone.listener.listening {
                listening.frame(maxHeight: .infinity, alignment: .top)
            } else {
                conversation
            }
            composer
        }
        .sheet(item: $adding) { kind in PhoneAddSheet(kind: kind, today: phone.today) { phone.updateRemarks() } }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: u(14)) {
                    if phone.chat.messages.isEmpty {
                        Text(loc("Dis-moi ce dont tu as besoin.")).font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                            .padding(.top, u(26))
                    }
                    ForEach(phone.chat.messages) { message in
                        Group {
                            if message.role == .person {
                                Text("« \(message.text) »").font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                                    .padding(.top, u(12))
                            } else {
                                Text(message.text)
                                    .font(.system(size: u(21), weight: .medium))
                                    .lineSpacing(u(4))
                                    .padding(.horizontal, u(4))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .id(message.id)
                    }
                    if phone.chat.isThinking { ProgressView().padding(.top, u(8)) }
                }
                .padding(.horizontal, u(14))
                .padding(.bottom, u(16))
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: phone.chat.messages.count) {
                if let last = phone.chat.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var listening: some View {
        VStack(spacing: 0) {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<20, id: \.self) { i in
                        let base = 0.2 + abs(sin(Double(i) * 1.7)) * 0.8
                        let wave = 0.55 + 0.45 * sin(t * 7 + Double(i % 6) * 0.9)
                        Capsule().fill(PhoneTheme.listen)
                            .frame(width: 3, height: u(40) * min(1, base * (0.35 + wave * (0.4 + phone.listener.level))))
                    }
                }
                .frame(height: u(40))
            }
            Text("« \(phone.listener.heard.isEmpty ? "…" : phone.listener.heard) »")
                .font(.system(size: u(21), weight: .medium)).multilineTextAlignment(.center)
                .padding(.top, u(20)).padding(.horizontal, u(14))
            Text(loc("Yumi t'écoute. Touche-le encore pour envoyer."))
                .font(.system(size: u(12))).foregroundStyle(PhoneTheme.gray).padding(.top, u(14))
        }
        .padding(.top, u(40))
    }

    private var composer: some View {
        VStack(spacing: u(8)) {
            Text(phone.listener.access == .denied ? loc("Le micro est refusé. Tu peux le rendre dans Réglages.")
                 : loc("Écris dans le champ, ou touche Yumi pour lui parler"))
                .font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray)
            HStack(spacing: u(8)) {
                Menu {
                    Button(loc("Un rappel"), systemImage: "checklist") { adding = .reminder }
                    Button(loc("Un événement"), systemImage: "calendar") { adding = .event }
                } label: {
                    Image(systemName: "plus").font(.system(size: u(17), weight: .semibold)).foregroundStyle(.white)
                        .frame(width: u(40), height: u(40))
                        .background(PhoneTheme.ink, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                }
                .accessibilityLabel(Text(loc("Ajouter")))
                TextField(loc("Écris à Yumi…"), text: $draft, axis: .vertical)
                    .font(.system(size: u(15)))
                    .lineLimit(1...4)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, u(14)).padding(.vertical, u(11))
                    .frame(minHeight: u(44))
                    .background(PhoneTheme.ink, in: RoundedRectangle(cornerRadius: u(22), style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: u(22), style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                Button {
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { send() } else { typing = false; phone.talk() }
                } label: {
                    PhoneFace(character: phone.character, size: u(38), ring: u(56), listening: phone.listener.listening)
                        .shadow(color: PhoneTheme.violet.opacity(phone.listener.listening ? 0 : 0.33), radius: u(9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(draft.isEmpty ? loc("Touche Yumi pour parler") : loc("Envoyer")))
            }
        }
        .padding(.horizontal, u(12)).padding(.top, u(10)).padding(.bottom, u(8))
        .background(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.3)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !phone.chat.isThinking else { return }
        draft = ""
        Task { await phone.chat.send(text) }
    }
}

// MARK: - His voice

/// Yumi answers aloud when he was asked aloud: never the links (`SpokenAnswer`). The voice of the
/// iPhone, or the ElevenLabs voice chosen on his page when a key was given (only his answer is sent).
@MainActor
final class PhoneSpeaker {
    static let shared = PhoneSpeaker()
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    static let keyName = YumiVoice.keychainKey

    func say(_ answer: String) async {
        let text = SpokenAnswer.split(answer).text
        guard !text.isEmpty else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let voice = YumiVoice.stored()
        if let id = voice.voiceID(), let key = PhoneKeychain.get(Self.keyName),
           let request = try? YumiVoice.speechRequest(text: text, voiceID: id, key: key),
           let (data, response) = try? await URLSession.shared.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let player = try? AVAudioPlayer(data: data) {
            self.player = player
            player.play()
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AppLanguage.isEnglish ? "en-US" : "fr-FR")
        utterance.pitchMultiplier = voice == .man ? 0.9 : 1.1
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
    }
}
