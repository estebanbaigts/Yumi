#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only. Launch with `YUMI_ISLAND_SHOTS=<folder>` to walk the island through
/// the launch and its eight views with example content, and save a PNG of the panel at each
/// step, to be compared with design/yumi/maquette/reference.html.
/// `YUMI_ISLAND_VIEW=<home|working|alert|finished|error|module|talk|drop|compact|folded-music|chat-live>` instead
/// opens the island on one view and leaves it there.
@MainActor
enum IslandDemo {
    private static var started = false

    static func startIfRequested(controller: IslandWindowController) {
        let env = ProcessInfo.processInfo.environment
        if let folder = env["YUMI_SETTINGS_SHOTS"] {
            Task { await settingsShots(into: folder) }
            return
        }
        guard !started, env["YUMI_ISLAND_SHOTS"] != nil || env["YUMI_ISLAND_VIEW"] != nil || env["YUMI_ISLAND_ASK"] != nil || env["YUMI_ISLAND_ACTION"] != nil else { return }
        started = true
        // Nothing folds the island while it is being looked at
        controller.holdsOpen = true
        controller.fsm.homeToPetitDelay = 3600
        controller.fsm.petitToHiddenDelay = 3600
        Task { @MainActor in
            if env["YUMI_ISLAND_SHOTS"] != nil, env["YUMI_ISLAND_VIEW"] == "live" {
                // The folded island as it really is (a track playing, an event coming up)
                await pause(Double(env["YUMI_ISLAND_WAIT"] ?? "") ?? 7)
                shot(controller, "5-live-a")
                controller.demoHover = true
                await pause(1); shot(controller, "5-live-hover")
                controller.demoHover = false
                await pause(1); shot(controller, "5-live-b")
                NSApp.terminate(nil)
            } else if let action = env["YUMI_ISLAND_ACTION"] {
                // "music:primary": the same notification as a module button, after a wait
                await pause(Double(env["YUMI_ISLAND_WAIT"] ?? "") ?? 8)
                let parts = action.split(separator: ":").map(String.init)
                let live = AppState.shared.modules.map { "\($0.id)=\($0.live?.text ?? "-")" }.joined(separator: ", ")
                print("YUMI modules: \(live)")
                if parts.count == 2 { IslandActions.liveControl(parts[0], parts[1]) }
                await pause(Double(env["YUMI_ISLAND_AFTER"] ?? "") ?? 4)
                NSApp.terminate(nil)
            } else if let question = env["YUMI_ISLAND_ASK"] {
                // A real request, through the chat service, with a picture every half second
                await pause(6.2)
                controller.expand(to: .prompt)
                await pause(0.8)
                IslandActions.send(question)
                for i in 0..<(Int(env["YUMI_ISLAND_WAIT"] ?? "") ?? 60) {
                    await pause(0.5)
                    shot(controller, String(format: "7-ask-%03d", i))
                }
                NSApp.terminate(nil)
            } else if env["YUMI_ISLAND_VIEW"] == "chat-live" {
                await pause(6.2)
                if env["YUMI_ISLAND_SHOTS"] != nil {
                    await walkChat(controller, shots: true)
                    NSApp.terminate(nil)
                } else {
                    // Again and again, to be watched
                    while true { await walkChat(controller, shots: false); await pause(3) }
                }
            } else if let name = env["YUMI_ISLAND_VIEW"] {
                await pause(6.2)
                show(name, controller)
            } else {
                await walk(controller)
            }
        }
    }

