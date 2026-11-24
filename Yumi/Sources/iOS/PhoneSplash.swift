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
    /// He landed in the circle: the cover is removed, the circle draws him from now on.
    var done: () -> Void

    private enum Stage: Int { case hidden, drip, hello, falling, landed }

    @State private var stage = Stage.hidden
    @State private var hello: String?
    @State private var black = true
    @State private var falling = false
    @State private var skipped = false

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
    private var islandSize: CGSize {
        switch stage {
        case .drip: CGSize(width: u(140), height: u(120))
        case .hello: CGSize(width: u(230), height: u(210))
        default: CGSize(width: 126, height: 37)
        }
    }

    private var island: some View {
        let shape: AnyShape = switch stage {
        case .drip: AnyShape(UnevenRoundedRectangle(topLeadingRadius: u(20), bottomLeadingRadius: u(70),
                                                    bottomTrailingRadius: u(70), topTrailingRadius: u(20), style: .continuous))
        case .hello: AnyShape(RoundedRectangle(cornerRadius: u(44), style: .continuous))
        default: AnyShape(RoundedRectangle(cornerRadius: 18.5, style: .continuous))
        }
        return shape.fill(.black)
            .overlay(shape.stroke(PhoneTheme.rim, lineWidth: 1.2).opacity(stage == .hello ? 0.8 : 0))
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

    /// He leaves the island, which closes again, and falls straight into the circle; the app
    /// appears around him, he lands with a squash, and the circle takes him.
    private func fall() async {
        engine.setGaze(nil)
        engine.setLit(true)
        engine.setRim(.calm)
        engine.setMood(.surprised)
        hello = nil
        withAnimation(.timingCurve(0.55, 0, 0.85, 0.4, duration: 0.62)) { stage = .falling }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeInOut(duration: 0.5)) { black = false }
        reveal()
        try? await Task.sleep(for: .milliseconds(370))
        engine.setMood(.happy)
        engine.play(.squash)
        SoundEngine.shared.play("pop")
        try? await Task.sleep(for: .milliseconds(500))
        engine.setMood(nil)
        stage = .landed
        character.onScreen = true
        done()
    }
}
