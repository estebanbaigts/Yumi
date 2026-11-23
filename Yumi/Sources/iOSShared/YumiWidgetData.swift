import Foundation
import SwiftUI
import WidgetKit

/// What the app leaves for its widgets, in the App Group both share: what Yumi says now, the
/// next event, the reminders, the Mac, and pictures of him drawn by the real renderer (a widget
/// cannot run it). Written by the app each time the day changes; read by the widgets.
struct YumiWidgetData: Codable, Equatable {
    var remark: String
    var nextEvent: String?
    var nextEventAt: Date?
    var reminders: [String]
    /// « MacBook Pro · 2 sessions », nil without the link.
    var mac: String?
    /// A request of the Mac waiting for an answer.
    var macWaiting: String?
    var updatedAt: Date
    /// The coming events and the reminders, with their times: the widget works out by itself,
    /// minute after minute, what comes next and what is over, without waiting for the app.
    var upcoming: [Event]? = nil
    var dueReminders: [Reminder]? = nil

    struct Event: Codable, Equatable {
        var title: String
        var start: Date
        var end: Date
    }

    struct Reminder: Codable, Equatable {
        var title: String
        var due: Date?
    }

    /// The day as it is at `date`: the next event not started yet, the reminders still there.
    func at(_ date: Date) -> YumiWidgetData {
        var copy = self
        if let upcoming {
            let next = upcoming.first { $0.start > date }
            copy.nextEvent = next?.title
            copy.nextEventAt = next?.start
        }
        if let dueReminders {
            copy.reminders = dueReminders.map(\.title)
        }
        // What he said speaks of that moment: a few hours later, or another day, it is old news.
        // He then says only what the data still tells.
        let calendar = Calendar.current
        if !calendar.isDate(updatedAt, inSameDayAs: date) || date.timeIntervalSince(updatedAt) > 3 * 3600 {
            copy.nextEvent = copy.nextEventAt.map { calendar.isDate($0, inSameDayAs: date) ? copy.nextEvent : nil } ?? nil
            if copy.nextEvent == nil { copy.nextEventAt = nil }
            if let title = copy.nextEvent, let at = copy.nextEventAt {
                copy.remark = String(localized: "Ensuite : \(title) à \(at.formatted(date: .omitted, time: .shortened)).")
            } else {
                copy.remark = String(localized: "Je suis là.")
            }
        }
        return copy
    }

    static let group = "group.app.yumi"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    }

    private static var fileURL: URL? { folder?.appendingPathComponent("widget.json") }

    /// His picture for a mood: `yumi-happy.png`, `yumi-asking.png`...
    static func imageURL(_ name: String) -> URL? { folder?.appendingPathComponent("yumi-\(name).png") }

    static func load() -> YumiWidgetData? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(YumiWidgetData.self, from: data)
    }

    func save() {
        guard let url = Self.fileURL, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// What the widget shows before the app ever ran.
    static let placeholder = YumiWidgetData(remark: "Je suis là.", nextEvent: nil, nextEventAt: nil,
                                            reminders: [], mac: nil, macWaiting: nil, updatedAt: Date())
}

/// Yumi as the app drew him, or the plain badge when no picture is there yet.
struct YumiPicture: View {
    var name: String
    var size: CGFloat

    var body: some View {
        if let url = YumiWidgetData.imageURL(name), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable()
                // His own colours, even on a tinted or clear home screen
                .widgetAccentedRenderingMode(.fullColor)
                .scaledToFit().frame(width: size, height: size)
        } else {
            YumiBadge(size: size * 0.7).frame(width: size, height: size)
        }
    }
}

/// Yumi in the Dynamic Island and on the Lock Screen: the real character, drawn small by the app.
/// Each new expression comes in with a little bounce (a Live Activity animates only its changes).
struct YumiIslandPicture: View {
    var face: String
    var size: CGFloat

    var body: some View {
        Group {
            if let url = YumiWidgetData.imageURL("island-" + face), let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                YumiBadge(size: size * 0.8)
            }
        }
        .frame(width: size, height: size)
        .id(face)
        .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity),
                                removal: .opacity))
        .animation(.spring(response: 0.45, dampingFraction: 0.6), value: face)
    }
}
