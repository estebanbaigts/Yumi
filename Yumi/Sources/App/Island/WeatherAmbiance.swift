import SwiftUI

/// The seven moods of the weather page (`WX` in the workshop), picked from the sky, the
/// temperature, the hour and the season.
enum WeatherAmbiance: String, CaseIterable {
    case pluie, soleil, neige, nuit, chaud, froid, doux

    var name: String {
        switch self {
        case .pluie: loc("Pluie")
        case .soleil: loc("Soleil")
        case .neige: loc("Neige")
        case .nuit: loc("Nuit")
        case .chaud: loc("Chaud")
        case .froid: loc("Froid")
        case .doux: loc("Doux")
        }
    }

    var color: Color {
        switch self {
        case .pluie: YumiRGB(hex: 0x7FB4FF).color
        case .soleil: YumiRGB(hex: 0xFFC94D).color
        case .neige: YumiRGB(hex: 0xDDEBFF).color
        case .nuit: YumiRGB(hex: 0x8B9CFF).color
        case .chaud: YumiRGB(hex: 0xFF8A4D).color
        case .froid: YumiRGB(hex: 0x9FD8FF).color
        case .doux: YumiRGB(hex: 0x9CF2C8).color
        }
    }

    /// What Yumi does in it (`WX` of the workshop: scene, face, costume).
    var habit: YumiHabit? {
        switch self {
        case .pluie: .cloud
        case .soleil: .sunglasses
        case .nuit: .sleep
        case .chaud: .exhausted
        case .doux: .whistle
        case .neige, .froid: nil
        }
    }

    /// The face when no habit brings its own.
    var mood: YumiMood? {
        switch self {
        case .neige: .surprised
        case .froid: .worried
        default: nil
        }
    }

    var wearsBeanie: Bool { self == .neige || self == .froid }

    /// `symbol` is the module's SF Symbol, which follows the WMO code; `status` reads "19°".
    /// The filming mode shows each mood in turn.
    @MainActor static var forced: WeatherAmbiance?

    @MainActor static func pick(symbol: String, status: String, now: Date = .now, calendar: Calendar = .current) -> WeatherAmbiance {
        if let forced { return forced }
        let temperature = Int(status.filter { $0.isNumber || $0 == "-" || $0 == "−" }.replacingOccurrences(of: "−", with: "-"))
        let hour = calendar.component(.hour, from: now)
        let month = calendar.component(.month, from: now)
        let winter = [12, 1, 2].contains(month), summer = [6, 7, 8].contains(month)
        if symbol.contains("snow") { return .neige }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("bolt") { return .pluie }
        if let t = temperature, t >= (summer ? 30 : 28) { return .chaud }
        if let t = temperature, t <= (winter ? 3 : 1) { return .froid }
        if hour < 7 || hour >= 21 { return .nuit }
        if symbol.hasPrefix("sun") { return .soleil }
        return .doux
    }
}

