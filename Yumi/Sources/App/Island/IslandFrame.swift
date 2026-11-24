import SwiftUI

// MARK: - The frame shared by every screen of the open island (★ Proposition)
//
// In the height of the notch: « ‹ Accueil » on the left, « × » on the right. On the home,
// the left side offers to talk and the right side « Ranger » and « Déposer ». Under the
// content, a halo of the screen's colour glows from the bottom edge.

struct IslandFrameBar: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen
    let height: CGFloat
    @ObservedObject private var voice = IslandVoice.shared

    var body: some View {
        HStack(spacing: 6) {
            if screen == .talk, voice.active {
                VoiceTitle()
            } else if screen == .finished {
                Text("✓ " + loc("Terminé"))
                    .font(IslandTheme.text(12, .semibold))
                    .foregroundStyle(IslandTheme.green)
                    .padding(.leading, 4)
            } else if screen == .alert {
                Text(loc("Demande"))
                    .font(IslandTheme.text(12, .semibold))
                    .foregroundStyle(IslandTheme.amber)
                    .padding(.leading, 4)
            } else if screen == .home {
                EarButton(symbol: "mic.fill", label: loc("Parler ⌥"), color: Color(hex: "#7FD8FF")) { IslandActions.talk() }
            } else {
                Button { withAnimation(.islandSpring(0.5)) { IslandActions.go(.overview) } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold))
                        Text(loc("Accueil")).font(IslandTheme.text(12.5, .semibold))
                    }
                    .frame(height: height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
            Spacer(minLength: 8)
            if screen == .home {
                Button { withAnimation(.islandSpring(0.4)) { model.editingModules.toggle() } } label: {
                    Text(model.editingModules ? loc("OK") : loc("Ranger"))
                        .font(IslandTheme.text(11.5, .semibold))
                        .foregroundStyle(model.editingModules ? Color.black : .white)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(model.editingModules ? Color(hex: "#F5F5F7") : Color.white.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                EarButton(symbol: "doc.fill", label: loc("Déposer"), color: IslandTheme.green) { IslandActions.go(.upload) }
            }
            Button {
                IslandVoice.shared.phase = .idle
                IslandActions.fold()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.1)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loc("Fermer"))
        }
        .frame(height: height)
    }
}

/// A small coloured capsule of the top row.
private struct EarButton: View {
    let symbol: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                Text(label).font(IslandTheme.text(11.5, .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(color.opacity(0.13)))
            .overlay(Capsule().strokeBorder(color.opacity(0.33)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The glow under the content, in the colour of the screen on display.
struct IslandHalo: View {
    let color: Color

    var body: some View {
        // `.glowBg`: left 10 %, right 10 %, bottom -90, height 170, blur 50, opacity .38.
        // The blur is drawn as an elliptical gradient so it looks the same in every capture.
        GeometryReader { geo in
            let w = geo.size.width * 0.8
            EllipticalGradient(stops: [.init(color: color.opacity(0.38), location: 0),
                                       .init(color: color.opacity(0.30), location: 0.32),
                                       .init(color: color.opacity(0.10), location: 0.62),
                                       .init(color: color.opacity(0), location: 1)])
                .frame(width: w + 200, height: 170 + 200)
                .position(x: geo.size.width / 2, y: geo.size.height + 90 - 85)
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.5), value: color)
    }

    /// nil: no halo (the weather fills the island with its own mood instead). `accent` is the
    /// colour chosen for Yumi: the home glows in it.
    @MainActor static func color(screen: IslandScreen, module: ModuleSnapshot?, accent: Color) -> Color? {
        switch screen {
        case .home:             return accent
        case .module, .working:
            if module?.id == IslandModel.agentModuleID { return Color(hex: "#5B8CFF") }
            // `pOpen(…, {glow: c})`: the weather glows in its mood's colour, under its scene
            if let module, module.id == "weather" { return WeatherAmbiance.pick(symbol: module.symbol, status: module.status).color }
            return module?.color ?? IslandTheme.violet
        case .alert:            return IslandTheme.amber
        case .finished, .drop:  return IslandTheme.green
        case .error:            return IslandTheme.red
        case .talk:             return IslandVoice.shared.active ? IslandVoice.cyan : Color(hex: "#8B6CFF")
        default:                return IslandTheme.violet
        }
    }
}
