import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct YumiWidgets: WidgetBundle {
    var body: some Widget {
        YumiApprovalLiveActivity()
        YumiDayLiveActivity()
        YumiTodayWidget()
        YumiAgentsWidget()
    }
}

/// A request of an agent on the Mac: on the Lock Screen and in the Dynamic Island. Opened, it is
/// Yumi surprised, who asks and what, then Refuser in red and Autoriser in green.
struct YumiApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: YumiApprovalActivity.self) { context in
            ApprovalBanner(state: context.state, device: context.attributes.deviceName)
                .padding(.horizontal, 16).padding(.vertical, 14)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ApprovalBanner(state: context.state, device: context.attributes.deviceName)
                }
            } compactLeading: {
                YumiIslandPicture(face: context.state.answered == nil ? "asking" : "happy", size: 24)
            } compactTrailing: {
                if context.state.answered == nil {
                    Text(timerInterval: Date()...max(Date(), context.state.expiresAt), countsDown: true, showsHours: false)
                        .monospacedDigit().font(.caption2.weight(.semibold)).foregroundStyle(WidgetInk.amber).frame(maxWidth: 40)
                } else {
                    Image(systemName: context.state.answered == "allow" ? "checkmark" : "xmark")
                        .foregroundStyle(context.state.answered == "allow" ? WidgetInk.allow : WidgetInk.refuse)
                }
            } minimal: {
                YumiIslandPicture(face: "asking", size: 22)
            }
        }
    }
}

private struct ApprovalBanner: View {
    let state: YumiApprovalActivity.ContentState
    let device: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                YumiIslandPicture(face: state.answered == nil ? "asking" : "happy", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.source.isEmpty ? device : state.source).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetInk.amber).lineLimit(1)
                    Text(state.summary).font(.system(size: 13, design: .monospaced)).foregroundStyle(WidgetInk.code).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            ApprovalButtons(state: state)
        }
    }
}

/// Never a single tap that both shows and answers: the person reads the request, then chooses.
private struct ApprovalButtons: View {
    let state: YumiApprovalActivity.ContentState

    var body: some View {
        if let answered = state.answered {
            Label(answered == "allow" ? String(localized: "Envoyé : autorisé") : String(localized: "Envoyé : refusé"),
                  systemImage: "paperplane.fill")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
        } else {
            HStack(spacing: 10) {
                Button(intent: LinkAnswerIntent(approvalID: state.approvalID, fingerprint: state.fingerprint, allow: false)) {
                    Text("Refuser").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(WidgetInk.refuse, in: Capsule())
                }
                Button(intent: LinkAnswerIntent(approvalID: state.approvalID, fingerprint: state.fingerprint, allow: true)) {
                    Text("Autoriser").font(.system(size: 15, weight: .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(WidgetInk.allow, in: Capsule())
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Yumi in the Dynamic Island: his face on the left, the next thing of the day on the right.
/// The compact form is his face and a short countdown; nothing more.
struct YumiDayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: YumiDayActivity.self) { context in
            DayBanner(state: context.state)
                .padding(16)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    DayBanner(state: context.state)
                }
            } compactLeading: {
                YumiIslandPicture(face: context.state.face, size: 24)
            } compactTrailing: {
                if let at = context.state.at, at > Date() {
                    Text(timerInterval: Date()...at, countsDown: true, showsHours: false)
                        .monospacedDigit().font(.caption2.weight(.bold)).foregroundStyle(WidgetInk.timer).frame(maxWidth: 44)
                } else {
                    Image(systemName: context.state.symbol)
                        .foregroundStyle(context.state.urgent ? WidgetInk.amber : WidgetInk.timer)
                }
            } minimal: {
                YumiIslandPicture(face: context.state.face, size: 22)
            }
        }
    }
}

/// « Ta journée »: Yumi, then the next thing and when.
private struct DayBanner: View {
    let state: YumiDayActivity.ContentState

    var body: some View {
        HStack(spacing: 10) {
            YumiIslandPicture(face: state.face, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.urgent ? state.detail : String(localized: "Ta journée"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.urgent ? WidgetInk.amber : WidgetInk.coral).lineLimit(1)
                (Text(state.at.map { $0.formatted(date: .omitted, time: .shortened) + " " } ?? "").bold()
                 + Text(state.title)
                 + Text(state.at.map { $0 > Date() ? " · " + widgetUntil($0, now: Date()) : "" } ?? ""))
                    .font(.system(size: 13.5)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
