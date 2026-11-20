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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }

    struct Entry: TimelineEntry {
        var date: Date
        var data: YumiWidgetData
    }

    struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { Entry(date: Date(), data: .placeholder) }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            completion(Entry(date: Date(), data: YumiWidgetData.load() ?? .placeholder))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let entry = Entry(date: Date(), data: YumiWidgetData.load() ?? .placeholder)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
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
        return "happy"
    }

    private var line: String { entry.data.macWaiting.map { "Ton Mac attend ton accord : \($0)" } ?? entry.data.remark }

    var body: some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("Yumi").font(.headline)
                Text(line).font(.caption).lineLimit(2)
            }
        case .systemMedium:
            HStack(spacing: 12) {
                YumiPicture(name: face, size: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text(line).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
                    if let event = entry.data.nextEvent, let at = entry.data.nextEventAt {
                        Label("\(at.formatted(date: .omitted, time: .shortened)) · \(event)", systemImage: "calendar")
                            .font(.caption).foregroundStyle(.white.opacity(0.75)).lineLimit(1)
                    }
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
                YumiPicture(name: face, size: 64)
                Spacer(minLength: 0)
                Text(line).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(3)
            }
        }
    }
}
