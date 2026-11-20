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
        .configurationDisplayName("Yumi")
        .description("Ce que Yumi a à te dire aujourd'hui.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var data: YumiWidgetData
        /// Which of his faces this moment shows: he changes expression through the hour.
        var beat = 0
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .placeholder) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date(), data: YumiWidgetData.load() ?? .placeholder))
        }

        /// An hour of moments, ten minutes apart: iOS shows each in turn, with a transition, so
        /// that he lives a little on the home screen (a widget cannot run an animation).
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let data = YumiWidgetData.load() ?? .placeholder
            let now = Date()
            let entries = (0..<6).map { Entry(date: now.addingTimeInterval(Double($0) * 600), data: data, beat: $0) }
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }
}

private struct WidgetNight: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.06, blue: 0.15)
            RadialGradient(colors: [Color(red: 0.55, green: 0.42, blue: 1).opacity(0.35), .clear],
                           center: .top, startRadius: 4, endRadius: 180)
        }
    }
}

private struct YumiTodayView: View {
    let entry: YumiTodayWidget.Entry
    @Environment(\.widgetFamily) private var family

    private var face: String {
        if entry.data.macWaiting != nil { return "asking" }
        let hour = Calendar.current.component(.hour, from: entry.date)
        if hour >= 23 || hour < 6 { return "asleep" }
        return ["happy", "calm", "wink", "happy", "calm", "happy"][entry.beat % 6]
    }

    /// His face of the moment, swapped with a soft transition from one moment to the next.
    private func yumi(_ size: CGFloat) -> some View {
        YumiPicture(name: face, size: size)
            .id(face)
            .transition(.push(from: .bottom).combined(with: .opacity))
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
                yumi(96)
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
                yumi(64)
                Spacer(minLength: 0)
                countdown
                Text(line).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
            }
        }
    }
}
