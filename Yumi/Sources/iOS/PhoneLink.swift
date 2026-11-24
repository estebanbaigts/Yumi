import ActivityKit
import Foundation
import LocalAuthentication
import Observation
import UIKit
import UserNotifications

/// The iPhone's side of the link with the Mac. Off unless the person turned it on.
///
/// What it can and cannot do, honestly:
/// - The Mac's picture arrives when the app is open, and in the background through a silent push
///   from CloudKit. iOS decides when (or whether) a silent push wakes the app: it may come late.
/// - A request then becomes a notification with « Autoriser » (Face ID or the code first) and
///   « Refuser », and a Live Activity with the same buttons. Without a server of ours there is no
///   push to update a Live Activity: it changes when the app runs, and goes stale at the deadline.
/// - An answer is only a proposal: the Mac checks it again (`LinkReplyCheck`) before acting.
@MainActor
@Observable
final class PhoneLink: NSObject {
    static let shared = PhoneLink()

    private(set) var mac: LinkSnapshot?
    private(set) var lastError: String?
    /// Requests answered from this iPhone, until the Mac's picture drops them: id → allowed.
    private(set) var answered: [String: Bool] = [:]
    @ObservationIgnored private var notified: Set<String> = []

    static let categoryID = "yumi.approval"
    static let allowID = "yumi.allow"
    static let denyID = "yumi.deny"

    /// Turning the link on: register for CloudKit's silent pushes, ask for notifications.
    func turnedOn() async {
        UIApplication.shared.registerForRemoteNotifications()
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        if let link = YumiLinks.current() as? CloudKitLink { try? await link.subscribe() }
        await refresh()
    }

    func turnedOff() {
        mac = nil
        Task { await Self.endActivities(keeping: []) }
    }

    /// Reads the Mac's picture. Called at launch, when the app comes back, and on a silent push.
    func refresh() async {
        let link = YumiLinks.current()
        guard await link.isAvailable() else {
            mac = nil
            return
        }
        do {
            let was = mac
            mac = try await link.latestSnapshot()
            lastError = nil
            if was == nil, let mac, Date().timeIntervalSince(mac.sentAt) < 180 { await connected(mac) }
        } catch {
            lastError = loc("Je n'arrive pas à joindre ton iCloud.")
            return
        }
        await show(mac?.approvals ?? [], from: mac)
    }

    /// The Mac just showed up: the link view celebrates, a notification says so, and the Mac is
    /// told the iPhone is there (a « hello » it shows on its island, never acted on).
    private(set) var connectedAt: Date?

    #if DEBUG
    /// `-YumiCelebrate YES`: the celebration at launch, to look at it.
    func celebrateForTesting() { connectedAt = Date() }
    #endif

