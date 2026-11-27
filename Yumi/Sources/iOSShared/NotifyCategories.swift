import Foundation

/// The kinds of Yumi's notifications that open the animated view (`Sources/iOSNotify`), and the
/// shared place where the app leaves his look for it.
enum NotifyCategories {
    static let approval = "yumi.approval"
    static let weather = "yumi.weather"
    static let group = "group.app.yumi"
}
