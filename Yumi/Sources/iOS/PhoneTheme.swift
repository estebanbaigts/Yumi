import SwiftUI

/// Yumi's colours on the iPhone: the night of the notch, and his rim at rest (the blue, violet
/// and pink of the concept sheet, `IslandAccent.yumi.restStops`). The app is always dark, as the
/// island is.
enum PhoneTheme {
    static let blue = YumiRGB(hex: 0x5B8CFF).color
    static let violet = YumiRGB(hex: 0x8B6CFF).color
    static let pink = YumiRGB(hex: 0xF58AD9).color
    static let night = YumiRGB(hex: 0x0E0F26).color
    static let deep = YumiRGB(hex: 0x1B1C4A).color

    /// The new screens: black, cards a little lighter, greys of the system.
    static let ground = Color.black
    static let ink = YumiRGB(hex: 0x0E0E10).color
    static let gray = YumiRGB(hex: 0x8E8E93).color
    static let dim = YumiRGB(hex: 0x6E6E73).color
    static let soft = YumiRGB(hex: 0xB9BCC8).color
    static let listen = YumiRGB(hex: 0x7FD8FF).color
    static let amber = YumiRGB(hex: 0xFFB547).color
    static let coral = YumiRGB(hex: 0xFF8A7A).color
    static let mint = YumiRGB(hex: 0x3DDC97).color
    static let mail = YumiRGB(hex: 0x6FB4FF).color
    static let code = YumiRGB(hex: 0xFFE3B0).color
    static let refuse = YumiRGB(hex: 0xFF453A).color
    static let allow = YumiRGB(hex: 0x30D158).color

    /// His rim, left to right.
    static let rim = LinearGradient(colors: [blue, violet, pink], startPoint: .leading, endPoint: .trailing)

    /// Behind every screen: the night, a little lighter at the top, where he stands.
    static var background: some View {
        ZStack {
            night
            RadialGradient(colors: [violet.opacity(0.28), .clear], center: .init(x: 0.5, y: 0.12),
                           startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A card of the app: dark glass with a hairline of his rim.
    func phoneCard() -> some View {
        background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(PhoneTheme.rim.opacity(0.35), lineWidth: 0.8))
    }

    /// The screens of the app, on black.
    func phoneScreen() -> some View {
        scrollContentBackground(.hidden)
    }

    /// A card of the new screens: #0E0E10, 20 of radius, a hairline of its colour if it has one.
    func phoneTile(_ tint: Color? = nil, padding: CGFloat = u(12)) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PhoneTheme.ink, in: RoundedRectangle(cornerRadius: u(20), style: .continuous))
            .overlay {
                if let tint {
                    RoundedRectangle(cornerRadius: u(20), style: .continuous).strokeBorder(tint.opacity(0.2), lineWidth: 1)
                }
            }
    }

    /// The little capital title of a card (`.eb` of the workshop).
    func phoneEyebrow(_ color: Color) -> some View {
        font(.system(size: u(11), weight: .bold)).textCase(.uppercase).kerning(0.6).foregroundStyle(color)
    }
}

/// The workshop draws the iPhone 300 points wide; a real one is about 393. Every size of the new
/// screens goes through this, so that they keep the workshop's proportions.
nonisolated func u(_ value: CGFloat) -> CGFloat { value * 1.31 }