    private func connected(_ mac: LinkSnapshot) async {
        let key = "phoneLinkGreeted"
        guard UserDefaults.standard.string(forKey: key) != mac.deviceName else { return }
        connectedAt = Date()
        UserDefaults.standard.set(mac.deviceName, forKey: key)
        await LinkAnswers.send(approvalID: LinkHello.id, fingerprint: UIDevice.current.name, allow: true)
        let content = UNMutableNotificationContent()
        content.title = loc("C'est bon, on est connectés")
        content.body = loc("Ton iPhone et \(mac.deviceName) se parlent maintenant, par ton iCloud.")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "yumi-linked", content: content, trigger: nil))
    }

    /// While the app is open, the Mac is looked at often: every 5 s until it shows, every 20 s after.
    func watch() async {
        while !Task.isCancelled {
            if LinkSetting.isOn(), UIApplication.shared.applicationState == .active { await refresh() }
            try? await Task.sleep(for: .seconds(mac == nil ? 5 : 20))
        }
    }

    /// For filming the video (design/video-beta.md): in 5 s, the same notification as a real request
    /// of the Mac, and its Live Activity. Nothing is sent anywhere.
    func demoNotification() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        let content = UNMutableNotificationContent()
        content.title = "Yumi"
        content.subtitle = loc("Claude Code veut pousser sur GitHub")
        content.body = loc("Touche pour décider")
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "yumi-demo", content: content, trigger: trigger))
    }

    /// Filming mode: the made-up request of the Mac on the Lock Screen and in the Dynamic Island.
    /// Nothing is sent anywhere: the link is `OffLink` while filming.
    func showStudio(_ mac: LinkSnapshot) {
        guard StudioMode.isOn, let approval = mac.approvals.first,
              Activity<YumiApprovalActivity>.activities.isEmpty else { return }
        startActivity(approval, source: "Claude Code · Yumi", device: mac.deviceName)
    }

    /// A tap in the app. « Autoriser » asks for Face ID (or the code) first, as from a
    /// notification; nothing is sent if that fails. The Mac still checks the answer.
    func answer(_ approval: LinkApproval, allow: Bool) async {
        // Filming: nothing is sent, so nothing to unlock
        if allow, !StudioMode.isOn {
            let context = LAContext()
            let ok = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                        localizedReason: loc("Autoriser la demande de ton Mac"))) ?? false
            guard ok else { return }
        }
        answered[approval.id] = allow
        guard !StudioMode.isOn else { return }
        await LinkAnswers.send(approvalID: approval.id, fingerprint: approval.fingerprint, allow: allow)
    }

    /// When the Mac's picture was sent: tells whether the Mac is there.
    var lastSeen: Date? { mac?.sentAt }

    // MARK: - Showing the requests

    private func show(_ approvals: [LinkApproval], from mac: LinkSnapshot?) async {
        let live = approvals.filter { $0.expiresAt > Date() }
        let source: (LinkApproval) -> String = { approval in
            guard let session = mac?.sessions.first(where: { $0.id == approval.sessionID }) else { return mac?.deviceName ?? "Mac" }
            return "\(session.agent) · \(session.project)"
        }
        for approval in live where !notified.contains(approval.id) {
            notified.insert(approval.id)
            await notify(approval, source: source(approval))
            startActivity(approval, source: source(approval), device: mac?.deviceName ?? "Mac")
        }
        // Answered or expired on the Mac: off the Lock Screen and out of the notifications
        let ids = Set(live.map(\.id))
        answered = answered.filter { ids.contains($0.key) }
        let gone = notified.subtracting(ids)
        if !gone.isEmpty {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: Array(gone))
            notified.subtract(gone)
        }
        await Self.endActivities(keeping: ids)
    }

    private func notify(_ approval: LinkApproval, source: String) async {
        let content = UNMutableNotificationContent()
        content.title = source
        content.body = approval.summary
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["approvalID": approval.id, "fingerprint": approval.fingerprint]
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: approval.id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func startActivity(_ approval: LinkApproval, source: String, device: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = YumiApprovalActivity.ContentState(approvalID: approval.id, fingerprint: approval.fingerprint,
                                                     summary: approval.summary, source: source,
                                                     expiresAt: approval.expiresAt, answered: nil)
        _ = try? Activity.request(attributes: YumiApprovalActivity(deviceName: device),
                                  content: ActivityContent(state: state, staleDate: approval.expiresAt))
    }

    private static func endActivities(keeping ids: Set<String>) async {
        for activity in Activity<YumiApprovalActivity>.activities where !ids.contains(activity.content.state.approvalID) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// The buttons of the notification. « Autoriser » needs the iPhone unlocked.
    static func registerCategories() {
        let allow = UNNotificationAction(identifier: allowID, title: loc("Autoriser"), options: [.authenticationRequired])
        let deny = UNNotificationAction(identifier: denyID, title: loc("Refuser"), options: [.destructive])
        let category = UNNotificationCategory(identifier: categoryID, actions: [allow, deny], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

/// Silent pushes from CloudKit, and the notification buttons.
final class PhoneAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PhoneLink.registerCategories()
        if LinkSetting.isOn(), !StudioMode.isOn { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult {
        await PhoneLink.shared.refresh()
        return .newData
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = info["approvalID"] as? String, let fingerprint = info["fingerprint"] as? String else { return }
        let action = response.actionIdentifier
        switch action {
        case PhoneLink.allowID: await LinkAnswers.send(approvalID: id, fingerprint: fingerprint, allow: true)
        case PhoneLink.denyID: await LinkAnswers.send(approvalID: id, fingerprint: fingerprint, allow: false)
        default: break // Opening the notification answers nothing
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
