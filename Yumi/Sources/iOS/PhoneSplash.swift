import SwiftUI

/// The opening (« Le réveil + la chute », p6 of the workshop): on black, the Dynamic Island
/// swells into a drop, two sleeping eyes open inside it, look left and right; it opens, the
/// light comes on and he says hello by name. Then the island closes again and he falls straight
/// into the circle at the bottom, at its centre and its size, while the app appears. About 5 s;
/// a tap skips to the fall.
///
/// iOS draws nothing of an app before it opens: the opening starts once the app is in front.
struct PhoneSplash: View {
    let character: PhoneCharacter
    /// His first name, read when he says hello (the memory may load during the opening).
    var name: () -> String?
    /// The black goes: the home screen shows its cards under him.
    var reveal: () -> Void
    /// He touches the circle: it shows around him.
    var landed: () -> Void = {}
    /// He landed in the circle: the cover is removed, the circle draws him from now on.
    var done: () -> Void

    private enum Stage: Int { case hidden, drip, hello, falling, landed }

    @State private var stage = Stage.hidden
    @State private var hello: String?
    @State private var black = true
    @State private var falling = false
    @State private var skipped = false
    /// The shooting stars inside the island while he says hello (`STARS` of the workshop).
    @State private var stars = false

    private var engine: BotEngine { character.engine }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
            let bottom = geo.safeAreaInsets.bottom
            ZStack(alignment: .topLeading) {
                Color.black.opacity(black ? 1 : 0)
                island
                    .position(x: width / 2, y: 11 + islandSize.height / 2)
                if let hello, stage == .hello {
                    Text(hello)
                        .font(.system(size: u(24), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .frame(width: width - 40)
                        .position(x: width / 2, y: 11 + islandSize.height + u(20))
                        .transition(.opacity.combined(with: .offset(y: u(10))))
                }
                if stage != .hidden {
                    let place = yumiPlace(height: height, bottom: bottom)
                    YumiStage(engine: engine, followsPointer: false)
                        .frame(width: place.size, height: place.size)
                        .position(x: width / 2, y: place.y)
                }
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(black)
        .contentShape(Rectangle())
        .onTapGesture { skipped = true }
        .accessibilityLabel(Text(hello ?? AppIdentity.characterName))
        .task { await play() }
    }

    /// The workshop's 92×27 is the real Dynamic Island (126×37); its other sizes go through `u`.
    @State private var closed = false

    private var islandSize: CGSize {
        if closed { return CGSize(width: 126, height: 37) }
        return switch stage {
        case .drip: CGSize(width: u(140), height: u(120))
        case .hello: CGSize(width: u(230), height: u(210))
        default: CGSize(width: 126, height: 37)
        }
    }

    private var island: some View {
        let open: AnyShape = switch stage {
        case .drip: AnyShape(UnevenRoundedRectangle(topLeadingRadius: u(20), bottomLeadingRadius: u(70),
                                                    bottomTrailingRadius: u(70), topTrailingRadius: u(20), style: .continuous))
        case .hello: AnyShape(RoundedRectangle(cornerRadius: u(44), style: .continuous))
        default: AnyShape(RoundedRectangle(cornerRadius: 18.5, style: .continuous))
        }
        let shape = closed ? AnyShape(RoundedRectangle(cornerRadius: 18.5, style: .continuous)) : open
        return shape.fill(.black)
            .overlay { PhoneShootingStars().opacity(stars ? 1 : 0).clipShape(shape) }
            .frame(width: islandSize.width, height: islandSize.height)
    }

    /// Where he is drawn: in the middle of the island, then in the circle at the bottom
    /// (`PhoneOrb`: 68 of the workshop, him 46, on the bottom of the safe area).
    private func yumiPlace(height: CGFloat, bottom: CGFloat) -> (y: CGFloat, size: CGFloat) {
        switch stage {
        case .hidden, .drip: return (11 + u(120) / 2, u(48))
        case .hello: return (11 + u(105), u(80))
        case .falling, .landed: return (height - bottom - u(34), u(46))
        }
    }

    private func play() async {
        engine.setLit(false)
        engine.setMood(.asleep)
        engine.setRim(.calm)
        var clock = 0
        /// Waits until `ms` of the opening; a tap jumps straight to the fall.
        func wait(until ms: Int) async -> Bool {
            while clock < ms {
                if skipped { return false }
                try? await Task.sleep(for: .milliseconds(min(50, ms - clock)))
                clock += min(50, ms - clock)
            }
            return !skipped
        }
        let spring = Animation.spring(response: 0.6, dampingFraction: 0.72)

        intro: do {
            // 1. the Dynamic Island swells into a drop, two sleeping eyes inside it
            guard await wait(until: 150) else { break intro }
            withAnimation(spring) { stage = .drip }
            SoundEngine.shared.play("pop")
            // 2. the eyes open and look left, then right
            guard await wait(until: 800) else { break intro }
            engine.setMood(.surprised)
            engine.play(.pop)
            SoundEngine.shared.play("blip")
            guard await wait(until: 1100) else { break intro }
            engine.setGaze(CGPoint(x: -1, y: 0))
            guard await wait(until: 1400) else { break intro }
            engine.setGaze(CGPoint(x: 1, y: 0))
            // 3. it opens, curious
            guard await wait(until: 1750) else { break intro }
            engine.setGaze(nil)
            engine.setMood(.curious)
            withAnimation(spring) { stage = .hello }
            // 4. the light comes on, he bounces: hello, by name
            guard await wait(until: 2200) else { break intro }
            withAnimation(.easeOut(duration: 0.6)) { stars = true }
            withAnimation(.easeOut(duration: 0.5)) {
                hello = name().map { loc("Bonjour \($0)") } ?? loc("Bonjour")
            }
            engine.setLit(true)
            engine.setMood(.happy)
            engine.setRim(.joy)
            engine.play(.boing)
            SoundEngine.shared.play("greet")
            guard await wait(until: 2750) else { break intro }
            engine.play(.wave)
            guard await wait(until: 3450) else { break intro }
            engine.setMood(.wink)
            guard await wait(until: 3800) else { break intro }
        }
        await fall()
    }

    /// He leaves the island, which closes again into the Dynamic Island; then he falls straight
    /// into the circle, the app appears around him, he lands with a squash, and the circle takes
    /// him with a little jump.
    private func fall() async {
        engine.setGaze(nil)
        engine.setLit(true)
        engine.setRim(.calm)
        // 3800: the island closes, he stays where he was
        hello = nil
        stars = false
        withAnimation(.timingCurve(0.32, 1.22, 0.42, 1, duration: 0.6)) { closed = true }
        try? await Task.sleep(for: .milliseconds(100))
        // 3900: the fall, straight down, faster and faster
        engine.setMood(.surprised)
        withAnimation(.timingCurve(0.55, 0, 0.85, 0.4, duration: 0.62)) { stage = .falling }
        // 4150: the black goes, the cards come in
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: 0.5)) { black = false }
        reveal()
        // 4520: he lands in the circle, which shows
        try? await Task.sleep(for: .milliseconds(370))
        engine.setMood(.happy)
        engine.play(.squash)
        SoundEngine.shared.play("pop")
        landed()
        // 5900: the circle takes him, with a jump
        try? await Task.sleep(for: .milliseconds(1380))
        engine.setMood(nil)
        stage = .landed
        character.onScreen = true
        engine.play(.jump)
        done()
    }
}