    /// `YUMI_SETTINGS_SHOTS=<folder>`: every page of the settings window, light then dark,
    /// saved as PNG, then the app quits.
    private static func settingsShots(into folder: String) async {
        await pause(2)
        let developer = UserDefaults.standard.bool(forKey: SettingsPage.developerKey)
        UserDefaults.standard.set(true, forKey: SettingsPage.developerKey)
        defer { UserDefaults.standard.set(developer, forKey: SettingsPage.developerKey) }
        for dark in [false, true] {
            for page in SettingsPage.allCases {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 600),
                                      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Réglages de \(AppIdentity.productName)"
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = NSHostingView(rootView: SettingsView(page: page))
                window.setContentSize(NSSize(width: 760, height: 600))
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                await pause(1.5)
                // The shell takes the picture of this window (screencapture -l), then removes the file
                let name = "\(SettingsPage.allCases.firstIndex(of: page)!)-\(page.rawValue)-\(dark ? "sombre" : "clair")"
                let ready = URL(fileURLWithPath: "\(folder)/ready")
                try? "\(window.windowNumber) \(name)".write(to: ready, atomically: true, encoding: .utf8)
                while FileManager.default.fileExists(atPath: ready.path) { await pause(0.2) }
                window.close()
            }
        }
        NSApp.terminate(nil)
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static func walk(_ controller: IslandWindowController) async {
        // The launch: one picture every 250 ms
        for i in 0..<22 {
            await pause(0.25)
            shot(controller, String(format: "0-launch-%02d", i))
        }
        await pause(0.6)
        shot(controller, "1-compact")
        for name in ["home", "module", "working", "alert", "finished", "error", "music", "focus", "weather", "talk", "settings", "welcome", "memory", "memory-empty", "drop", "file",
                     "remark-short", "remark-long", "remark-action", "remark-open", "remark-none",
                     "github", "github-pr"] {
            show(name, controller)
            await pause(0.45); shot(controller, "2-\(name)-a")
            await pause(2.2);  shot(controller, "2-\(name)-b")
        }
        show("compact", controller)
        await pause(1.2); shot(controller, "3-compact-working")
        await walkFolded(controller)
        await walkChat(controller, shots: true)
        // The goodbye: one picture every 250 ms
        controller.quitRequested()
        for i in 0..<19 {
            await pause(0.25)
            shot(controller, String(format: "8-bye-%02d", i))
        }
        NSApp.terminate(nil)
    }

    /// The folded island with something live: the two examples of the contract (music and
    /// agenda), the buttons on hover, the next track sliding in, a title too long, then
    /// the agenda alone and nothing at all.
    private static func walkFolded(_ controller: IslandWindowController) async {
        for name in ["folded-music", "folded-hover", "folded-next", "folded-long", "folded-agenda", "folded-none"] {
            show(name, controller)
            await pause(0.12); shot(controller, "4-\(name)-a")
            await pause(0.2);  shot(controller, "4-\(name)-b")
            await pause(1.4);  shot(controller, "4-\(name)-c")
        }
        controller.demoHover = false
    }

    /// An answer made live, without the core: the text writes itself, a file is written with
    /// its preview, a command fails, then the answer lands in the history.
    private static func walkChat(_ controller: IslandWindowController, shots: Bool) async {
        let state = AppState.shared
        func snap(_ name: String) { if shots { shot(controller, "6-chat-\(name)") } }
        func type(_ words: String, into live: inout ChatLive) async {
            for word in words.split(separator: " ") {
                live.text += (live.text.isEmpty ? "" : " ") + word
                state.chatLive = live
                await pause(0.07)
            }
        }
        state.chatLive = nil
        state.stateOverride = .thinking
        state.chatHistory = [ChatMessage(role: .user, content: "Écris-moi un petit script qui dit bonjour, et lance-le")]
        controller.expand(to: .prompt)
        await pause(0.9); snap("0-waiting")

        var live = ChatLive()
        state.chatLive = live
        await type("Je te prépare ça. Je crée le script dans Téléchargements, puis je le lance pour vérifier.", into: &live)
        snap("1-text")

        let lines = ["#!/bin/zsh", "# bonjour.sh", "nom=${1:-toi}", "echo \"Bonjour, $nom !\"", "date \"+Il est %H:%M.\"", "exit 0"]
        live.activity = ChatActivity(id: "w1", kind: .writing, label: "Écrit bonjour.sh", detail: "")
        for index in lines.indices {
            live.activity?.detail = lines[0...index].joined(separator: "\n")
            state.chatLive = live
            await pause(0.3)
            if index == 2 { snap("2-writing") }
        }
        snap("3-written")
        live.done.append(ChatActivity(id: "w1", kind: .writing, label: "Écrit bonjour.sh"))
        live.activity = ChatActivity(id: "r1", kind: .running, label: "Lance zsh bonjour.sh", detail: "Bonjour, toi !\nIl est 16:42.")
        state.chatLive = live
        await pause(1.0); snap("4-running")
        live.done.append(ChatActivity(id: "r1", kind: .running, label: "Lance zsh bonjour.sh"))
        live.activity = ChatActivity(id: "r2", kind: .running, label: "Lance chmod +x bonjour.sh")
        state.chatLive = live
        await pause(0.7)
        live.done.append(ChatActivity(id: "r2", kind: .running, label: "Lance chmod +x bonjour.sh", succeeded: false))
        live.activity = nil
        state.chatLive = live
        await type("C'est fait : bonjour.sh est dans Téléchargements et il répond bien.", into: &live)
        snap("5-ending")

        // The core ends the answer, then files it in the history
        state.chatLive = nil
        state.stateOverride = nil
        snap("6-ended")
        await pause(0.05)
        state.chatHistory.append(ChatMessage(role: .assistant, content: live.text))
        await pause(0.05); snap("7-final")
        await pause(1.2);  snap("8-settled")
    }

