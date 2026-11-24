import SwiftUI

// MARK: - The file dropped (★ Proposition, `fichier`)
//
// Yumi, happy, with the file under him; « J'en fais quoi ? », four choices and a free field.

struct DropPage: View {
    @ObservedObject var state: AppState
    @State private var text = ""
    @State private var handed: ClaudeCodeModule.HandOff?
    @FocusState private var focused: Bool
    private let green = Color(hex: "#3DDC97")

    private var file: DroppedFile? { state.view == .upload ? nil : state.droppedFile }

    var body: some View {
        Group {
            if let file { dropped(file) } else { waiting }
        }
        .padding(.horizontal, 24)
        .frame(height: IslandHome.height)
    }

    private func dropped(_ file: DroppedFile) -> some View {
        HStack(spacing: 26) {
            VStack(spacing: 8) {
                YumiSlot(width: 80)
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill").foregroundStyle(green)
                    Text(file.name).lineLimit(1)
                }
                .font(IslandTheme.text(12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))
                .frame(maxWidth: 150)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(loc("J'en fais quoi ?")).font(.system(size: 19, weight: .semibold))
                if let handed {
                    Text(handed == .typed ? loc("C'est dans la session. Ajoute ta consigne et valide.")
                                          : loc("Chemin copié. Colle-le dans la session avec ⌘V."))
                        .font(IslandTheme.text(12)).foregroundStyle(green).padding(.top, 4)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    choice(loc("Le résumer"), Color(hex: "#8B6CFF")) { IslandActions.summarize() }
                    choice(loc("Poser une question"), Color(hex: "#7FD8FF")) { IslandActions.talk() }
                    if let target = ClaudeTaskMirror.fileTarget {
                        choice(loc("Le donner à \(agent)"), Color(hex: "#5B8CFF")) {
                            Task {
                                handed = await ClaudeCodeModule.hand(file.url, to: target)
                                if handed != nil { SoundEngine.shared.play("send"); IslandModel.shared.pose(.pop) }
                            }
                        }
                    } else {
                        choice(loc("L'envoyer par mail"), Color(hex: "#6FB4FF")) { IslandActions.sendByMail() }
                    }
                    choice(loc("Le ranger"), green) { IslandActions.putAway() }
                }
                .padding(.top, 12)
                HStack(spacing: 6) {
                    TextField("", text: $text, prompt: Text(loc("Ou dis-moi ce que tu veux en faire…")).foregroundStyle(Color(hex: "#8E8E93")))
                        .textFieldStyle(.plain)
                        .font(IslandTheme.text(13))
                        .focused($focused)
                        .onSubmit(send)
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 30, height: 30).background(Circle().fill(green)).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc("Envoyer"))
                }
                .padding(.leading, 14)
                .padding(.trailing, 5)
                .frame(height: 38)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(green.opacity(0.47), lineWidth: 1.4))
                .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: file.name) { handed = nil }
    }

    /// "Claude Code", "Codex": the agent of the session the file can go to.
    private var agent: String {
        state.tasks.first(where: { $0.id == ClaudeTaskMirror.taskID })?.name ?? loc("Claude Code")
    }

    private func choice(_ label: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(IslandTheme.text(12.5, .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.11)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.33)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func send() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = ""
        IslandActions.send(query)
    }

    /// Opened by « Déposer » before any file: where to drop it.
    private var waiting: some View {
        VStack(spacing: 10) {
            YumiSlot(width: 70)
            Text(loc("Lâche le fichier sur Yumi")).font(IslandTheme.text(15, .semibold))
            Text(loc("Je le résume, je réponds à tes questions dessus ou je le range."))
                .font(IslandTheme.text(12)).foregroundStyle(Color(hex: "#8E8E93"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(green.opacity(state.fileDragOver ? 0.7 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
        .padding(.vertical, 6)
    }
}