/// Shooting stars crossing the island: thin white lines tilted 28°, each its own rhythm.
struct PhoneShootingStars: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                for i in 0..<12 {
                    let duration = 1.4 + Double(i % 4) * 0.35
                    let delay = (Double(i) * 0.47).truncatingRemainder(dividingBy: 2.6)
                    let phase = ((t - delay) / duration).truncatingRemainder(dividingBy: 1)
                    let p = phase < 0 ? phase + 1 : phase
                    let opacity = p < 0.15 ? p / 0.15 : p < 0.7 ? 1 - (p - 0.15) / 0.55 * 0.1 : 0.9 * (1 - (p - 0.7) / 0.3)
                    let origin = CGPoint(x: size.width * Double((i * 53 + 20) % 100) / 100,
                                         y: size.height * Double((i * 37 + 8) % 85) / 100)
                    var c = g
                    c.translateBy(x: origin.x, y: origin.y)
                    c.rotate(by: .degrees(28))
                    c.translateBy(x: u(-30) + p * u(150), y: 0)
                    c.opacity = opacity
                    let length = u(46)
                    let line = Path(roundedRect: CGRect(x: 0, y: -0.75, width: length, height: 1.5), cornerRadius: 1)
                    c.fill(line, with: .linearGradient(Gradient(stops: [.init(color: .clear, location: 0),
                                                                        .init(color: .white, location: 0.7),
                                                                        .init(color: YumiRGB(hex: 0xC9B8FF).color, location: 1)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: length, y: 0)))
                    var glow = c
                    glow.addFilter(.shadow(color: YumiRGB(hex: 0xB49BFF).color, radius: 6))
                    glow.fill(Path(ellipseIn: CGRect(x: length - 3, y: -2, width: 4, height: 4)), with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