    /// Example mails from two accounts of Apple's Mail.
    private static var sampleMails: [GmailMail] {
        let now = Date.now
        func mail(_ id: String, _ account: String, _ from: String, _ subject: String, minutes: Double,
                  unread: Bool, important: Bool = false) -> GmailMail {
            var mail = GmailMail(uid: MailAppParse.stableID(id), from: from, subject: subject,
                                 date: now.addingTimeInterval(-minutes * 60), unread: unread, thread: nil)
            mail.account = account
            mail.important = important
            mail.source = .mailApp
            mail.messageID = id
            mail.replyAddress = "contact@example.com"
            return mail
        }
        return [
            mail("1", "Pro", "Camille Durand", "Urgent : contrat à signer avant vendredi", minutes: 12, unread: true, important: true),
            mail("2", "iCloud", "Léa Martin", "Dîner samedi ?", minutes: 40, unread: true),
            mail("3", "Pro", "Paul Moreau", "Compte rendu de la réunion produit", minutes: 95, unread: false, important: true),
            mail("4", "iCloud", "Apple", "Ton reçu", minutes: 180, unread: false),
            mail("5", "Pro", "Notion", "Mises à jour de la semaine", minutes: 300, unread: false),
        ]
    }

    /// What Yumi could remember, of each kind.
    private static var memories: [MemoryEntry] {
        let now = Date.now
        func entry(_ id: String, _ kind: MemoryEntry.Kind, _ text: String, hours: Double) -> MemoryEntry {
            MemoryEntry(id: id, kind: kind, text: text, date: now.addingTimeInterval(-hours * 3600))
        }
        return [
            entry("p1", .person, "Tu préfères les réponses courtes, sans listes.", hours: 30),
            entry("p2", .person, "Tu travailles surtout le soir.", hours: 2),
            entry("j1", .project, "Yumi : un compagnon dans la notch du Mac, en Swift.", hours: 5),
            entry("j2", .project, "Audioscope : mis de côté pour l'instant.", hours: 50),
            entry("t1", .thread, "Tu m'as demandé un script qui dit bonjour ; il est dans Téléchargements.", hours: 1),
            entry("t2", .thread, "Le bouton Précédent de la musique attend une décision.", hours: 3),
        ]
    }

