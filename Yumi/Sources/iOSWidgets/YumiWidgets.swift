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
        YumiWeatherWidget()
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

/// Yumi in the Dynamic Island: his face on the left, the one thing that matters now on the right.
/// Every colour is one of his rims, chosen by the moment (calm, work, warn, joy, done, think).
struct YumiDayLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: YumiDayActivity.self) { context in
            DayBanner(state: context.state)
                .padding(16)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    YumiIslandPicture(face: state.face, size: 44).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    DayValue(state: state, size: 22).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    DayLines(state: state).padding(.horizontal, 4)
                }
            } compactLeading: {
                YumiIslandPicture(face: state.face, size: 26)
            } compactTrailing: {
                DayValue(state: state, size: 12).frame(maxWidth: 64)
            } minimal: {
                YumiIslandPicture(face: state.face, size: 22)
            }
        }
    }
}

/// The colour of a moment: the middle tone of Yumi's rim for it.
enum DayAccent {
    static func color(_ accent: String) -> Color {
        switch accent {
        case "work": WidgetInk.hex(0x7FD0FF)
        case "warn": WidgetInk.hex(0xFFB547)
        case "joy": WidgetInk.hex(0xF58AD9)
        case "done": WidgetInk.hex(0x3DDC97)
        case "think": WidgetInk.hex(0xC9A8FF)
        default: WidgetInk.hex(0x8B6CFF)
        }
    }
}

/// The short value: the time an agent works (stops by itself), the countdown, or a word.
private struct DayValue: View {
    let state: YumiDayActivity.ContentState
    let size: CGFloat

    var body: some View {
        Group {
            if let since = state.working {
                Text(timerInterval: IslandClock.workingRange(since: since), countsDown: false, showsHours: true)
            } else if let at = state.at, at > Date() {
                Text(timerInterval: Date()...at, countsDown: true, showsHours: true)
            } else if let value = state.value {
                Text(value)
            } else {
                Image(systemName: state.symbol)
            }
        }
        .monospacedDigit()
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(DayAccent.color(state.accent))
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
        // A new moment: the value rolls in, its colour slides to the new one (iOS animates
        // each update of an activity, never in between)
        .contentTransition(.numericText())
        .id(state.value ?? state.symbol)
        .transition(.push(from: .bottom))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: state)
    }
}

/// The coloured line, then the title and its detail.
private struct DayLines: View {
    let state: YumiDayActivity.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let kicker = state.kicker {
                Text(kicker).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DayAccent.color(state.accent)).lineLimit(1)
            }
            (Text(state.title).foregroundStyle(.white)
             + Text(state.detail.isEmpty ? "" : " · " + state.detail).foregroundStyle(WidgetInk.gray))
                .font(.system(size: 14)).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(state.title)
        .transition(.push(from: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: state)
    }
}

/// On the Lock Screen: Yumi, the lines, the value.
private struct DayBanner: View {
    let state: YumiDayActivity.ContentState

    var body: some View {
        HStack(spacing: 12) {
            YumiIslandPicture(face: state.face, size: 40)
            DayLines(state: state)
            DayValue(state: state, size: 18)
        }
    }
}
