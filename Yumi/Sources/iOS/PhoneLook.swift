import SwiftUI

/// « Yumi »: himself, large, then what he wears, his colour, what he holds while an agent works,
/// and his voice. The same choices as on the Mac (same keys); the app's Yumi and the widgets follow.
struct PhoneLookView: View {
    let phone: Phone
    @State private var accent = IslandAccent.current()
    @State private var costume = YumiCostume.current()
    @State private var habit = YumiWorkHabit.current()
    @State private var voice = YumiVoice.stored()
    @State private var key = PhoneKeychain.get(PhoneSpeaker.keyName) ?? ""
    @State private var preview = BotEngine()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                YumiStage(engine: preview, followsPointer: false)
                    .frame(width: u(140), height: u(140))
                    .frame(maxWidth: .infinity)
                    .padding(.top, u(6)).padding(.bottom, u(14))
                    .onTapGesture { preview.play([.jump, .wave, .celebrate].randomElement() ?? .jump) }

                title(loc("Skins"))
                PhoneFlow(spacing: u(6)) {
                    ForEach(YumiCostume.allCases, id: \.self) { choice in
                        chip(choice == .none ? loc("Aucun") : choice.label, on: costume == choice) { choose(costume: choice) }
                    }
                }

                title(loc("Couleur"))
                HStack(spacing: u(10)) {
                    ForEach(IslandAccent.allCases, id: \.self) { choice in
                        Button { choose(accent: choice) } label: {
                            Circle()
                                .fill(choice == .yumi ? AnyShapeStyle(PhoneTheme.rim) : AnyShapeStyle(YumiRGB(hex: choice.hex).color))
                                .frame(width: u(24), height: u(24))
                                .padding(3)
                                .overlay(Circle().strokeBorder(.white.opacity(accent == choice ? 1 : 0), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(loc("Couleur \(choice.rawValue)")))
                        .accessibilityAddTraits(accent == choice ? .isSelected : [])
                    }
                }

                title(loc("Quand un agent travaille"))
                PhoneFlow(spacing: u(6)) {
                    ForEach(YumiWorkHabit.settingsChoices, id: \.self) { choice in
                        chip(choice.label, on: habit == choice) { choose(habit: choice) }
                    }
                }

                title(loc("Sa voix"))
                HStack(spacing: u(6)) {
                    ForEach([YumiVoice.mac, .woman, .man], id: \.self) { choice in
                        chip(choice.phoneLabel, on: voice == choice) {
                            voice = choice
                            UserDefaults.standard.set(choice.rawValue, forKey: YumiVoice.defaultsKey)
                            Task { await PhoneSpeaker.shared.say(loc("Coucou, c'est moi !")) }
                        }
                    }
                }
                if voice != .mac {
                    SecureField(loc("Clé ElevenLabs"), text: $key)
                        .font(.system(size: u(13)))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, u(14)).frame(height: u(40))
                        .background(PhoneTheme.ink, in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                        .padding(.top, u(8))
                        .onSubmit { PhoneKeychain.set(PhoneSpeaker.keyName, key.trimmingCharacters(in: .whitespaces).nonEmpty) }
                        .onChange(of: key) { PhoneKeychain.set(PhoneSpeaker.keyName, key.trimmingCharacters(in: .whitespaces).nonEmpty) }
                    Text(loc("Sans clé, il parle avec la voix de l'iPhone. Seule sa réponse est envoyée à ElevenLabs."))
                        .font(.system(size: u(11))).foregroundStyle(PhoneTheme.gray).padding(.top, u(6))
                }
            }
            .padding(.horizontal, u(14))
            .padding(.bottom, u(110))
        }
        .scrollIndicators(.hidden)
        .onAppear {
            preview.setLook(accent: accent, costume: costume)
            preview.setState(.idle, force: true)
            preview.setMood(.happy)
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).phoneEyebrow(PhoneTheme.gray).padding(.top, u(14)).padding(.bottom, u(6))
    }

    private func chip(_ text: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(.system(size: u(12), weight: on ? .semibold : .regular))
                .foregroundStyle(on ? .black : .white)
                .padding(.horizontal, u(11)).frame(height: u(28))
                .background(on ? Color(white: 0.96) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func choose(accent choice: IslandAccent) {
        accent = choice
        choice.save()
        apply()
    }

    private func choose(costume choice: YumiCostume) {
        costume = choice
        choice.save()
        apply()
        preview.play(.pop)
    }

    private func choose(habit choice: YumiWorkHabit) {
        habit = choice
        UserDefaults.standard.set(choice.rawValue, forKey: YumiWorkHabit.defaultsKey)
        preview.setHabit(choice.held)
        SoundEngine.shared.play("pop")
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            preview.setHabit(nil)
        }
    }

    /// The preview, the app's Yumi and the widget's pictures, at once.
    private func apply() {
        preview.setLook(accent: accent, costume: costume)
        phone.character.engine.setLook(accent: accent, costume: costume)
        PhoneWidgets.lookChanged()
        SoundEngine.shared.play("pop")
    }
}
