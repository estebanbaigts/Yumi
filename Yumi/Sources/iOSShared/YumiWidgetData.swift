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
