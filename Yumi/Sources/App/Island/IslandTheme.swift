import SwiftUI

// Colours, type and motion of design/maquette/reference.html (`:root`).
// The island is one fixed object: same values in the light and dark themes.

enum IslandTheme {
    static let surface  = Color(hex: "#14161F")   // --isl-surface
    static let raise    = Color(hex: "#232738")   // --isl-raise, a step lighter than the surface
    static let line     = Color.white.opacity(0.09)   // --isl-line
    static let fg       = Color(hex: "#F4F5F8")   // --isl-fg
    static let muted    = Color(hex: "#A6ABC0")   // --isl-muted, lighter for reading
    static let faint    = Color(hex: "#7C8199")   // --isl-faint, lighter for reading
    /// Text on a main button
    static let ink      = Color(hex: "#06070C")
    static let code     = Color(hex: "#D6DAEA")
    static let bubbleMe = Color(hex: "#23263A")

    static let blue   = Color(hex: "#5B8CFF")
    static let violet = Color(hex: "#8B6CFF")
    static let pink   = Color(hex: "#F58AD9")
    static let amber  = Color(hex: "#FFB547")
    static let red    = Color(hex: "#FF5D6C")
    static let green  = Color(hex: "#3DDC97")

    /// `--round`: SF Pro Rounded
    static func round(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        .system(size: readable(size), weight: weight, design: .rounded)
    }

    /// Small text reads one point larger than the mock-up asked, and nothing goes under 10.5:
    /// the island is read at a glance, from a distance.
    static func readable(_ size: CGFloat) -> CGFloat {
        size >= 14 ? size : max(10.5, size + 1)
    }

    /// `--text`: SF Pro Text
    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: readable(size), weight: weight)
    }

    /// `--mono`: SF Mono
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: readable(size), weight: weight, design: .monospaced)
    }
}

extension Animation {
    /// `--spring: cubic-bezier(.32, 1.22, .42, 1)`: it overshoots, then settles.
    static func islandSpring(_ duration: Double = 0.55) -> Animation {
        .timingCurve(0.32, 1.22, 0.42, 1, duration: duration)
    }

    /// The CSS keyword `ease`.
    static func islandEase(_ duration: Double) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
    }
}

// MARK: - Nothing moves off screen

private struct IslandLayerShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// false inside a layer of the island that is not the one on screen: its continuous
    /// animations (wave, shimmer, spinner) stop instead of turning for nobody.
    var islandLayerShown: Bool {
        get { self[IslandLayerShownKey.self] }
        set { self[IslandLayerShownKey.self] = newValue }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - `rise`: how a block of content comes in

/// `@keyframes rise { from { opacity: 0; transform: translateY(8px) scale(.98); filter: blur(5px) } }`,
/// played once when the view appears, each child a little after the previous one.
struct RiseIn: ViewModifier {
    let index: Int
    var duration: Double = 0.42
    var stagger: Double = 0.045

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.98)
            .offset(y: shown ? 0 : 8)
            .blur(radius: shown ? 0 : 5)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.islandSpring(duration).delay(Double(index) * stagger)) { shown = true }
                }
            }
    }
}

extension View {
    func riseIn(_ index: Int, duration: Double = 0.42, stagger: Double = 0.045) -> some View {
        modifier(RiseIn(index: index, duration: duration, stagger: stagger))
    }
}
