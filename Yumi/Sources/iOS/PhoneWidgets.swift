import SwiftUI
import WidgetKit

/// Feeds the widgets and the Live Activity: what Yumi says now, and pictures of him drawn by
/// the same renderer as everywhere else (a widget cannot run it, so the app draws for it).
@MainActor
enum PhoneWidgets {
    /// The faces the widgets use, by name.
    static let faces: [(name: String, mood: YumiMood?, state: BotState, lit: Bool, gaze: CGPoint?)] = [
        ("happy", .happy, .idle, true, nil),
        ("calm", nil, .idle, true, nil),
        ("asking", .curious, .approval, true, nil),
        ("asleep", .asleep, .sleeping, false, nil),
        ("wink", .wink, .idle, true, nil),
        ("left", nil, .idle, true, CGPoint(x: -1, y: 0.2)),
        ("right", nil, .idle, true, CGPoint(x: 1, y: 0.2)),
        ("surprised", .surprised, .idle, true, nil),
        ("working", .focused, .working, true, nil),
    ]

    private static var drawn = false

    /// Draws his faces once per launch (they only change with his look in the settings).
    static func drawFaces() {
        guard !drawn else { return }
        drawn = true
        for face in faces {
            guard let url = YumiWidgetData.imageURL(face.name) else { continue }
            let renderer = ImageRenderer(content: StillYumi(mood: face.mood, state: face.state, lit: face.lit, gaze: face.gaze)
                .frame(width: 180, height: 180))
            renderer.scale = 3
            if let image = renderer.uiImage, let png = image.pngData() {
                try? png.write(to: url, options: .atomic)
            }
            // A small one for the Dynamic Island: a Live Activity refuses a big picture
            if let small = YumiWidgetData.imageURL("island-" + face.name) {
                let island = ImageRenderer(content: StillYumi(mood: face.mood, state: face.state, lit: face.lit, gaze: face.gaze)
                    .frame(width: 48, height: 48))
                island.scale = 2
                if let png = island.uiImage?.pngData() { try? png.write(to: small, options: .atomic) }
            }
        }
    }

    private static var drawnAmbiance: WeatherAmbiance?

    /// The weather widget: Yumi as the weather makes him, and a few still moments of its ground
    /// that the widget shows one after the other.
    static func drawWeather(_ ambiance: WeatherAmbiance?, force: Bool = false) {
        guard let ambiance, force || ambiance != drawnAmbiance else { return }
        drawnAmbiance = ambiance
        let start = Date().timeIntervalSinceReferenceDate
        for frame in 0..<YumiWidgetData.weatherFrames {
            guard let url = YumiWidgetData.imageURL("weather-\(frame)") else { continue }
            let renderer = ImageRenderer(content: ZStack {
                Color.black
                WeatherEffects(ambiance: ambiance, frozenAt: start + Double(frame) * 0.9)
            }.frame(width: 340, height: 160))
            renderer.scale = 2
            if let png = renderer.uiImage?.pngData() { try? png.write(to: url, options: .atomic) }
        }
        let costume = YumiCostume.current()
        if let url = YumiWidgetData.imageURL("weather-yumi") {
            let renderer = ImageRenderer(content: StillYumi(mood: ambiance.mood ?? .happy, state: .idle, lit: true,
                                                            habit: ambiance.habit,
                                                            costume: ambiance.wearsBeanie && costume == .none ? .beanie : costume)
                .frame(width: 180, height: 180))
            renderer.scale = 3
            if let png = renderer.uiImage?.pngData() { try? png.write(to: url, options: .atomic) }
        }
        // A small one for the Lock Screen
        if let url = YumiWidgetData.imageURL("weather-yumi-small") {
            let renderer = ImageRenderer(content: StillYumi(mood: ambiance.mood ?? .happy, state: .idle, lit: true,
                                                            habit: ambiance.habit,
                                                            costume: ambiance.wearsBeanie && costume == .none ? .beanie : costume)
                .frame(width: 60, height: 60))
            renderer.scale = 2
            if let png = renderer.uiImage?.pngData() { try? png.write(to: url, options: .atomic) }
        }
    }

