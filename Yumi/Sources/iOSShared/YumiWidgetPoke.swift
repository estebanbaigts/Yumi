import AppIntents
import Foundation
import WidgetKit

/// A touch on Yumi in the widget. It runs in the widget's own process (no app opens): it notes
/// the time and asks iOS to draw the widget again, which then plays a short reaction, a few
/// faces in a row with a transition each (a widget cannot run a continuous animation).
struct YumiWidgetPoke: AppIntent {
    static let title: LocalizedStringResource = "Toucher Yumi"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        YumiWidgetPokes.record()
        WidgetCenter.shared.reloadTimelines(ofKind: "YumiToday")
        return .result()
    }
}

/// The touches, kept in the App Group shared with the app.
enum YumiWidgetPokes {
    private static var defaults: UserDefaults? { UserDefaults(suiteName: YumiWidgetData.group) }

    static func record(now: Date = Date()) {
        defaults?.set(now.timeIntervalSince1970, forKey: "widgetPokeAt")
        defaults?.set((defaults?.integer(forKey: "widgetPokes") ?? 0) + 1, forKey: "widgetPokes")
    }

    /// The last touch, when it was recent enough to still be reacting to it.
    static func recent(now: Date = Date()) -> (at: Date, count: Int)? {
        guard let seconds = defaults?.double(forKey: "widgetPokeAt"), seconds > 0 else { return nil }
        let at = Date(timeIntervalSince1970: seconds)
        guard now.timeIntervalSince(at) < 20 else { return nil }
        return (at, defaults?.integer(forKey: "widgetPokes") ?? 0)
    }

    /// His reaction, face after face: each touch picks one of a few short scenes.
    static func reaction(_ count: Int) -> [String] {
        let scenes = [["surprised", "happy", "wink", "calm"],
                      ["left", "right", "happy", "calm"],
                      ["surprised", "wink", "happy", "calm"]]
        return scenes[count % scenes.count]
    }
}
