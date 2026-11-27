import SwiftUI
import UIKit
import UserNotifications
import UserNotificationsUI

/// A notification of Yumi held down: the real Yumi, animated by the same engine as the app (a
/// notification's expanded view runs like an app, unlike a widget). The buttons stay iOS's own.
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var host: UIHostingController<NotifyYumiView>?

    func didReceive(_ notification: UNNotification) {
        let content = notification.request.content
        let view = NotifyYumiView(moment: NotifyMoment(category: content.categoryIdentifier, userInfo: content.userInfo),
                                  title: content.title, subtitle: content.subtitle, text: content.body)
        if let host {
            host.rootView = view
        } else {
            let host = UIHostingController(rootView: view)
            host.view.backgroundColor = .clear
            addChild(host)
            host.view.frame = self.view.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            self.view.addSubview(host.view)
            host.didMove(toParent: self)
            self.host = host
        }
        preferredContentSize = CGSize(width: self.view.bounds.width, height: 250)
    }
}

/// What the notification is about, and so what Yumi does.
enum NotifyMoment {
    case approval
    case weather(WeatherAmbiance?)
    case other

    init(category: String, userInfo: [AnyHashable: Any]) {
        switch category {
        case NotifyCategories.approval: self = .approval
        case NotifyCategories.weather:
            self = .weather((userInfo["ambiance"] as? String).flatMap(WeatherAmbiance.init(rawValue:)))
        default: self = .other
        }
    }

    var accent: Color {
        switch self {
        case .approval: Color(red: 1, green: 0.71, blue: 0.28)
        case .weather: Color(red: 0.36, green: 0.55, blue: 1)
        case .other: Color(red: 0.55, green: 0.42, blue: 1)
        }
    }
}

struct NotifyYumiView: View {
    let moment: NotifyMoment
    let title: String
    let subtitle: String
    let text: String
    @StateObject private var engine = BotEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if case .weather(let ambiance?) = moment {
                    WeatherEffects(ambiance: ambiance)
                } else {
                    RadialGradient(colors: [Color(white: 0.12), .black], center: .bottom, startRadius: 0, endRadius: 220)
                }
                YumiStage(engine: engine, particleOverhang: 30, followsPointer: false)
                    .frame(width: 120, height: 120)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(subtitle.isEmpty ? title : subtitle)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(moment.accent).lineLimit(1)
            Text(text).font(.system(size: 15)).foregroundStyle(.white).lineLimit(2)
        }
        .padding(14)
        .background(Color.black)
        .onAppear(perform: start)
    }

    private func start() {
        let shared = UserDefaults(suiteName: NotifyCategories.group) ?? .standard
        let costume = YumiCostume.current(in: shared)
        switch moment {
        case .approval:
            engine.setLook(accent: .current(in: shared), costume: costume)
            engine.setState(.approval, force: true)
            engine.setMood(.curious)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { engine.play(.wave) }
        case .weather(let ambiance):
            engine.setLook(accent: .current(in: shared),
                           costume: ambiance?.wearsBeanie == true && costume == .none ? .beanie : costume)
            engine.setState(.idle, force: true)
            engine.setHabit(ambiance?.habit)
            engine.setMood(ambiance?.mood)
        case .other:
            engine.setLook(accent: .current(in: shared), costume: costume)
            engine.setState(.idle, force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { engine.play(.pop) }
        }
    }
}