    private static func hex(_ ambiance: WeatherAmbiance) -> UInt32 {
        let c = UIColor(ambiance.color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UInt32(r * 255) << 16 | UInt32(g * 255) << 8 | UInt32(b * 255)
    }

    /// His colour or costume changed: draw the pictures again and show them.
    static func lookChanged() {
        drawnAmbiance = nil
        drawn = false
        drawFaces()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// The day as the widgets show it. Reloads them only when something changed.
    static func publish(remark: String, today: PhoneToday, mac: LinkSnapshot?, force: Bool = false) {
        drawFaces()
        let now = Date()
        let next = today.events.first { $0.start > now && !$0.isAllDay }
        let data = YumiWidgetData(
            remark: remark,
            nextEvent: next?.title, nextEventAt: next?.start,
            reminders: today.reminders.prefix(3).map(\.title),
            mac: mac.map { "\($0.deviceName) · \($0.sessions.count) session\($0.sessions.count > 1 ? "s" : "")" },
            macWaiting: mac?.approvals.first(where: { $0.expiresAt > now })?.summary,
            updatedAt: now,
            upcoming: today.week.flatMap(\.events).filter { !$0.isAllDay && $0.end > now }.prefix(12)
                .map { .init(title: $0.title, start: $0.start, end: $0.end) },
            dueReminders: today.reminders.prefix(3).map { .init(title: $0.title, due: $0.due) },
            weather: { if case .ready(let report) = today.weather { return "\(PhoneWeather.degrees(report)) · \(WeatherSummary.sky(report.code))" }; return nil }(),
            ambiance: PhoneWeather.ambiance(today.weather)?.rawValue,
            ambianceColor: PhoneWeather.ambiance(today.weather).map(Self.hex),
            degrees: { if case .ready(let report) = today.weather { return PhoneWeather.degrees(report) }; return nil }(),
            place: today.placeName.nonEmpty,
            sky: { if case .ready(let report) = today.weather { return WeatherSummary.sky(report.code) }; return nil }(),
            agents: mac.map { mac in
                mac.sessions.map { session in
                    let waits = mac.approvals.contains { $0.sessionID == session.id && $0.expiresAt > now }
                    let state = PhoneAgentLook.state(session, waiting: waits)
                    return .init(project: session.project, agent: session.agent,
                                 mood: state == .approval ? "wait" : state == .sleeping ? "sleep" : "work", since: session.updatedAt)
                }
            })
        drawWeather(PhoneWeather.ambiance(today.weather))
        var compared = data
        compared.updatedAt = YumiWidgetData.load()?.updatedAt ?? now
        guard force || compared != YumiWidgetData.load() else { return }
        data.save()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// One still picture of Yumi: the engine is run for a moment so that the mood and the light have
/// settled, then drawn once.
struct StillYumi: View {
    let mood: YumiMood?
    let state: BotState
    let lit: Bool
    var gaze: CGPoint? = nil
    var habit: YumiHabit? = nil
    var costume: YumiCostume? = nil

    var body: some View {
        Canvas { context, size in
            let engine = BotEngine()
            engine.setLook(accent: .current(), costume: costume ?? .current())
            engine.setState(state, force: true)
            if let habit { engine.setHabit(habit) }
            engine.setLit(lit)
            engine.setMood(mood)
            if let gaze { engine.setGaze(gaze) }
            // He fills the picture: a widget shows him small enough as it is
            let frame = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.07, dy: size.height * 0.1)
                .offsetBy(dx: 0, dy: size.height * 0.04)
            let start = Date()
            for step in 0...90 { engine.advance(to: start.addingTimeInterval(Double(step) / 30)) }
            engine.draw(context: context, frame: frame)
        }
    }
}
