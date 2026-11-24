import SwiftUI
import WidgetKit

/// The colours of the widgets: almost black, his greys and the colours of the app's cards.
enum WidgetInk {
    static func hex(_ value: UInt32, _ alpha: Double = 1) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255, opacity: alpha)
    }
    static let ground = hex(0x0A0A0E)
    static let gray = hex(0x8E8E93)
    static let coral = hex(0xFF8A7A)
    static let blue = hex(0x5B8CFF)
    static let amber = hex(0xFFB547)
    static let timer = hex(0x7FD0FF)
    static let code = hex(0xFFE3B0)
    static let refuse = hex(0xFF453A)
    static let allow = hex(0x30D158)
    static let bars: [Color] = [hex(0xFF8A7A), hex(0xF2B36B), hex(0x3DDC97), hex(0x8B9CFF)]
}

/// Yumi on the home screen: the next thing of the day (small), the day with the weather (medium),
/// and on the Lock Screen. The app writes the data (`PhoneWidgets`); iOS asks again every minute
/// of the hour so that his face changes, and whenever the app has news.
struct YumiTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YumiToday", provider: Provider()) { entry in
            YumiTodayView(entry: entry)
                .containerBackground(WidgetInk.ground, for: .widget)
        }
        .configurationDisplayName("Yumi")
        .description("Ce que Yumi a à te dire aujourd'hui.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var data: YumiWidgetData
        /// Which of his faces this moment shows: he changes expression through the hour.
        var beat = 0
        /// Just touched: the face of his reaction, which wins over the hour's.
        var reaction: String? = nil
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .placeholder) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date(), data: (YumiWidgetData.load() ?? .placeholder).at(Date())))
        }

        /// An hour of moments, one a minute: iOS shows each in turn with a transition, so that
        /// he looks around and changes expression on the home screen (a widget cannot run a
        /// continuous animation).
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(Self.timeline(now: Date()))
        }

        static func timeline(now: Date) -> Timeline<Entry> {
            let data = YumiWidgetData.load() ?? .placeholder
            var entries: [Entry] = []
            // Just touched: a short reaction, one face every 0.9 s
            if let poke = YumiWidgetPokes.recent(now: now) {
                for (i, face) in YumiWidgetPokes.reaction(poke.count).enumerated() {
                    entries.append(Entry(date: now.addingTimeInterval(Double(i) * 0.9), data: data.at(now), beat: 0, reaction: face))
                }
            }
            // Then a moment every 20 s for the hour: his face changes each minute, the weather's
            // ground moves each moment (a widget cannot run an animation; iOS cross-fades them)
            let step = (now.timeIntervalSince1970 / 20).rounded(.down) * 20 + 20
            entries += (0..<180).map {
                let date = Date(timeIntervalSince1970: step + Double($0) * 20)
                return Entry(date: date, data: data.at(date), beat: $0)
            }
            if entries.first.map({ $0.date > now }) ?? true { entries.insert(Entry(date: now, data: data.at(now), beat: 0), at: 0) }
            // Asked again within the hour at the latest, and at midnight: a new day, a new agenda
            let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
            return Timeline(entries: entries.filter { $0.date < midnight }, policy: .after(min(midnight, now.addingTimeInterval(3600))))
        }
    }
}

/// His face of the moment, from the hour, a request of the Mac, or a touch.
enum WidgetFace {
    static func of(_ entry: YumiTodayWidget.Entry) -> String {
        if let reaction = entry.reaction { return reaction }
        if entry.data.macWaiting != nil { return "asking" }
        let hour = Calendar.current.component(.hour, from: entry.date)
        if hour >= 23 || hour < 6 { return "asleep" }
        return ["happy", "left", "calm", "right", "wink", "happy", "surprised", "calm"][(entry.beat / 3) % 8]
    }

    static func agent(_ mood: String) -> String {
        switch mood {
        case "wait": "asking"
        case "sleep": "asleep"
        default: "working"
        }
    }
}

/// « dans 18 min » until the hour, then « dans 2 h 15 ».
func widgetUntil(_ date: Date, now: Date) -> String {
    let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
    if minutes < 60 { return String(localized: "dans \(minutes) min") }
    return String(localized: "dans \(minutes / 60) h \(String(format: "%02d", minutes % 60))")
}

private struct YumiTodayView: View {
    let entry: YumiTodayWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var face: String { WidgetFace.of(entry) }

