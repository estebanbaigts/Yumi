import SwiftUI
import WidgetKit

/// Yumi on the home screen: his face of the moment and what he has to say (the next event,
/// the reminders, the Mac). The app writes it (`PhoneWidgets`); iOS asks again every 15 minutes
/// and whenever the app has news.
struct YumiTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "YumiToday", provider: Provider()) { entry in
            YumiTodayView(entry: entry)
                .containerBackground(for: .widget) { WidgetNight() }
        }
        // His night is drawn by the view itself (see YumiTodayView), edge to edge
        .contentMarginsDisabled()
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
            completion(Entry(date: Date(), data: YumiWidgetData.load() ?? .placeholder))
        }

        /// An hour of moments, one a minute: iOS shows each in turn with a transition, so that
        /// he looks around and changes expression on the home screen (a widget cannot run a
        /// continuous animation).
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let data = YumiWidgetData.load() ?? .placeholder
            let now = Date()
            var entries: [Entry] = []
            // Just touched: a short reaction, one face every 0.9 s
            if let poke = YumiWidgetPokes.recent(now: now) {
                for (i, face) in YumiWidgetPokes.reaction(poke.count).enumerated() {
                    entries.append(Entry(date: now.addingTimeInterval(Double(i) * 0.9), data: data, beat: 0, reaction: face))
                }
            }
            // Then a face a minute, from the next whole minute
            let minute = (now.timeIntervalSince1970 / 60).rounded(.down) * 60 + 60
            entries += (0..<60).map { Entry(date: Date(timeIntervalSince1970: minute + Double($0) * 60), data: data, beat: $0) }
            if entries.first.map({ $0.date > now }) ?? true { entries.insert(Entry(date: now, data: data, beat: 0), at: 0) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

/// His night, light enough for a black Yumi to stand out: violet at the top, a halo behind him.
/// Drawn as a picture so that iOS keeps its colours on a tinted or clear home screen, where it
/// takes the widget's own background away and turns the rest to one colour.
private struct WidgetNight: View {
    var body: some View {
        Image(uiImage: Self.picture)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .scaledToFill()
    }

    private static let picture: UIImage = {
        let size = CGSize(width: 360, height: 360)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let linear = CGGradient(colorsSpace: space, colors: [
                UIColor(red: 0.24, green: 0.2, blue: 0.5, alpha: 1).cgColor,
                UIColor(red: 0.1, green: 0.1, blue: 0.27, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(linear, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            let halo = CGGradient(colorsSpace: space, colors: [
                UIColor(red: 0.62, green: 0.5, blue: 1, alpha: 0.55).cgColor,
                UIColor(red: 0.62, green: 0.5, blue: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            let center = CGPoint(x: size.width * 0.27, y: size.height * 0.36)
            cg.drawRadialGradient(halo, startCenter: center, startRadius: 2, endCenter: center, endRadius: 150, options: [])
        }
    }()
}

private struct YumiTodayView: View {
    let entry: YumiTodayWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var face: String {
        if let reaction = entry.reaction { return reaction }
        if entry.data.macWaiting != nil { return "asking" }
        let hour = Calendar.current.component(.hour, from: entry.date)
        if hour >= 23 || hour < 6 { return "asleep" }
        return ["happy", "left", "calm", "right", "wink", "happy", "surprised", "calm"][entry.beat % 8]
    }

    /// His face of the moment, swapped with a soft transition from one moment to the next.
    /// Touch him and he reacts (YumiWidgetPoke), without opening the app.
    private func yumi(_ size: CGFloat) -> some View {
        Button(intent: YumiWidgetPoke()) {
            YumiPicture(name: face, size: size)
                .id(face)
                .transition(entry.reaction == nil ? .push(from: .bottom).combined(with: .opacity)
                                                  : .scale(scale: 0.7).combined(with: .opacity))
        }
        .buttonStyle(.plain)
    }

    /// « dans 2 h 15 », kept up to date by iOS itself.
    @ViewBuilder private var countdown: some View {
        if let at = entry.data.nextEventAt, at > entry.date, let event = entry.data.nextEvent {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                Text(event).lineLimit(1)
                Text(at, style: .relative).monospacedDigit()
            }
            .font(.caption).foregroundStyle(.white.opacity(0.75))
        }
    }

    private var line: String { entry.data.macWaiting.map { "Ton Mac attend ton accord : \($0)" } ?? entry.data.remark }

    var body: some View {
        if family == .systemSmall || family == .systemMedium {
            ZStack {
                WidgetNight()
                content.padding(16)
            }
        } else {
            content
        }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                YumiPicture(name: face, size: 46)
            }
        case .accessoryRectangular:
            HStack(spacing: 6) {
                YumiPicture(name: face, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Yumi").font(.headline)
                    Text(line).font(.caption).lineLimit(2)
                }
            }
        case .systemMedium:
            HStack(spacing: 12) {
                yumi(118)
                VStack(alignment: .leading, spacing: 6) {
                    Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
                    countdown
                    if let first = entry.data.reminders.first {
                        Label(first, systemImage: "circle").font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                    if let mac = entry.data.mac {
                        Label(mac, systemImage: "laptopcomputer").font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        default:
            VStack(alignment: .leading, spacing: 4) {
                yumi(78)
                Spacer(minLength: 0)
                countdown
                Text(line).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
            }
        }
    }
}
