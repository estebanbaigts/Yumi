import SwiftUI

/// « C'est bon, on est connectés » (workshop: connexion.html): when the iPhone first finds the
/// Mac, the screen darkens, the two devices come together while data flows both ways, Yumi jumps
/// to the middle, a shockwave and shooting stars, then the sentence. About 5 s, a touch ends it.
struct PhoneLinkCelebration: View {
    let macName: String
    var done: () -> Void

    @State private var step = 0
    @State private var engine = BotEngine()

    var body: some View {
        ZStack {
            Color.black.opacity(step >= 1 ? 1 : 0).ignoresSafeArea()
            RadialGradient(colors: [PhoneTheme.violet.opacity(step >= 3 ? (step >= 5 ? 0.3 : 0.55) : 0), .clear],
                           center: UnitPoint(x: 0.5, y: 0.46), startRadius: 4, endRadius: u(260))
                .ignoresSafeArea()
            if step >= 3 {
                PhoneShootingStars().ignoresSafeArea().transition(.opacity)
                Circle().strokeBorder(LinearGradient(colors: [PhoneTheme.pink, PhoneTheme.blue], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .frame(width: u(40), height: u(40))
                    .modifier(Shockwave())
            }
            VStack(spacing: 0) {
                HStack(spacing: step >= 2 ? u(4) : u(14)) {
                    RoundedRectangle(cornerRadius: u(6)).strokeBorder(Color(white: 0.96), lineWidth: 2)
                        .frame(width: u(22), height: u(40))
                        .shadow(color: step >= 3 ? PhoneTheme.blue : .clear, radius: u(10))
                    PhoneLinkWire(state: step >= 1 ? .connecting : .searching).frame(width: u(90), height: u(14))
                    VStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: u(4)).strokeBorder(Color(white: 0.96), lineWidth: 2).frame(width: u(52), height: u(33))
                        Capsule().fill(Color(white: 0.96)).frame(width: u(66), height: 3)
                    }
                    .shadow(color: step >= 3 ? PhoneTheme.pink : .clear, radius: u(10))
                }
                .padding(.top, u(150))
                YumiStage(engine: engine, followsPointer: false)
                    .frame(width: u(100), height: u(100))
                    .scaleEffect(step >= 2 ? 1 : 0.2)
                    .offset(y: step >= 2 ? 0 : u(380))
                    .opacity(step >= 2 ? 1 : 0)
                    .padding(.top, u(40))
                if step >= 4 {
                    VStack(spacing: u(6)) {
                        Text(loc("C'est bon, on est connectés")).font(.system(size: u(22), weight: .bold))
                        Text(loc("Ton iPhone et \(macName) se parlent, par ton iCloud."))
                            .font(.system(size: u(13))).foregroundStyle(PhoneTheme.soft).multilineTextAlignment(.center)
                    }
                    .padding(.top, u(26)).padding(.horizontal, u(24))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                Spacer()
            }
            .opacity(step >= 1 ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .task { await play() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(loc("C'est bon, on est connectés")))
    }

    private func play() async {
        engine.setLook(accent: .current(), costume: .current())
        engine.setState(.idle, force: true)
        engine.setMood(.surprised)
        withAnimation(.easeOut(duration: 0.5)) { step = 1 }
        SoundEngine.shared.play("blip")
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.spring(response: 0.8, dampingFraction: 0.62)) { step = 2 }
        engine.play(.jump)
        engine.setMood(.happy)
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.easeOut(duration: 0.5)) { step = 3 }
        engine.play(.celebrate)
        SoundEngine.shared.play("love")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { step = 4 }
        try? await Task.sleep(for: .milliseconds(1000))
        withAnimation(.easeInOut(duration: 0.6)) { step = 5 }
        engine.play(.wave)
        try? await Task.sleep(for: .milliseconds(1800))
        finish()
    }

    private func finish() {
        withAnimation(.easeIn(duration: 0.4)) { step = 0 }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            done()
        }
    }
}

/// A ring that grows nine times and fades, once.
private struct Shockwave: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content.scaleEffect(on ? 9 : 0.3).opacity(on ? 0 : 1)
            .onAppear { withAnimation(.timingCurve(0.1, 0.7, 0.3, 1, duration: 1.1)) { on = true } }
    }
}
