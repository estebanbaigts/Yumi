import SwiftUI

/// Réglages › Son apparence: his colour and what he wears, the same choices as on the Mac
/// (IslandAccent, YumiCostume, same keys). A large Yumi shows each choice at once; the app's
/// Yumi and the widget's pictures follow.
struct PhoneLookView: View {
    let phone: Phone
    @State private var accent = IslandAccent.current()
    @State private var costume = YumiCostume.current()
    @State private var preview = BotEngine()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                YumiStage(engine: preview, followsPointer: false)
                    .frame(width: 190, height: 190)
                    .padding(.top, 12)
                    .onTapGesture { preview.play([.jump, .wave, .celebrate].randomElement() ?? .jump) }

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("Couleur")).font(.headline)
                    HStack(spacing: 12) {
                        ForEach(IslandAccent.allCases, id: \.self) { choice in
                            Button { choose(accent: choice) } label: {
                                Circle()
                                    .fill(choice == .yumi ? AnyShapeStyle(PhoneTheme.rim) : AnyShapeStyle(YumiRGB(hex: choice.hex).color))
                                    .frame(width: 34, height: 34)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(.white.opacity(accent == choice ? 1 : 0), lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(loc("Couleur \(choice.rawValue)")))
                            .accessibilityAddTraits(accent == choice ? .isSelected : [])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .phoneCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text(loc("Ce qu'il porte")).font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(YumiCostume.allCases, id: \.self) { choice in
                            Button { choose(costume: choice) } label: {
                                Text(choice.label)
                                    .font(.subheadline.weight(costume == choice ? .semibold : .regular))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(costume == choice ? AnyShapeStyle(PhoneTheme.rim.opacity(0.35)) : AnyShapeStyle(.white.opacity(0.06)),
                                                in: Capsule())
                                    .overlay(Capsule().strokeBorder(PhoneTheme.rim.opacity(costume == choice ? 0.9 : 0.25), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(costume == choice ? .isSelected : [])
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .phoneCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .phoneScreen()
        .navigationTitle(loc("Son apparence"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            preview.setLook(accent: accent, costume: costume)
            preview.setState(.idle, force: true)
        }
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

    /// The preview, the app's Yumi and the widget's pictures, at once.
    private func apply() {
        preview.setLook(accent: accent, costume: costume)
        phone.character.engine.setLook(accent: accent, costume: costume)
        PhoneWidgets.lookChanged()
        SoundEngine.shared.play("pop")
    }
}
