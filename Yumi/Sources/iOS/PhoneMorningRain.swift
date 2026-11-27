import Foundation
import UserNotifications

/// « Pluie vers 18:00 »: tomorrow at 7:30, when the forecast says it will rain during the day.
/// Planned on the iPhone from the forecast it already has; held down, the notification shows
/// Yumi under his cloud (`Sources/iOSNotify`). Nothing when it will not rain.
@MainActor
enum PhoneMorningRain {
    static let id = "yumi-morning-rain"

    static func plan(weather: WeatherState, place: String, now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard !StudioMode.isOn, case .ready(let report) = weather,
              await center.notificationSettings().authorizationStatus == .authorized,
              let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now),
              let rain = IslandClock.firstRain(on: tomorrow, hours: report.hours.map { ($0.time, $0.rainChance) }),
              let morning = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Yumi"
        content.subtitle = loc("Pluie vers") + " " + rain.formatted(date: .omitted, time: .shortened)
        content.body = place.isEmpty ? loc("Prends un parapluie.") : loc("Prends un parapluie.") + " · " + place
        content.categoryIdentifier = NotifyCategories.weather
        content.userInfo = ["ambiance": WeatherAmbiance.pluie.rawValue]
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: morning),
                                                    repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
