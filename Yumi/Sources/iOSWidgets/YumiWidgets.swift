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
    }
}

/// A request of an agent on the Mac: on the Lock Screen and in the Dynamic Island.
struct YumiApprovalLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: YumiApprovalActivity.self) { context in
            ApprovalBanner(state: context.state, device: context.attributes.deviceName)
                .padding(16)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    YumiIslandPicture(face: context.state.answered == nil ? "asking" : "happy", size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), context.state.expiresAt), countsDown: true)
                        .monospacedDigit().font(.caption).foregroundStyle(.secondary)
                        .frame(width: 44)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.source).font(.caption).foregroundStyle(.secondary)
                        Text(context.state.summary).font(.headline).lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ApprovalButtons(state: context.state)
                }
            } compactLeading: {
                YumiIslandPicture(face: context.state.answered == nil ? "asking" : "happy", size: 24)
            } compactTrailing: {
                Image(systemName: context.state.answered == nil ? "hand.raised.fill" : "checkmark")
                    .foregroundStyle(.orange)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                YumiIslandPicture(face: state.answered == nil ? "asking" : "happy", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(state.source) · \(device)").font(.caption).foregroundStyle(.white.opacity(0.7))
                    Text(state.summary).font(.headline).foregroundStyle(.white).lineLimit(2)
                }
                Spacer()
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
            HStack(spacing: 8) {
                Button(intent: LinkAnswerIntent(approvalID: state.approvalID, fingerprint: state.fingerprint, allow: false)) {
                    Text("Refuser").frame(maxWidth: .infinity)
                }
                .tint(.gray)
                Button(intent: LinkAnswerIntent(approvalID: state.approvalID, fingerprint: state.fingerprint, allow: true)) {
                    Text("Autoriser").frame(maxWidth: .infinity)
                }
                .tint(Color(red: 0.36, green: 0.55, blue: 1))
            }
            .buttonStyle(.borderedProminent)
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
                .activityBackgroundTint(Color(red: 0.08, green: 0.06, blue: 0.16))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    YumiIslandPicture(face: context.state.face, size: 48)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Label(context.state.detail, systemImage: context.state.symbol)
                            .font(.caption).foregroundStyle(context.state.urgent ? Color.orange : .secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let at = context.state.at, at > Date() {
                        Text(at, style: .relative).monospacedDigit().font(.caption)
                            .multilineTextAlignment(.trailing).frame(width: 64)
                    }
                }
            } compactLeading: {
                YumiIslandPicture(face: context.state.face, size: 24)
            } compactTrailing: {
                if let at = context.state.at, at > Date() {
                    Text(timerInterval: Date()...at, countsDown: true, showsHours: false)
                        .monospacedDigit().font(.caption2).frame(maxWidth: 44)
                } else {
                    Image(systemName: context.state.symbol)
                        .foregroundStyle(context.state.urgent ? Color.orange : Color(red: 0.62, green: 0.55, blue: 1))
                }
            } minimal: {
                YumiIslandPicture(face: context.state.face, size: 22)
            }
        }
    }
}

private struct DayBanner: View {
    let state: YumiDayActivity.ContentState

    var body: some View {
        HStack(spacing: 12) {
            YumiIslandPicture(face: state.face, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(2)
                Label(state.detail, systemImage: state.symbol).font(.subheadline)
                    .foregroundStyle(state.urgent ? Color.orange : .white.opacity(0.7)).lineLimit(1)
            }
            Spacer()
            if let at = state.at, at > Date() {
                Text(at, style: .relative).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.trailing)
            }
        }
    }
}
