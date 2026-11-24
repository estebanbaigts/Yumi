import SwiftUI

// What surrounds Yumi while he arrives and while he leaves: at launch, shooting stars and
// « Bonjour » with the person's name (`l1`, « Le réveil »); at the goodbye, a halo and a few
// words (`q1`). Yumi himself is the island's one character, drawn above.

struct IslandGreetingLayer: View {
    let phase: IslandModel.GreetingPhase
    /// Where the halo is centred, in the layer's own units.
    let center: CGPoint
    /// Size of the layer, in its own units.
    let size: CGSize
    /// A few words under Yumi: only the goodbye has some.
    var words: String?
    /// « Bonjour Esteban » at the bottom of the launch (`l1`, « Le réveil »), with shooting
    /// stars in place of the glow.
    var hello: String?

    private var glowOn: Bool { phase.lit && !phase.bye }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear

            // `.g-glow`: 320 × 240, blooms when the light comes on
            EllipticalGradient(
                stops: [
                    .init(color: Color(red: 139 / 255, green: 108 / 255, blue: 255 / 255).opacity(0.46), location: 0),
                    .init(color: Color(red: 91 / 255, green: 140 / 255, blue: 255 / 255).opacity(0.18), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5
            )
            .frame(width: 320, height: 240)
            .scaleEffect(phase.lit ? 1 : 0.4)
            .animation(.islandSpring(1), value: phase.lit)
            .opacity(glowOn && hello == nil ? 1 : 0)
            .animation(.islandEase(phase.bye ? 0.22 : 0.8), value: glowOn)
            .position(center)

            // `STARS(10)`: shooting stars crossing the island while the light is on
            if hello != nil {
                ShootingStars(size: size)
                    .opacity(glowOn ? 1 : 0)
                    .animation(.islandEase(0.6), value: glowOn)
            }

            // `.sq-hi`: bottom 14, 16 pt bold rounded
            if let hello {
                Text(hello)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size.width)
                    .position(x: size.width / 2, y: size.height - 14 - 10)
                    .opacity(glowOn ? 1 : 0)
                    .offset(y: glowOn ? 0 : 6)
                    .animation(.islandEase(0.5), value: glowOn)
            }

            // `.g-bye`
            if let words {
                Text(words)
                    .font(IslandTheme.text(13, .semibold))
                    .foregroundStyle(IslandTheme.muted)
                    .frame(width: size.width)
                    .offset(y: 104)
                    .opacity(phase.say ? 1 : 0)
                    .animation(.islandEase(0.4), value: phase.say)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// `.sq-stars i`: a 46-point streak with a bright head, at 28°, flying 150 points in 1.4 to 2.5 s.
private struct ShootingStars: View {
    let size: CGSize

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { g, box in
                let t = timeline.date.timeIntervalSinceReferenceDate
                for i in 0..<10 {
                    let duration = 1.4 + Double(i % 4) * 0.35
                    let delay = Double(i * 47 % 260) / 100
                    let p = ((t + delay) / duration).truncatingRemainder(dividingBy: 1)
                    let opacity = p < 0.15 ? p / 0.15 : p < 0.7 ? 1 - (p - 0.15) / 0.55 * 0.1 : 0.9 * (1 - (p - 0.7) / 0.3)
                    let origin = CGPoint(x: box.width * Double((i * 53 + 20) % 100) / 100,
                                         y: box.height * Double((i * 37 + 8) % 85) / 100)
                    let shift = -30 + 150 * p
                    var c = g
                    c.translateBy(x: origin.x, y: origin.y)
                    c.rotate(by: .degrees(28))
                    c.opacity = opacity
                    let streak = CGRect(x: shift, y: 0, width: 46, height: 1.5)
                    c.fill(Path(roundedRect: streak, cornerRadius: 1),
                           with: .linearGradient(Gradient(colors: [.clear, .white, Color(hex: "#C9B8FF")]),
                                                 startPoint: CGPoint(x: streak.minX, y: 0), endPoint: CGPoint(x: streak.maxX, y: 0)))
                    c.fill(Path(ellipseIn: CGRect(x: streak.maxX - 3, y: -1.5, width: 4, height: 4)), with: .color(.white))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Rings and sparks (`#fx`)

/// Three rings and twelve dots burst from Yumi when the light comes on. Drawn inside the
/// island, so the island's edge cuts them, as `overflow: hidden` does in the mock-up.
struct IslandSparks: View {
    let start: Date?
    var scale: CGFloat = 1
    /// Centre of the burst, in island coordinates: Yumi's seat in the greeting.
    let center: CGPoint

    private static let colors = [IslandTheme.blue, IslandTheme.violet, IslandTheme.pink]
    /// `cubic-bezier(.2, .7, .3, 1)`
    private static let curve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.2, y: 0.7),
                                                endControlPoint: UnitPoint(x: 0.3, y: 1))
    /// Last ring: 0.26 s delay + 1 s
    private static let length = 1.3

    var body: some View {
        // Running only for the 1.3 s of the burst: `start` goes back to nil afterwards
        TimelineView(.animation(paused: start == nil)) { timeline in
            Canvas { context, _ in
                guard let start else { return }
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t <= Self.length else { return }

                // `@keyframes ring { 0% { opacity: .9; transform: scale(.5) } 100% { opacity: 0; transform: scale(3.4) } }`, 1 s
                for i in 0..<3 {
                    let local = t - Double(i) * 0.13
                    guard local >= 0, local <= 1 else { continue }
                    let p = Self.curve.value(at: local)
                    let scale = (0.5 + (3.4 - 0.5) * p) * self.scale
                    let radius = 32 * scale
                    let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                    context.stroke(Path(ellipseIn: rect.insetBy(dx: scale, dy: scale)),
                                   with: .color(Self.colors[i].opacity(0.9 * (1 - p))),
                                   lineWidth: 2 * scale)
                }

                // `@keyframes fly`: from 34 to 150 away, shrinking to .3, fading, .85 s
                for i in 0..<12 {
                    let local = (t - Double(i % 4) * 0.03) / 0.85
                    guard local >= 0, local <= 1 else { continue }
                    let p = Self.curve.value(at: local)
                    let angle = Double(i * 30 + 8) * .pi / 180
                    let distance = (34 + (150 - 34) * p) * scale
                    let radius = 3 * (1 - 0.7 * p) * scale
                    let x = center.x + cos(angle) * distance
                    let y = center.y + sin(angle) * distance
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Self.colors[i % 3].opacity(1 - p)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
