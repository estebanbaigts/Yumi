import SwiftUI

// MARK: - Yumi himself (★ Proposition, `personnage`)
//
// Yumi large on the left; on the right, his skins (the one chosen is kept everywhere), then
// his habits and poses to try.

struct CharacterPage: View {
    @ObservedObject var model: IslandModel
    @AppStorage(YumiCostume.defaultsKey) private var costume = YumiCostume.none.rawValue
    @State private var tried: YumiHabit?
    private let violet = Color(hex: "#C77DFF")

    private static let habits: [(YumiHabit, String)] = [
        (.coffee, loc("Café")), (.smoke, loc("Clope")), (.headphones, loc("Casque")), (.sunglasses, loc("Lunettes")),
        (.cloud, loc("Nuage")), (.whistle, loc("Sifflote")), (.sleep, loc("Dodo")), (.exhausted, loc("Épuisé")),
    ]
    private static let poses: [(YumiPose, String)] = [
        (.jump, loc("Saut")), (.celebrate, loc("Célébrer")), (.wave, loc("Salut")),
        (.stretch, loc("S'étirer")), (.squash, loc("S'écraser")), (.shake, loc("Secouer")),
    ]

    var body: some View {
        HStack(spacing: 20) {
            YumiSlot(width: 130)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 0) {
                heading(loc("Skins"))
                FlowLayout(spacing: 5) {
                    ForEach(YumiCostume.allCases, id: \.self) { each in
                        chip(each == .none ? loc("Aucun") : each.label, on: each.rawValue == costume) {
                            IslandActions.setCostume(each)
                        }
                    }
                }
                heading(loc("Habitudes et poses")).padding(.top, 14)
                FlowLayout(spacing: 5) {
                    ForEach(Self.habits, id: \.0) { habit, label in
                        chip(label, on: tried == habit) {
                            tried = tried == habit ? nil : habit
                            model.setHabit(tried)
                        }
                    }
                    ForEach(Self.poses, id: \.0) { pose, label in
                        chip(label, on: false) { model.pose(pose) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(height: IslandHome.height)
        .onDisappear { if tried != nil { model.setHabit(nil) } }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(IslandTheme.text(10.5, .bold)).tracking(0.8)
            .foregroundStyle(violet)
            .padding(.bottom, 6)
    }

    private func chip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(IslandTheme.text(11, on ? .semibold : .regular))
                .foregroundStyle(on ? Color.black : .white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(on ? violet : Color.white.opacity(0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