    /// Touch him and he reacts (YumiWidgetPoke), without opening the app.
    private func yumi(_ size: CGFloat) -> some View {
        Button(intent: YumiWidgetPoke()) {
            YumiPicture(name: face, size: size)
                .offset(y: entry.beat % 2 == 0 ? 0 : -2)
                .id(face)
                .transition(entry.reaction == nil ? .push(from: .bottom).combined(with: .opacity)
                                                  : .scale(scale: 0.7).combined(with: .opacity))
        }
        .buttonStyle(.plain)
    }

    private var line: String { entry.data.macWaiting.map { String(localized: "Ton Mac attend ton accord : \($0)") } ?? entry.data.remark }

    private var upcoming: [YumiWidgetData.Event] {
        (entry.data.upcoming ?? []).filter { $0.end > entry.date && Calendar.current.isDate($0.start, inSameDayAs: entry.date) }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                YumiPicture(name: face, size: 40)
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let title = entry.data.nextEvent, let at = entry.data.nextEventAt {
                    Text("\(at.formatted(date: .omitted, time: .shortened)) \(title)").font(.headline).lineLimit(1)
                    Text(lockDetail(at)).font(.caption).lineLimit(1).opacity(0.8)
                } else {
                    Text("Yumi").font(.headline)
                    Text(line).font(.caption).lineLimit(2).opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemMedium: medium
        default: small
        }
    }

    private func lockDetail(_ at: Date) -> String {
        let working = entry.data.agents?.filter { $0.mood != "sleep" }.count ?? 0
        let until = widgetUntil(at, now: entry.date)
        return working > 0 ? String(localized: "\(until) · \(working) agents") : until
    }

    /// Yumi at the top, the next event at the bottom: when, what.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                yumi(44)
                Spacer()
                Text("Yumi").font(.system(size: 13)).foregroundStyle(WidgetInk.gray)
            }
            Spacer(minLength: 0)
            if let title = entry.data.nextEvent, let at = entry.data.nextEventAt {
                Text(widgetUntil(at, now: entry.date)).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(WidgetInk.coral)
                Text(at.formatted(date: .omitted, time: .shortened)).font(.system(size: 26, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.white)
                Text(title).font(.system(size: 14)).foregroundStyle(.white).lineLimit(1)
            } else {
                Text(line).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
            }
        }
    }

    /// Yumi on the left; the date and the weather, then the next three things of the day.
    private var medium: some View {
        HStack(spacing: 16) {
            yumi(92)
            VStack(alignment: .leading, spacing: 6) {
                Text([entry.date.formatted(.dateTime.weekday(.wide).day()).capitalized, entry.data.weather]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13.5)).foregroundStyle(WidgetInk.gray).lineLimit(1)
                if upcoming.isEmpty {
                    Text(line).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(3)
                }
                ForEach(Array(upcoming.prefix(3).enumerated()), id: \.offset) { index, event in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(WidgetInk.bars[index % WidgetInk.bars.count]).frame(width: 4, height: 18)
                        Text(event.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 16, weight: .bold)).monospacedDigit()
                        Text(event.title).font(.system(size: 16)).lineLimit(1)
                    }
                    .foregroundStyle(.white)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// The agents of the Mac at a glance: who works, who waits.
struct YumiAgentsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YumiAgents", provider: YumiTodayWidget.Provider()) { entry in
            YumiAgentsView(entry: entry)
                .containerBackground(WidgetInk.ground, for: .widget)
        }
        .configurationDisplayName("Agents")
        .description("Tes agents sur le Mac, et ce qui attend ta réponse.")
        .supportedFamilies([.systemSmall])
    }
}

private struct YumiAgentsView: View {
    let entry: YumiTodayWidget.Entry