/// The animated ground of the weather page, drawn in a Canvas.
struct WeatherEffects: View {
    let ambiance: WeatherAmbiance

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                switch ambiance {
                case .pluie: rain(g, size, t)
                case .soleil: sun(g, size, t, color: YumiRGB(hex: 0xFFC94D).color, speed: 18, glow: true)
                case .chaud:
                    g.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .linearGradient(Gradient(colors: [YumiRGB(hex: 0xFF6A2A).color.opacity(0.18 + 0.1 * sin(t * 2.5)), .clear]),
                                                 startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: size.height * 0.3)))
                    sun(g, size, t, color: YumiRGB(hex: 0xFF8A4D).color, speed: 6, glow: false)
                    waves(g, size, t)
                case .neige: snow(g, size, t)
                case .nuit: night(g, size, t)
                case .froid: frost(g, size, t)
                case .doux: mild(g, size, t)
                }
            }
        }
    }

    private func rain(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [YumiRGB(hex: 0x1B2333).color, .black]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.75)))
        for i in 0..<45 {
            let x = size.width * Double((i * 37) % 100) / 100
            let duration = 0.55 + Double(i % 5) * 0.08
            let phase = ((t + Double(i) * 0.13) / duration).truncatingRemainder(dividingBy: 1)
            let length = 14 + Double(i % 4) * 5
            let y = -30 + phase * (size.height + 60)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - length * 0.18, y: y + length))
            g.stroke(path, with: .color(YumiRGB(hex: 0x9CC4FF).color.opacity([0.35, 0.55, 0.75][i % 3])), lineWidth: 1.6)
        }
        for i in 0..<12 {
            let phase = ((t + Double(i) * 0.21) / 1.2).truncatingRemainder(dividingBy: 1)
            let x = size.width * Double((i * 53 + 7) % 100) / 100
            let w = 10 * (0.4 + phase)
            let rect = CGRect(x: x - w / 2, y: size.height - 8, width: w, height: 4)
            g.stroke(Path(ellipseIn: rect), with: .color(YumiRGB(hex: 0x9CC4FF).color.opacity(1 - phase)), lineWidth: 1.2)
        }
    }

    private func sun(_ g: GraphicsContext, _ size: CGSize, _ t: Double, color: Color, speed: Double, glow: Bool) {
        let center = CGPoint(x: size.width - 100, y: 90)
        if glow {
            let r = 130 * (1 + 0.05 * sin(t * .pi / 2))
            g.fill(Path(ellipseIn: CGRect(x: size.width + 60 - 2 * r, y: -60, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.53), color.opacity(0.13), .clear]),
                                         center: CGPoint(x: size.width + 60 - r, y: -60 + r), startRadius: 0, endRadius: r))
        }
        var rays = g
        rays.translateBy(x: center.x, y: center.y)
        rays.rotate(by: .degrees(t / speed * 360))
        for k in 0..<12 {
            var ray = rays
            ray.rotate(by: .degrees(Double(k) * 30))
            ray.fill(Path(roundedRect: CGRect(x: -3, y: -52, width: 6, height: 16), cornerRadius: 3), with: .color(color))
        }
        g.fill(Path(ellipseIn: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52)), with: .color(color == YumiRGB(hex: 0xFFC94D).color ? YumiRGB(hex: 0xFFD24A).color : YumiRGB(hex: 0xFF7A3D).color))
    }

    private func waves(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<6 {
            let phase = ((t + Double(i) * 0.4) / 2.4).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.08 + Double(i) * 0.15)
            let y = size.height + 10 - phase * size.height * 0.8
            var path = Path()
            path.move(to: CGPoint(x: x, y: y + 70))
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 12, y: y + 35))
            g.stroke(path, with: .color(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.45 * (1 - phase))), lineWidth: 2)
        }
    }

    private func snow(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        let flakes: [(CGFloat, CGFloat, CGFloat)] = [(20, 30, 2.2), (80, 90, 1.6), (150, 50, 2), (120, 150, 1.4), (190, 120, 2.4)]
        let drift = (t / 6).truncatingRemainder(dividingBy: 1) * 200
        var x0: CGFloat = 0
        while x0 < size.width {
            var y0: CGFloat = -200
            while y0 < size.height {
                for f in flakes {
                    let y = y0 + f.1 + drift
                    g.fill(Path(ellipseIn: CGRect(x: x0 + f.0 + sin((t + Double(f.1)) * 0.8) * 4, y: y, width: f.2 * 2, height: f.2 * 2)), with: .color(.white.opacity(0.85)))
                }
                y0 += 200
            }
            x0 += 220
        }
    }

    private func night(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [YumiRGB(hex: 0x0B1030).color, .black]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.8)))
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(40, 60, 1.4), (140, 40, 1), (260, 90, 1.6), (380, 50, 1), (520, 110, 1.3), (600, 70, 1)]
        for (i, s) in stars.enumerated() {
            let a = 0.55 + 0.45 * sin(t * 2 + Double(i))
            g.fill(Path(ellipseIn: CGRect(x: s.0, y: s.1, width: s.2 * 2, height: s.2 * 2)), with: .color(.white.opacity(a)))
        }
        // The crescent: a disc with another cut out of it
        let moon = CGRect(x: size.width - 160, y: 50, width: 40, height: 40)
        var crescent = Path(ellipseIn: moon.offsetBy(dx: -8, dy: 6))
        crescent = crescent.subtracting(Path(ellipseIn: moon))
        g.fill(crescent, with: .color(YumiRGB(hex: 0xE8ECFF).color.opacity(0.9)))
    }

    private func frost(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [YumiRGB(hex: 0x9FD8FF).color.opacity(0.27), .clear]),
                                     center: CGPoint(x: size.width / 2, y: size.height * 1.2), startRadius: 0, endRadius: size.width * 0.6))
        for i in 0..<14 {
            let phase = ((t + Double(i) * 0.37) / 2.4).truncatingRemainder(dividingBy: 1)
            let a = sin(phase * .pi)
            let p = CGPoint(x: size.width * Double((i * 41 + 5) % 100) / 100, y: size.height * Double((i * 23 + 8) % 100) / 100)
            g.draw(Text("✦").font(.system(size: 11)).foregroundStyle(YumiRGB(hex: 0xCFEFFF).color.opacity(a)), at: p)
        }
        for i in 0..<5 {
            let duration = 2.2 + Double(i % 3) * 0.5
            let phase = ((t + Double(i) * 0.7) / duration).truncatingRemainder(dividingBy: 1)
            let x = -170 + phase * (size.width + 340)
            let y = size.height * (0.18 + Double(i) * 0.15)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y + 12))
            path.addCurve(to: CGPoint(x: x + 100, y: y + 10), control1: CGPoint(x: x + 30, y: y + 4), control2: CGPoint(x: x + 60, y: y + 20))
            path.addQuadCurve(to: CGPoint(x: x + 150, y: y + 8), control: CGPoint(x: x + 140, y: y + 4))
            g.stroke(path, with: .color(Color(red: 0.81, green: 0.94, blue: 1).opacity(0.55)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    private func mild(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [YumiRGB(hex: 0x9CF2C8).color.opacity(0.2), .clear]),
                                     center: CGPoint(x: size.width * 0.8, y: 0), startRadius: 0, endRadius: size.width * 0.5))
        let leaves: [(String, String)] = [("❀", "#9CF2C8"), ("✿", "#FFD6A5"), ("❀", "#C8F29C"), ("✦", "#FFB3D1")]
        for i in 0..<9 {
            let duration = [6.0, 7.5, 9.0][i % 3]
            let phase = ((t + Double(i) * 0.9) / duration).truncatingRemainder(dividingBy: 1)
            let leaf = leaves[i % 4]
            let x = -20 + phase * (size.width + 40)
            let y = size.height * Double((i * 29 + 10) % 75) / 100 + sin(phase * .pi * 4) * 14
            var c = g
            c.translateBy(x: x, y: y)
            c.rotate(by: .degrees(phase * 360))
            c.draw(Text(leaf.0).font(.system(size: 14)).foregroundStyle(Self.color(leaf.1).opacity(0.8)), at: .zero)
        }
    }
}

extension WeatherEffects {
    /// "#RRGGBB" without the island's helper, so that the iPhone can draw it too.
    fileprivate static func color(_ hex: String) -> Color {
        YumiRGB(hex: UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0).color
    }
}
