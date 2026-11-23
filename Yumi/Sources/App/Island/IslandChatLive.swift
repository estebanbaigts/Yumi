import SwiftUI

// The answer while it is being made (Contracts/ChatLive.swift): the actions already done,
// small, above; the answer whose text grows, with a cursor; and under it the action under
// way, with what it is writing or printing.

struct ChatLiveView: View {
    let live: ChatLive
    /// false once the answer is complete and only waits for its place in the history:
    /// the cursor and the running action are gone, the text stays where it is.
    var running = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !live.done.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(live.done) { ChatDoneRow(activity: $0) }
                }
                .padding(.leading, 4)
            }

            if !live.text.isEmpty || live.activity == nil {
                ChatLine(text: live.text, cursor: running)
            }

            if running, let activity = live.activity {
                ChatActivityRow(activity: activity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One line of the conversation: what the user said in a bubble on the right (`.me`), what
/// Yumi answers as plain text (`.ans`). The same view draws the live answer and the final
/// one, so that one becomes the other without anything moving.
struct ChatLine: View {
    let text: String
    var mine = false
    var cursor = false

    var body: some View {
        if mine {
            HStack(spacing: 0) {
                Spacer(minLength: 24)
                Text(text)
                    .font(IslandTheme.text(12.5, .medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16, style: .continuous)
                        .fill(Color(hex: "#8B6CFF")))
            }
        } else {
            HStack(spacing: 0) {
                (Text(text) + Text(cursor ? (text.isEmpty ? "▍" : " ▍") : "").foregroundStyle(IslandTheme.violet))
                    .font(IslandTheme.text(12.5, .regular))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08)))
                Spacer(minLength: 24)
            }
        }
    }
}

extension ChatActivity.Kind {
    var symbol: String {
        switch self {
        case .thinking:  return "sparkles"
        case .reading:   return "doc.text"
        case .writing:   return "square.and.pencil"
        case .editing:   return "pencil"
        case .running:   return "terminal"
        case .searching: return "magnifyingglass"
        case .waiting:   return "hourglass"
        }
    }

    var changesSomething: Bool { LiveChat.changes.contains(rawValue) }
}

/// An action already finished: ticked, or struck through when it failed.
private struct ChatDoneRow: View {
    let activity: ChatActivity

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: activity.succeeded ? "checkmark" : "xmark")
                .font(.system(size: 7.5, weight: .heavy))
                .foregroundStyle(activity.succeeded ? IslandTheme.green : IslandTheme.red)
                .frame(width: 10)
            Text(activity.label)
                .font(IslandTheme.round(10, .semibold))
                .strikethrough(!activity.succeeded)
                .foregroundStyle(IslandTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// The action under way: its icon, its label, a sign that it is running, and what it shows.
private struct ChatActivityRow: View {
    let activity: ChatActivity
    @State private var detailHeight: CGFloat = 0

    /// About four lines of 10.5 pt monospaced text.
    private let detailLimit: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: activity.kind.symbol)
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(IslandTheme.violet)
                    .frame(width: 14)
                Text(activity.label)
                    .font(IslandTheme.round(11, .bold))
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ChatSpinner()
            }
            .padding(.leading, 4)

            if let detail = activity.detail, !detail.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(detail)
                        .font(IslandTheme.mono(10.5))
                        .foregroundStyle(IslandTheme.code)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { detailHeight = $0 }
                }
                // It grows downwards and keeps its last lines in view
                .defaultScrollAnchor(.bottom)
                .frame(height: min(max(detailHeight, 1), detailLimit))
                .background(RoundedRectangle(cornerRadius: 9).fill(IslandTheme.surface))
                .clipShape(RoundedRectangle(cornerRadius: 9))
            }
        }
    }
}

/// A small arc that turns.
private struct ChatSpinner: View {
    @Environment(\.islandLayerShown) private var shown

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shown)) { timeline in
            let turn = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(IslandTheme.muted, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(turn * 360))
                .frame(width: 9, height: 9)
        }
    }
}
