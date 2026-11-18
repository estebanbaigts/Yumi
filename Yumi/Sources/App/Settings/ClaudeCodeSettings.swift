import SwiftUI
import AppKit

/// Claude Code: the hooks that let Yumi see the sessions, and what they need. Nothing is
/// written in ~/.claude/settings.json before the person has read the change and confirmed it.
struct ClaudeCodeSettings: View {
    @State private var python = HookLauncher.pythonAvailable()
    @State private var installed = HookServer.hooksInstalled()
    @State private var outdated = HookServer.hooksNeedUpdate()
    @State private var preview: String?
    @State private var message: String?
    /// Off until the person turns it on: see `AgentRules`.
    @AppStorage(AgentRules.harmlessKey) private var letHarmlessThrough = false
    #if APPSTORE
    @State private var folderGranted = UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    private static let bookmarkKey = "claudeDirectoryBookmark"
    #endif

    var body: some View {
        Form {
            Section {
                LabeledContent("python3") {
                    HStack {
                        SettingsStatus(text: python ? loc("Présent") : loc("Absent"), tone: python ? .ok : .warning)
                        if !python {
                            Button("Installer") { installTools() }
                        }
                    }
                }
                LabeledContent("Hooks") {
                    SettingsStatus(text: hookState.text, tone: hookState.tone)
                }
                #if APPSTORE
                LabeledContent("Dossier .claude") {
                    HStack {
                        SettingsStatus(text: folderGranted ? loc("Accès donné") : loc("Pas d'accès"), tone: folderGranted ? .ok : .off)
                        Button(folderGranted ? "Changer…" : "Choisir…") { chooseFolder() }
                    }
                }
                #endif
            } header: {
                Text("État")
            } footer: {
                SettingsHelp(python
                             ? loc("Les hooks me disent ce que font tes sessions Claude Code. Claude Code marche pareil sans eux, je ne vois juste rien.")
                             : loc("Sans python3, je ne vois pas tes sessions (Claude Code marche normalement). « Installer » ouvre l'installation des outils de ligne de commande d'Apple."))
            }

            Section {
                HStack {
                    Button(installed ? (outdated ? loc("Mettre à jour") : loc("Réinstaller")) : loc("Installer"), action: prepare)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canWrite)
                    Button("Retirer", action: uninstall)
                        .disabled(!installed || !canWrite)
                    Spacer()
                }
                #if !APPSTORE
                LabeledContent("Script") {
                    Text(HookServer.hookScriptPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                #endif
                if let message { SettingsHelp(message) }
            } header: {
                Text("Hooks")
            } footer: {
                SettingsHelp(loc("J'écris dans ~/.claude/settings.json, après t'avoir montré le changement. Une copie de l'ancien fichier est gardée à côté."))
            }

            if let preview {
                Section("Ce que je vais écrire") {
                    ScrollView {
                        Text(preview)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 180)
                    HStack {
                        Spacer()
                        Button("Annuler") { self.preview = nil; message = nil }
                            .keyboardShortcut(.cancelAction)
                        Button("Écrire", action: confirm)
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }

            Section {
                Toggle(loc("Laisser passer tout seul ce qui ne change rien"), isOn: $letHarmlessThrough)
            } header: {
                Text("Demandes d'accord")
            } footer: {
                SettingsHelp(loc("Lire des fichiers, regarder git et lancer les tests passent sans ton clic, et la session le note. Supprimer, pousser, installer, contacter internet ou agir en administrateur attend toujours ta réponse."))
            }

            #if !APPSTORE
            // The other coding agents, through the same hooks.
            AgentHooksSection(target: .codex)
            AgentHooksSection(target: .gemini)
            #endif
        }
    }

    private var hookState: (text: String, tone: SettingsStatus.Tone) {
        if outdated { return (loc("À mettre à jour"), .warning) }
        return installed ? (loc("Installés"), .ok) : (loc("Pas installés"), .off)
    }

    private var canWrite: Bool {
        #if APPSTORE
        folderGranted
        #else
        true
        #endif
    }

    private func refresh() {
        installed = HookServer.hooksInstalled()
        outdated = HookServer.hooksNeedUpdate()
        python = HookLauncher.pythonAvailable()
    }

    private func legacyNote() -> String? {
        let legacy = HookServer.shared.pendingLegacyHookCount
        guard legacy > 0 else { return nil }
        return legacy == 1 ? loc("Ça retire aussi un ancien hook d'une autre app.") : loc("Ça retire aussi \(legacy) anciens hooks d'une autre app.")
    }

    private func installTools() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        try? process.run()
        message = loc("L'installation d'Apple s'ouvre. Reviens ici quand elle est finie.")
    }

    #if APPSTORE
    private func folder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale), !stale else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            folderGranted = false
            message = loc("J'ai perdu l'accès au dossier .claude. Choisis-le à nouveau.")
            return nil
        }
        return url
    }

    private func withFolder(_ work: (URL) throws -> Void) rethrows {
        guard let url = folder() else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try work(url)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.message = loc("Choisis ton dossier .claude pour que \(AppIdentity.productName) y ajoute ses hooks")
        panel.prompt = "Choisir"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            folderGranted = true
            message = nil
        } catch {
            message = loc("Je n'ai pas pu garder l'accès : \(error.localizedDescription)")
        }
    }
    #endif

    private func prepare() {
        do {
            #if APPSTORE
            try withFolder { preview = try HookServer.shared.previewClaudeHooksAppStore(claudeURL: $0) }
            #else
            preview = try HookServer.shared.previewClaudeHooks()
            #endif
            message = [loc("Relis le changement avant de l'écrire."), legacyNote()].compactMap { $0 }.joined(separator: " ")
        } catch {
            message = loc("Je n'ai pas pu lire les réglages de Claude Code : \(error.localizedDescription)")
        }
    }

    private func confirm() {
        do {
            #if APPSTORE
            try withFolder { try HookServer.shared.writeClaudeHooksAppStore(claudeURL: $0) }
            #else
            try HookServer.shared.writeClaudeHooks()
            #endif
            preview = nil
            message = loc("C'est écrit. Relance tes sessions Claude Code pour que je les voie.")
            refresh()
        } catch {
            message = loc("L'écriture a échoué : \(error.localizedDescription)")
        }
    }

    private func uninstall() {
        do {
            #if APPSTORE
            try withFolder { try HookServer.shared.uninstallClaudeHooksAppStore(claudeURL: $0) }
            #else
            try HookServer.shared.uninstallClaudeHooks()
            #endif
            message = loc("Hooks retirés.")
            refresh()
        } catch {
            message = loc("Je n'ai pas pu les retirer : \(error.localizedDescription)")
        }
    }
}
