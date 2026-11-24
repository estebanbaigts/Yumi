import SwiftUI

// MARK: - Finished (★ Proposition, `termine`)
//
// Which agent finished, on which model, in which repository and branch, and what it did; the
// terminal, all the agents; the island folds by itself a few seconds later.

struct FinishedPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    @State private var summary: String?
    private let green = Color(hex: "#3DDC97")

    var body: some View {
        let session = ClaudeTaskMirror.lastFinished
        let row = session.flatMap { id in
            state.modules.first { $0.id == IslandModel.agentModuleID }?.rows.first { $0.id == id.value }
        }
        let refused = session.flatMap { ClaudeTaskMirror.refusals[$0] }
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 24) {
                YumiSlot(width: 80)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(row?.agent ?? IslandAgent.name(state.focusTask)).font(IslandTheme.text(13, .bold))
                        let place = [row?.model, row?.place].compactMap { $0 }.joined(separator: " · ")
                        if !place.isEmpty || row?.branch != nil {
                            (Text(place) + Text(row?.branch.map { " ⎇ \($0)" } ?? "").font(.system(size: 12, design: .monospaced)))
                                .font(IslandTheme.text(12))
                                .foregroundStyle(Color(hex: "#8E8E93"))
                        }
                    }
                    Text(refused.map { loc("Tu as refusé : \($0). Voilà ce qu'il a fait ensuite.") }
                         ?? summary ?? loc("C'est passé."))
                        .font(.system(size: 24, weight: .bold))
                        .lineLimit(2)
                        .padding(.top, 6)
                    Text(IslandAgent.finishedLine(state, model))
                        .font(IslandTheme.text(12.5))
                        .foregroundStyle(Color(hex: "#B9BCC8"))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        if let session, ClaudeTaskMirror.openLabel(session: session.value) != nil {
                            pill(loc("Terminal"), filled: true) { _ = ClaudeTaskMirror.openSession(session.value) }
                        }
                        pill(loc("Tous les agents"), filled: false) { IslandActions.showModule(IslandModel.agentModuleID) }
                    }
                    .padding(.top, 12)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Text(loc("L'île se replie toute seule dans quelques secondes"))
                .font(IslandTheme.text(11))
                .foregroundStyle(Color(hex: "#8E8E93"))
        }
        .padding(.horizontal, 20)
        .frame(height: 190)
        // Nothing to answer: the summary is read, then the island folds by itself. Longer text,
        // longer stay; another view opened meanwhile is left alone.
        .task(id: session?.value) {
            summary = nil
            for _ in 0..<10 {
                if let text = session.flatMap({ ClaudeSessionJournals.shared.journals[$0.value]?.summary }) {
                    summary = text
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            let seconds = min(12, 6 + Double((summary ?? "").count) / 40)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, state.view == .finished else { return }
            IslandActions.fold()
        }
    }

    private func pill(_ label: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(IslandTheme.text(13, filled ? .semibold : .regular))
                .foregroundStyle(filled ? Color.black : .white)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(filled ? green : .clear))
                .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.3), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
