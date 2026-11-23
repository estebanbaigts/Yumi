import SwiftUI

// MARK: - The chat (★ Proposition, `chat`)
//
// The conversations kept on the left, the one going on in the middle, the field at the bottom.

struct ChatPage: View {
    @ObservedObject var state: AppState
    @ObservedObject private var archive = ChatArchiveStore.shared
    @ObservedObject private var voice = IslandVoice.shared

    var body: some View {
        if voice.active {
            VoicePage(state: state).transition(.opacity)
        } else {
            conversation
        }
    }

    private var conversation: some View {
        HStack(alignment: .top, spacing: 18) {
            history
                .frame(width: 150, alignment: .topLeading)
                .padding(.trailing, 12)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
            IslandTalkView(state: state)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .frame(height: IslandHome.height, alignment: .top)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(loc("Historique").uppercased())
                .font(IslandTheme.text(10.5, .bold)).tracking(0.8)
                .foregroundStyle(Color(hex: "#8E8E93"))
                .padding(.bottom, 6)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    if !state.chatHistory.isEmpty {
                        item(title: state.chatHistory.first { $0.role == .user }?.content ?? loc("Cette conversation"),
                             date: loc("maintenant"), on: true) {}
                    }
                    ForEach(archive.chats.prefix(12)) { chat in
                        item(title: chat.title, date: Self.when(chat.date), on: false) {
                            withAnimation(.islandSpring(0.4)) { IslandActions.resume(chat) }
                        }
                    }
                }
            }
            Button {
                withAnimation(.islandSpring(0.4)) { IslandActions.newConversation() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text(loc("Nouvelle")).font(IslandTheme.text(11.5, .medium))
                }
                .foregroundStyle(Color(hex: "#B9A8FF"))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }

    private func item(title: String, date: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(IslandTheme.text(12, on ? .semibold : .medium)).lineLimit(1)
                Text(date).font(IslandTheme.text(10.5)).foregroundStyle(Color(hex: "#8E8E93"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Color(hex: "#8B6CFF").opacity(0.2) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "10:12" today, "hier", then the day's short name or date.
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return loc("hier") }
        if now.timeIntervalSince(date) < 6 * 86400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