    /// The examples of the contract, with another text for the music, and the fields of the
    /// activity interface filled in as the core will.
    private static func examples(music: String?, agenda: Bool = true, pullRequest: Bool = false) -> [ModuleSnapshot] {
        var github = ModuleSnapshot(id: "github", name: "GitHub", colorHex: "#C9CCDA", status: "128 · 12 · 3",
                                    title: "Une étoile de plus, de la part de louis.", subtitle: "estebanbaigts/Yumi",
                                    primaryAction: "Ouvrir", secondaryAction: nil)
        if pullRequest {
            github.needsAttention = true
            github.title = "Une pull request t'attend : le repli de l'île."
            github.primaryAction = "Relire"
        }
        let now = Date.now
        github.rows = [
            ModuleRow(id: "p1", title: "Le repli de l'île", detail: "#14 · lea", state: .waiting, label: "ta review",
                      date: now.addingTimeInterval(-600), section: "estebanbaigts/Yumi", action: "https://github.com"),
            ModuleRow(id: "p2", title: "Les sons du lancement", detail: "#15 · estebanbaigts", state: .failure, label: "CI rouge",
                      date: now.addingTimeInterval(-3000), action: "https://github.com"),
            ModuleRow(id: "p3", title: "Météo en anglais", detail: "#11 · louis", state: .busy, label: "CI en cours",
                      date: now.addingTimeInterval(-7000), action: "https://github.com"),
            ModuleRow(id: "e1", title: "Une étoile", detail: "louis · Yumi", state: .neutral, label: "star",
                      date: now.addingTimeInterval(-1500), section: "Derniers événements", action: "https://github.com"),
            ModuleRow(id: "e2", title: "Poussé sur main", detail: "estebanbaigts · Yumi", state: .neutral, label: "push",
                      date: now.addingTimeInterval(-90000), action: "https://github.com"),
        ]
        return ModuleCatalog.placeholders.map { module in
            var module = module
            switch module.id {
            case "claude-code":
                module.status = "3 sessions"
                module.title = "Claude veut ton accord sur api. Je laisse passer ?"
                module.needsAttention = true
                module.rows = [
                    ModuleRow(id: "s1", title: "api", detail: "Demande Bash : rm -rf build", state: .waiting,
                              label: "attend un accord", date: now.addingTimeInterval(-40), action: "s1"),
                    ModuleRow(id: "s2", title: "yumi", detail: "Modifie IslandRows.swift", state: .busy,
                              label: "travaille", date: now.addingTimeInterval(-720), action: "s2", progress: "3/7",
                              details: ["Demande : Montre sur quoi Claude travaille dans l'île", "Tâche 3/7 : Écrit les tests du journal",
                                        "· Lance swift test", "· Modifie ClaudeSessions.swift", "· Lit HookServer.swift", "Depuis 12 min"]),
                    ModuleRow(id: "s3", title: "site", detail: "Deux fichiers modifiés, une commande, 4/4 tâches.", state: .success,
                              label: "terminée", date: now.addingTimeInterval(-50), action: "s3", progress: "4/4"),
                ]
            case "agenda": module.primarySymbol = "video.fill"
            case "music":
                module.progress = ModuleProgress(fraction: 0.58, leading: "1:52", trailing: "3:14")
                module.subtitle = "Halo Nord"
            case "focus":
                module.subtitle = "session 2 sur 4"
                module.live = ModuleLive(text: "18:42", priority: ModuleLivePriority.activity)
            default: break
            }
            if module.id == "music" {
                if let music { module.live?.text = music } else { module.live = nil }
            }
            if module.id == "agenda", !agenda { module.live = nil }
            return module
        } + [github]
    }

