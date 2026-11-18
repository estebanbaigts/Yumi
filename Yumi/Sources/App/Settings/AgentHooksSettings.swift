import SwiftUI

#if !APPSTORE
/// The hooks of another coding agent (Codex, Gemini CLI), in the same pane as Claude Code's and
/// with the same care: nothing is written before the person has read the change and confirmed
/// it, and the old file is copied beside it first. Not in the App Store build: its sandbox
/// cannot write in ~/.codex or ~/.gemini.
struct AgentHooksSection: View {
    let target: HookTarget
    @State private var found = false
    @State private var installed = false
    @State private var preview: String?
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("Hooks") {
                SettingsStatus(text: state.text, tone: state.tone)
            }
            HStack {
                Button(installed ? loc("Réinstaller") : loc("Installer"), action: prepare)
                    .disabled(!found)
                Button("Retirer", action: uninstall)
                    .disabled(!installed)
                Spacer()
            }
            if let message { SettingsHelp(message) }
            if let preview {
                ScrollView {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                HStack {
                    Spacer()
                    Button("Annuler", action: cancel)
                    Button("Écrire", action: confirm)
                        .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text(target.name)
        } footer: {
            SettingsHelp(footer)
        }
        .onAppear(perform: refresh)
    }

    private var state: (text: String, tone: SettingsStatus.Tone) {
        if !found { return (loc("Pas trouvé sur ce Mac"), .off) }
        return installed ? (loc("Installés"), .ok) : (loc("Pas installés"), .off)
    }

    private var footer: String {
        let file = loc("J'écris dans \(target.shownPath), après t'avoir montré le changement. Une copie de l'ancien fichier est gardée à côté.")
        switch target.id {
        case HookTarget.gemini.id:
            return file + " " + loc("Gemini CLI ne passe pas ses demandes d'accord par les hooks : je suis ses sessions, tu réponds dans le terminal.")
        case HookTarget.codex.id:
            return file + " " + loc("Au prochain lancement, Codex peut te demander d'approuver ces hooks.")
        default:
            return file
        }
    }

    private func refresh() {
        found = HookServer.agentFound(target)
        installed = HookServer.hooksInstalled(for: target)
    }

    private func prepare() {
        do {
            preview = try HookServer.shared.previewHooks(for: target)
            message = loc("Relis le changement avant de l'écrire.")
        } catch {
            preview = nil
            message = loc("Je n'ai pas pu lire \(target.shownPath) : \(error.localizedDescription)")
        }
    }

    private func cancel() {
        HookServer.shared.cancelHooks(for: target)
        preview = nil
        message = nil
    }

    private func confirm() {
        do {
            try HookServer.shared.writeHooks(for: target)
            preview = nil
            message = loc("C'est écrit. Relance \(target.name) pour que je voie ses sessions.")
            refresh()
        } catch {
            message = loc("L'écriture a échoué : \(error.localizedDescription)")
        }
    }

    private func uninstall() {
        do {
            try HookServer.shared.uninstallHooks(for: target)
            message = loc("Hooks retirés. L'ancien fichier est gardé à côté.")
            refresh()
        } catch {
            message = loc("Je n'ai pas pu les retirer : \(error.localizedDescription)")
        }
    }
}
#endif
