import AVFoundation
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// « Parler »: the last questions in grey, Yumi's answers large, and at the bottom the field, the
/// « + » and Yumi, whom one touches to talk. While he listens, the waves and what he hears.
struct PhoneChatView: View {
    @Bindable var phone: Phone
    @State private var draft = ""
    @State private var adding: PhoneAddKind?
    @State private var choosingFile = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
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
        // Only what the person picks reaches him, one file at a time
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.pdf, .image, .plainText, .text, .rtf, .commaSeparatedText, .json]) { result in
            guard case .success(let url) = result else { return }
            Task { if let file = await Self.read(url) { give(file) } }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) {
            guard let item = photo else { return }
            photo = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = Self.picture(data) {
                    give(PhoneAttachment(name: loc("Photo"), image: image))
                }
            }
        }
    }

    private func give(_ file: PhoneAttachment) {
        let text = draft
        draft = ""
        Task { await phone.chat.send(text, attachment: file) }
    }

    /// A file the person chose: read once, nothing kept.
    static func read(_ url: URL) async -> PhoneAttachment? {
        let open = url.startAccessingSecurityScopedResource()
        defer { if open { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true, let pdf = PDFDocument(url: url) {
            let text = pdf.string ?? ""
            // A scanned PDF has no text: its first page goes as a picture
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20, let page = pdf.page(at: 0) {
                let thumb = page.thumbnail(of: CGSize(width: 1400, height: 1800), for: .mediaBox)
                return PhoneAttachment(name: name, image: thumb.jpegData(compressionQuality: 0.8).map { LLMImage(data: $0) })
            }
            return PhoneAttachment(name: name, text: text)
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if type?.conforms(to: .image) == true { return picture(data).map { PhoneAttachment(name: name, image: $0) } }
        return String(data: data, encoding: .utf8).map { PhoneAttachment(name: name, text: $0) }
    }

    /// A picture made small enough for a model (1600 px at most), as JPEG.
    static func picture(_ data: Data) -> LLMImage? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return small.jpegData(compressionQuality: 0.8).map { LLMImage(data: $0) }
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
                            if message.role == .person, let file = message.attachment {
                                VStack(spacing: u(4)) {
                                    Label(file, systemImage: "doc.fill").font(.system(size: u(13), weight: .semibold))
                                        .padding(.horizontal, u(12)).frame(height: u(30))
                                        .background(PhoneTheme.ink, in: Capsule())
                                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                                    if message.text != file {
                                        Text("« \(message.text) »").font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                                    }
                                }
                                .padding(.top, u(12))
                            } else if message.role == .person {
                                Text("« \(message.text) »").font(.system(size: u(13))).foregroundStyle(PhoneTheme.gray)
                                    .padding(.top, u(12))
                            } else {
                                VStack(spacing: u(4)) {
                                    Text(message.text)
                                        .font(.system(size: u(21), weight: .medium))
                                        .lineSpacing(u(4))
                                        .padding(.horizontal, u(4))
                                    if let by = message.by {
                                        Text(by).font(.system(size: u(10.5), weight: .semibold)).foregroundStyle(PhoneTheme.dim)
                                    }
                                }
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
                    Button(loc("Un fichier"), systemImage: "doc") { choosingFile = true }
                    Button(loc("Une photo"), systemImage: "photo") { choosingPhoto = true }
                    Divider()
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
        let voice = PhoneVoiceChoice.current
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
        utterance.voice = Self.bestVoice(man: voice == .man)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.02
        synthesizer.speak(utterance)
    }

    /// Without ElevenLabs: the most natural voice installed (premium, then enhanced), of the
    /// chosen kind when the system tells it.
    private static func bestVoice(man: Bool) -> AVSpeechSynthesisVoice? {
        let language = AppLanguage.isEnglish ? "en" : "fr"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
        let wanted: AVSpeechSynthesisVoiceGender = man ? .male : .female
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            (v.quality == .premium ? 20 : v.quality == .enhanced ? 10 : 0) + (v.gender == wanted ? 5 : 0)
                + (v.language == (AppLanguage.isEnglish ? "en-US" : "fr-FR") ? 1 : 0)
        }
        return voices.max { rank($0) < rank($1) } ?? AVSpeechSynthesisVoice(language: AppLanguage.isEnglish ? "en-US" : "fr-FR")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
    }
}