    private static func show(_ name: String, _ controller: IslandWindowController) {
        let state = AppState.shared
        let model = IslandModel.shared
        state.pendingApproval = nil
        state.isPinned = false
        state.stateOverride = nil
        state.modules = examples(music: "Lueur · Halo Nord")
        if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks[i].name = "yumi"
            state.tasks[i].steps = ["Lit · YUMI.md", "Modifie · IslandRootView.swift", "Écrit · IslandModel.swift",
                                    "Exécute · xcodebuild -scheme Yumi test"]
        }
        switch name {
        case "home":
            controller.expand(to: .overview)
        case "home-edit":
            controller.expand(to: .overview)
            model.editingModules = true
        case "working":
            state.stateOverride = .working
            model.selectedModuleID = IslandModel.agentModuleID
            controller.expand(to: .module)
        case "alert":
            state.stateOverride = .approval
            state.pendingApproval = ApprovalInfo(sessionId: "demo", tool: "Bash", command: "xcodebuild -scheme Yumi test")
            controller.expand(to: .approval)
        case "finished":
            state.stateOverride = .finished
            controller.expand(to: .finished)
        case "error":
            state.stateOverride = .error
            controller.expand(to: .error)
        case "module":
            model.selectedModuleID = "agenda"
            controller.expand(to: .module)
        case "music":
            model.selectedModuleID = "music"
            controller.expand(to: .module)
        case "talk":
            state.chatHistory = [
                ChatMessage(role: .user, content: "Résume-moi ce PDF en trois points"),
                ChatMessage(role: .assistant, content: "Budget validé à 42 k€, livraison le 14 novembre, un risque sur le prestataire vidéo."),
            ]
            controller.expand(to: .prompt)
        case "drop":
            state.droppedFile = nil
            controller.expand(to: .upload)
        case "file":
            state.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/Contrat-v3.pdf"), name: "Contrat-v3.pdf")
            controller.expand(to: .choose)
        case "focus", "weather", "github", "claude-code":
            model.selectedModuleID = name
            controller.expand(to: .module)
        case "github-pr":
            state.modules = examples(music: "Lueur · Halo Nord", pullRequest: true)
            model.selectedModuleID = "github"
            controller.expand(to: .module)
        case "settings":
            controller.expand(to: .settings)
        case "mail":
            // The mails module with two example accounts (nothing is read from Mail)
            let mails = sampleMails
            GmailInbox.shared.show(mails)
            GmailInbox.shared.showAccounts(MailAccounts.names(in: mails))
            let snapshot = GmailSummary.snapshot(mails: mails, connection: .connected, now: .now, source: .mailApp)
            // Nothing else asks for attention, so the island stays on the mails
            state.modules = state.modules.filter { $0.id != IslandModel.agentModuleID }
                .map { $0.id == "gmail" ? snapshot : $0 }
            if !state.modules.contains(where: { $0.id == "gmail" }) { state.modules.append(snapshot) }
            model.category = .day
            model.selectedModuleID = "gmail"
            controller.expand(to: .module)
        case "screen-time":
            // Screen time with made-up days (nothing is read from the Mac)
            let snapshot = ScreenTimeSummary.snapshot(.example(now: .now), threshold: ScreenTimeSummary.defaultThreshold * 60, now: .now)
            state.modules = state.modules.filter { $0.id != IslandModel.agentModuleID } + [snapshot]
            model.category = .day
            model.selectedModuleID = snapshot.id
            controller.expand(to: .module)
        case "settings-approval":
            // An approval waits: the island stays, the window opens below it
            state.stateOverride = .approval
            state.pendingApproval = ApprovalInfo(sessionId: "demo", tool: "Bash", command: "xcodebuild -scheme Yumi test")
            controller.expand(to: .approval)
            Task { @MainActor in
                await pause(2.5)
                IslandActions.openSettings()
            }
        case "settings-open":
            // The island is open, then the settings window opens: the island folds
            controller.holdsOpen = false
            controller.expand(to: .overview)
            Task { @MainActor in
                await pause(2.5)
                IslandActions.openSettings()
            }
        case "welcome":
            controller.expand(to: .welcome)
        case "welcome-activity":
            // The second step of the first launch, without typing a first name
            WelcomeActivity.startsOnActivity = true
            controller.expand(to: .welcome)
        case "remark-short":
            state.remark = YumiRemark(id: "d1", text: "Deux heures d'affilée. Une pause ?", mood: .worried, duration: 30)
            controller.collapse()
        case "remark-long":
            state.remark = YumiRemark(id: "d2", text: "Point produit dans dix minutes, et Claude attend ta réponse depuis un moment déjà.", mood: .surprised, duration: 30)
        case "remark-action":
            state.remark = YumiRemark(id: "d3", text: "C'est passé, après dix-huit minutes. Bien joué.", mood: .happy, action: "Voir", duration: 30)
        case "remark-open":
            state.remark = YumiRemark(id: "d4", text: "Il est tard. Je reste là, mais toi tu devrais dormir.", mood: .asleep, action: "Bonne nuit", duration: 30)
            controller.expand(to: .overview)
        case "remark-none":
            state.remark = nil
        case "memory":
            state.userName = "Esteban"
            state.memory = memories
            controller.expand(to: .memory)
        case "memory-empty":
            state.userName = nil
            state.memory = []
            controller.expand(to: .memory)
        case "folded-music":
            controller.demoHover = false
            state.modules = examples(music: "Lueur · Halo Nord")
            controller.collapse()
        case "folded-hover":
            controller.demoHover = true
        case "folded-next":
            state.modules = examples(music: "Marée basse · Halo Nord")
        case "folded-long":
            state.modules = examples(music: "Les heures lentes du petit matin sur la côte · Halo Nord et l'Orchestre des Marées")
        case "folded-agenda":
            controller.demoHover = false
            state.modules = examples(music: nil)
        case "folded-none":
            state.modules = examples(music: nil, agenda: false)
        default:
            state.stateOverride = .working
            controller.collapse()
        }
    }

    private static func shot(_ controller: IslandWindowController, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["YUMI_ISLAND_SHOTS"],
              let view = controller.window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
