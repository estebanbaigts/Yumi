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

    /// The screens of the app, on his night.
    func phoneScreen() -> some View {
        scrollContentBackground(.hidden)
            .background { PhoneTheme.background }
            .toolbarBackground(PhoneTheme.night.opacity(0.85), for: .navigationBar, .tabBar)
    }
}
