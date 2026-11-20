import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct YumiWidgets: WidgetBundle {
    var body: some Widget {
        YumiApprovalLiveActivity()
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
                    YumiPicture(name: context.state.answered == nil ? "asking" : "happy", size: 44)
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
                YumiPicture(name: context.state.answered == nil ? "asking" : "happy", size: 24)
            } compactTrailing: {
                Image(systemName: context.state.answered == nil ? "hand.raised.fill" : "checkmark")
                    .foregroundStyle(.orange)
            } minimal: {
                YumiPicture(name: "asking", size: 22)
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
                YumiPicture(name: state.answered == nil ? "asking" : "happy", size: 40)
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
