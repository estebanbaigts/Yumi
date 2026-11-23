import SwiftUI

/// TimelineView + Canvas for one engine. The canvas is larger than the frame it is given
/// (BotEngine.canvasRect) and centred on it, so the layout is unchanged and nothing is cut.
struct YumiStage: View {
    /// Observed for its cadence only: the engine publishes nothing else.
    @ObservedObject var engine: BotEngine
    var particleOverhang: CGFloat = 0
    var paused = false
    /// false for a character that must not react to the pointer (galleries).
    var followsPointer = true

    @State private var probe = YumiScreenProbe()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let frame = CGRect(origin: .zero, size: geo.size)
            let room = BotEngine.canvasRect(for: frame, overhang: particleOverhang)
            // Every frame while he moves, thirty a second during a habit that lasts, fifteen while
            // he only breathes, none while nothing changes or he is not shown
            TimelineView(.animation(minimumInterval: engine.cadence.interval,
                                    paused: paused || engine.cadence == .still)) { timeline in
                Canvas { context, _ in
                    engine.particleOverhang = particleOverhang
                    engine.displayScale = displayScale
                    if followsPointer, let look = probe.look() { engine.pointer = look }
                    engine.advance(to: timeline.date)
                    var ctx = context
                    ctx.translateBy(x: -room.minX, y: -room.minY)
                    engine.draw(context: ctx, frame: frame)
                }
            }
            .frame(width: room.width, height: room.height)
            .position(x: room.midX, y: room.midY)
        }
        .background(YumiProbeView(probe: probe))
    }
}

/// Knows where the character is on screen, to turn the pointer position into a look direction.
#if canImport(AppKit)
import AppKit

@MainActor
final class YumiScreenProbe {
    weak var view: NSView?

    /// Same falloff as the mock-up: tanh of the distance over 220 pt sideways, 180 pt vertically.
    func look() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let rect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let mouse = NSEvent.mouseLocation
        return CGPoint(x: tanh((mouse.x - rect.midX) / 220), y: tanh((rect.midY - mouse.y) / 180))
    }
}

private struct YumiProbeView: NSViewRepresentable {
    let probe: YumiScreenProbe

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        probe.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        probe.view = nsView
    }
}
#else
/// No pointer on a touch screen: the character looks where his engine decides.
@MainActor
final class YumiScreenProbe {
    func look() -> CGPoint? { nil }
}

private struct YumiProbeView: View {
    let probe: YumiScreenProbe
    var body: some View { Color.clear }
}
#endif