    var body: some View {
        let agents = entry.data.agents ?? []
        let waiting = agents.filter { $0.mood == "wait" }.count
        VStack(alignment: .leading, spacing: 0) {
            Text("Agents").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(WidgetInk.blue)
            if entry.data.agents == nil {
                Spacer(minLength: 0)
                Text("Relie ton Mac pour voir tes agents.").font(.system(size: 14)).foregroundStyle(WidgetInk.gray)
            } else if agents.isEmpty {
                Spacer(minLength: 0)
                Text("Aucun agent en cours.").font(.system(size: 14)).foregroundStyle(WidgetInk.gray)
            }
            ForEach(Array(agents.prefix(3).enumerated()), id: \.offset) { _, agent in
                HStack(spacing: 8) {
                    YumiPicture(name: WidgetFace.agent(agent.mood), size: 28)
                    Text(agent.project).font(.system(size: 15)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    if agent.mood == "wait" {
                        Text("attend").font(.system(size: 13.5)).foregroundStyle(WidgetInk.amber)
                    } else if agent.mood == "work" {
                        Text(agent.since, style: .timer).font(.system(size: 13.5)).monospacedDigit()
                            .foregroundStyle(WidgetInk.gray).multilineTextAlignment(.trailing).frame(maxWidth: 48)
                    }
                }
                .padding(.top, 9)
            }
            Spacer(minLength: 0)
            if waiting > 0 {
                Text("\(waiting) demande en attente").font(.system(size: 13)).foregroundStyle(WidgetInk.gray)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Yumi in the weather: the ground of the ambiance moving behind him, the degrees and the sky.
struct YumiWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YumiWeather", provider: YumiTodayWidget.Provider()) { entry in
            YumiWeatherView(entry: entry)
                .containerBackground(for: .widget) { YumiWeatherGround(entry: entry) }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Météo de Yumi")
        .description("Yumi dans la météo d'ici, avec son ambiance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// One still moment of the ambiance's ground, a different one at each moment of the timeline.
private struct YumiWeatherGround: View {
    let entry: YumiTodayWidget.Entry

    var body: some View {
        ZStack {
            Color.black
            if entry.data.ambiance != nil,
               let url = YumiWidgetData.imageURL("weather-\(entry.beat % YumiWidgetData.weatherFrames)"),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFill()
                    .id(entry.beat)
                    .transition(.opacity)
            }
        }
    }
}

private struct YumiWeatherView: View {
    let entry: YumiTodayWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var color: Color { entry.data.ambianceColor.map { WidgetInk.hex($0) } ?? WidgetInk.timer }

    private var yumi: some View {
        Button(intent: YumiWidgetPoke()) {
            Group {
                if let url = YumiWidgetData.imageURL("weather-yumi"), let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).scaledToFit()
                } else {
                    YumiPicture(name: WidgetFace.of(entry), size: 60)
                }
            }
            // He breathes: a little up, a little down, from one moment to the next
            .offset(y: entry.beat % 2 == 0 ? 0 : -3)
            .animation(.easeInOut(duration: 1.2), value: entry.beat)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: -2) {
                    YumiPicture(name: "weather-yumi-small", size: 30)
                    Text(entry.data.degrees ?? "–").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                YumiPicture(name: "weather-yumi-small", size: 38)
                VStack(alignment: .leading, spacing: 0) {
                    Text([entry.data.degrees, entry.data.ambiance.map(Self.name)].compactMap { $0 }.joined(separator: " · "))
                        .font(.headline).lineLimit(1)
                    Text([entry.data.place, entry.data.sky].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).lineLimit(2).opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text([entry.data.degrees, entry.data.sky].compactMap { $0 }.joined(separator: " · "))
        default:
            home
        }
    }

    @ViewBuilder private var home: some View {
        if entry.data.degrees == nil {
            VStack(spacing: 8) {
                YumiPicture(name: "calm", size: 54)
                Text("Ouvre Yumi pour avoir la météo d'ici.").font(.system(size: 12)).foregroundStyle(WidgetInk.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(14)
        } else if family == .systemMedium {
            HStack(spacing: 14) {
                yumi.frame(width: 104, height: 104)
                info(big: 44)
                Spacer(minLength: 0)
            }
            .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    yumi.frame(width: 58, height: 58)
                    Spacer()
                    Text(entry.data.degrees ?? "").font(.system(size: 30, weight: .light)).monospacedDigit().foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                info(big: nil)
            }
            .padding(14)
        }
    }

    private func info(big: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.data.place ?? String(localized: "Météo")).font(.system(size: 11, weight: .bold)).textCase(.uppercase)
                .foregroundStyle(color)
            if let big {
                Text(entry.data.degrees ?? "").font(.system(size: big, weight: .light)).monospacedDigit().foregroundStyle(.white)
            }
            Text(entry.data.ambiance.map(Self.name) ?? "").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text(entry.data.sky ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
        }
    }

    private static func name(_ raw: String) -> String {
        switch raw {
        case "pluie": String(localized: "Pluie")
        case "soleil": String(localized: "Soleil")
        case "neige": String(localized: "Neige")
        case "nuit": String(localized: "Nuit")
        case "chaud": String(localized: "Chaud")
        case "froid": String(localized: "Froid")
        default: String(localized: "Doux")
        }
    }
}
