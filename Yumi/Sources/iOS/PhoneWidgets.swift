import SwiftUI
import WidgetKit

/// Feeds the widgets and the Live Activity: what Yumi says now, and pictures of him drawn by
/// the same renderer as everywhere else (a widget cannot run it, so the app draws for it).
@MainActor
enum PhoneWidgets {
    /// The faces the widgets use, by name.
    static let faces: [(name: String, mood: YumiMood?, state: BotState, lit: Bool)] = [
        ("happy", .happy, .idle, true),
        ("calm", nil, .idle, true),
        ("asking", .curious, .approval, true),
        ("asleep", .asleep, .sleeping, false),
        ("wink", .wink, .idle, true),
    ]

    private static var drawn = false

    /// Draws his faces once per launch (they only change with his look in the settings).
    static func drawFaces() {
        guard !drawn else { return }
        drawn = true
        for face in faces {
            guard let url = YumiWidgetData.imageURL(face.name) else { continue }
            let renderer = ImageRenderer(content: StillYumi(mood: face.mood, state: face.state, lit: face.lit)
                .frame(width: 180, height: 180))
            renderer.scale = 3
            if let image = renderer.uiImage, let png = image.pngData() {
                try? png.write(to: url, options: .atomic)
            }
        }
    }

    /// His colour or costume changed: draw the pictures again and show them.
    static func lookChanged() {
        drawn = false
        drawFaces()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The day as the widgets show it. Reloads them only when something changed.
    static func publish(remark: String, today: PhoneToday, mac: LinkSnapshot?) {
        drawFaces()
        let now = Date()
        let next = today.events.first { $0.start > now && !$0.isAllDay }
        let data = YumiWidgetData(
            remark: remark,
            nextEvent: next?.title, nextEventAt: next?.start,
            reminders: today.reminders.prefix(3).map(\.title),
            mac: mac.map { "\($0.deviceName) · \($0.sessions.count) session\($0.sessions.count > 1 ? "s" : "")" },
            macWaiting: mac?.approvals.first(where: { $0.expiresAt > now })?.summary,
            updatedAt: now)
        var compared = data
        compared.updatedAt = YumiWidgetData.load()?.updatedAt ?? now
        guard compared != YumiWidgetData.load() else { return }
        data.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// One still picture of Yumi: the engine is run for a moment so that the mood and the light have
/// settled, then drawn once.
private struct StillYumi: View {
    let mood: YumiMood?
    let state: BotState
    let lit: Bool

    var body: some View {
        Canvas { context, size in
            let engine = BotEngine()
            engine.setLook(accent: .current(), costume: .current())
            engine.setState(state, force: true)
            engine.setLit(lit)
            engine.setMood(mood)
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.18, dy: size.height * 0.18)
            let start = Date()
            for step in 0...90 { engine.advance(to: start.addingTimeInterval(Double(step) / 30)) }
            engine.draw(context: context, frame: frame)
        }
    }
}
