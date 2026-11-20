import SwiftUI

/// The opening, as on the Mac (Island/IslandLaunch.swift): on black, the Dynamic Island itself
/// stretches, two sleeping eyes open inside it, the light comes on and he says hello by name.
/// Then the drop goes back up into the Dynamic Island taking him with it, the black warms into
/// his night, and he pops up again at his place in the app. About 3.5 s; a tap skips it.
///
/// iOS draws nothing of an app before it opens: the opening starts once the app is in front.
struct PhoneSplash: View {
    let character: PhoneCharacter
    /// His first name, read when he says hello (the memory may load during the opening).
    var name: () -> String?
    /// Told when it is over (or skipped): the cover is gone, the home screen shows its cards.
    var done: () -> Void

    private enum Stage: Int { case hidden, drip, hello, leaving, gone }

    @State private var stage = Stage.hidden
    @State private var hello: String?
    @State private var finished = false
    @State private var yumiInDrop = true

    private var engine: BotEngine { character.engine }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let top = geo.safeAreaInsets.top
            ZStack(alignment: .topLeading) {
                // Black, then his night: the home screen's own background, so the hand-over is invisible
                PhoneTheme.background
                Color.black.ignoresSafeArea().opacity(stage.rawValue >= Stage.leaving.rawValue ? 0 : 1)
                island(width: width)
                    .position(x: width / 2, y: 11 + islandSize(width).height / 2)
                if let hello, stage == .hello {
                    Text(hello)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: islandSize(width).width - 175, alignment: .leading)
                        .position(x: width / 2 + 72, y: 11 + islandSize(width).height / 2 + 6)
                        .transition(.opacity.combined(with: .offset(x: 16)))
                }
                // Him, above the island, so that he can leave it. Not drawn before he appears
                // nor after the home screen took him: a Canvas at opacity 0 stalls the renderer.
                if yumiInDrop, stage == .drip || stage == .hello || stage == .leaving {
                    let place = yumiPlace(width: width, top: top)
                    YumiStage(engine: engine, followsPointer: false)
                        .frame(width: place.size, height: place.size)
                        .position(place.center)
                }
            }
            .ignoresSafeArea()
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await land() } }
        .accessibilityLabel(Text(hello ?? AppIdentity.characterName))
        .task { await play() }
    }

    private func islandSize(_ width: CGFloat) -> CGSize {
        switch stage {
        case .hidden, .leaving, .gone: CGSize(width: 126, height: 37)
        case .drip: CGSize(width: 170, height: 96)
        case .hello: CGSize(width: min(width - 24, 370), height: 190)
        }
    }

    private func island(width: CGFloat) -> some View {
        let size = islandSize(width)
        let radius: CGFloat = stage == .drip ? 42 : (stage == .hello ? 44 : 18.5)
        return ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black)
            // On black, his rim draws the island's edge
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(PhoneTheme.rim, lineWidth: 1.2)
                .opacity(stage == .hello ? 0.8 : 0)
        }
        .frame(width: size.width, height: size.height)
    }

    /// Where he is drawn, in screen points (the view ignores the safe area).
    private func yumiPlace(width: CGFloat, top: CGFloat) -> (center: CGPoint, size: CGFloat) {
        let islandMid = 11 + islandSize(width).height / 2
        switch stage {
        case .hidden, .drip: return (CGPoint(x: width / 2, y: islandMid + 4), 80)
        case .hello: return (CGPoint(x: width / 2 - 95, y: islandMid + 6), 120)
        case .leaving, .gone:
            // Back up into the Dynamic Island, small, with the drop
            return (CGPoint(x: width / 2, y: 11 + 18.5), 26)
        }
    }

    private func play() async {
        engine.setLit(false)
        engine.setMood(.asleep)
        engine.setRim(.calm)
        var clock = 0
        func wait(until ms: Int) async {
            try? await Task.sleep(for: .milliseconds(max(ms - clock, 0)))
            clock = ms
        }
        let spring = Animation.spring(response: 0.5, dampingFraction: 0.74)

        // 1. the Dynamic Island swells, two sleeping eyes inside it
        await wait(until: 150)
        withAnimation(spring) { stage = .drip }
        SoundEngine.shared.play("pop")
        // 2. the eyes open and check left, then right
        await wait(until: 600)
        engine.setMood(.surprised)
        engine.play(.pop)
        SoundEngine.shared.play("blip")
        await wait(until: 820)
        engine.setGaze(CGPoint(x: -1, y: 0))
        await wait(until: 1040)
        engine.setGaze(CGPoint(x: 1, y: 0))
        // 3. it opens, the light comes on, he waves: hello, by name
        await wait(until: 1250)
        withAnimation(spring) {
            stage = .hello
            hello = name().map { loc("Hello \($0) !") } ?? loc("Hello !")
        }
        engine.setLit(true)
        engine.setMood(.happy)
        engine.setRim(.joy)
        engine.play(.wave)
        SoundEngine.shared.play("greet")
        // 4. a wink, then he lands on the home screen
        await wait(until: 2350)
        engine.setMood(.wink)
        await wait(until: 2700)
        await land()
    }

    /// The drop goes back up into the Dynamic Island and takes him with it, the black warms into
    /// his night; then he pops up again at his place on the home screen (same engine), and the
    /// cards come in under him.
    private func land() async {
        guard !finished else { return }
        finished = true
        engine.setRim(.calm)
        engine.setGaze(nil)
        // His light goes out and his eyes close: black on the black drop, as on the Mac
        engine.setLit(false)
        engine.setMood(.asleep)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { stage = .leaving }
        SoundEngine.shared.play("close")
        // No longer drawn well before the drop reaches the notch: nothing of him shows in it
        try? await Task.sleep(for: .milliseconds(180))
        yumiInDrop = false
        try? await Task.sleep(for: .milliseconds(300))
        // Gone into the notch; he comes back on the home screen, lit
        engine.setMood(nil)
        engine.setLit(true)
        stage = .gone
        character.onScreen = true
        engine.play(.arrive)
        SoundEngine.shared.play("pop")
        done()
    }
}
