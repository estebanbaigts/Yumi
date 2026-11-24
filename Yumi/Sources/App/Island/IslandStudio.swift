import AppKit
import Combine
import SwiftUI

/// The filming mode (design/video.md): launched with `YUMI_STUDIO=1`, the island plays
/// each shot of the video on a key, with careful example data and nothing personal, as many
/// times as needed. No sound, no automatic folding, and the pointer is ignored, so that
/// nothing moves but what the shot asks for. `YUMI_STUDIO_SCALE=1.5` or `2` enlarges the
/// island so that it stays sharp once cropped to a vertical frame. Works in Release builds.
@MainActor
enum IslandStudio {
    static let isOn = ProcessInfo.processInfo.environment["YUMI_STUDIO"] == "1"

    /// 1 unless `YUMI_STUDIO_SCALE` says otherwise (between 1 and 3).
    static let scale: CGFloat = {
        guard isOn, let text = ProcessInfo.processInfo.environment["YUMI_STUDIO_SCALE"],
              let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return 1 }
        return CGFloat(min(3, max(1, value)))
    }()

    private static weak var controller: IslandWindowController?
    private static var monitors: [Any] = []
    private static var timers: [DispatchWorkItem] = []
    private static var lastShot: Int?
    /// What the island must show. The core may publish real modules or speak on its own
    /// while filming: the studio's data is put back at once, so nothing personal shows.
    private static var wanted: [ModuleSnapshot] = []
    private static var guards: Set<AnyCancellable> = []

    private static func show(_ modules: [ModuleSnapshot]) {
        wanted = modules
        AppState.shared.modules = modules
    }

    private static func keepData() {
        let state = AppState.shared
        state.$modules.receive(on: DispatchQueue.main)
            .sink { modules in if modules != wanted { state.modules = wanted } }
            .store(in: &guards)
        state.$remark.receive(on: DispatchQueue.main)
            .sink { remark in if let remark, !remark.id.hasPrefix("studio") { state.remark = nil } }
            .store(in: &guards)
        state.$userName.receive(on: DispatchQueue.main)
            .sink { name in if name != Self.name { state.userName = Self.name } }
            .store(in: &guards)
        state.$memory.receive(on: DispatchQueue.main)
            .sink { memory in if !memory.isEmpty { state.memory = [] } }
            .store(in: &guards)
    }

    // MARK: - Example data: believable, never personal

    static let name = "Alex"

    static func modules(musicPlaying: Bool = true) -> [ModuleSnapshot] {
        var music = ModuleSnapshot(id: "music", name: loc("Musique"), colorHex: "#F58AD9", status: loc("lecture"),
                                   title: loc("Lueur"), subtitle: loc("Halo Nord"), primaryAction: loc("Pause"), secondaryAction: loc("Suivant"))
        music.symbol = "music.note"
        music.source = "Spotify"
        music.primarySymbol = "pause.fill"
        music.secondarySymbol = "forward.end.fill"
        music.progress = ModuleProgress(fraction: 0.58, leading: "1:52", trailing: "3:14")
        if musicPlaying {
            music.live = ModuleLive(text: loc("Lueur · Halo Nord"), priority: ModuleLivePriority.activity, controls: [
                ModuleControl(id: "primary", symbol: "pause.fill", label: loc("Pause")),
                ModuleControl(id: "secondary", symbol: "forward.fill", label: loc("Suivant")),
            ])
        }
        var claude = ModuleSnapshot(id: "claude-code", name: loc("Agents"), colorHex: "#FFB547", status: loc("au repos"),
                                    title: loc("Rien en cours"), subtitle: loc("Atelier, dernière session il y a une heure"),
                                    primaryAction: loc("Voir"), secondaryAction: nil)
        claude.symbol = "terminal.fill"
        var agenda = ModuleSnapshot(id: "agenda", name: "Agenda", colorHex: "#5B8CFF", status: "14:30",
                                    title: loc("Point produit dans douze minutes"), subtitle: loc("14:30 à 15:00, en visio"),
                                    primaryAction: loc("Rejoindre"), secondaryAction: nil)
        agenda.symbol = "calendar"
        agenda.primarySymbol = "video.fill"
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ h: Int, _ m: Int) -> Date { day.addingTimeInterval(Double(h * 3600 + m * 60)) }
        agenda.rows = [
            ModuleRow(id: "a1", title: loc("Stand-up"), detail: "09:30", state: .success, label: "", date: at(9, 30)),
            ModuleRow(id: "a2", title: loc("Point produit"), detail: "14:30", state: .waiting, label: loc("dans 12 min"), date: at(14, 30)),
            ModuleRow(id: "a3", title: loc("Focus · refonte"), detail: "16:00", state: .neutral, label: "", date: at(16, 0)),
            ModuleRow(id: "a4", title: loc("Sport"), detail: "18:30", state: .neutral, label: "", date: at(18, 30)),
        ]
        agenda.pages["week"] = [
            (loc("Revue de sprint · 10:00"), 2), (loc("Dentiste · 17:30"), 1), (loc("Démo client · 15:00"), 3), (loc("Rien de prévu"), 0),
        ].enumerated().map { i, item in
            let date = Calendar.current.date(byAdding: .day, value: i + 1, to: day) ?? day
            return ModuleRow(id: "d\(i)", title: date.formatted(.dateTime.weekday(.abbreviated).day()).capitalized, detail: item.0,
                             state: .neutral, label: item.1 > 0 ? loc("\(item.1) évén.") : "", date: date)
        }
        var notes = ModuleSnapshot(id: "notes", name: "Notes", colorHex: "#F2C744", status: "3",
                                   title: loc("Dernière note"), subtitle: loc("Idée : une page d'accueil plus calme"),
                                   primaryAction: loc("Nouvelle note"), secondaryAction: nil)
        notes.symbol = "note.text"
        var focus = ModuleSnapshot(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: loc("prêt"),
                                   title: loc("Prêt pour une session"), subtitle: loc("vingt-cinq minutes"),
                                   primaryAction: loc("Démarrer"), secondaryAction: nil)
        focus.symbol = "timer"
        focus.primarySymbol = "play.fill"
        var weather = ModuleSnapshot(id: "weather", name: loc("Météo"), colorHex: "#7FD0FF", status: "19°",
                                     title: loc("19° et des éclaircies"), subtitle: loc("Pluie vers 18 h, prends une veste"),
                                     primaryAction: loc("Détail"), secondaryAction: nil)
        weather.symbol = "cloud.sun.fill"
        var github = ModuleSnapshot(id: "github", name: "GitHub", colorHex: "#C9CCDA", status: "128 · 12 · 3",
                                    title: loc("Une étoile de plus sur Atelier."), subtitle: loc("alex/atelier"),
                                    primaryAction: loc("Ouvrir"), secondaryAction: nil)
        github.symbol = "arrow.triangle.branch"
        github.pages["recent"] = [
            ModuleRow(id: "g1", title: loc("Merge de la PR #31"), detail: "alex/atelier · main", state: .success, label: loc("il y a 2 h")),
            ModuleRow(id: "g2", title: loc("Push sur refonte-ile"), detail: "alex/atelier · 3 commits", state: .busy, label: loc("il y a 3 h")),
            ModuleRow(id: "g3", title: loc("Revue demandée"), detail: "alex/notes · #12", state: .waiting, label: loc("hier")),
        ]
        github.pages["repos"] = [
            ModuleRow(id: "r1", title: "alex/atelier", detail: loc("Swift · dernier push il y a 2 h"), state: .neutral, label: loc("2 PR ouvertes")),
            ModuleRow(id: "r2", title: "alex/notes", detail: loc("TypeScript · hier"), state: .neutral, label: loc("1 PR ouverte")),
            ModuleRow(id: "r3", title: "alex/site", detail: loc("HTML · il y a 4 jours"), state: .neutral, label: loc("aucune PR")),
        ]
        return [claude, agenda, notes, focus, music, weather, github]
    }

    /// What GetTodayTool answers for tomorrow when asked for the free time, on a day with two
    /// example appointments: 10:00 to 12:00 and 17:00 to 20:00.
    static func freeTimeAnswer(now: Date = .now) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        func at(_ hour: Int) -> Date { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow }
        let events = [
            AgendaEvent(id: "studio-1", title: loc("Point produit"), start: at(10), end: at(12), isAllDay: false, location: ""),
            AgendaEvent(id: "studio-2", title: loc("Atelier client"), start: at(17), end: at(20), isAllDay: false, location: ""),
        ]
        let facts = TodayFacts(events: events, reminders: nil, weather: nil, dayEvents: events)
        return TodayPhrase.reply(facts, day: tomorrow, now: now, freeTime: true, calendar: calendar)
    }

    enum SessionsMoment { case working, waiting, answered }

    /// The example modules with the Claude Code module as ClaudeSessions would make it: one
    /// session at work, or three with one asking, or the same three once it was answered.
    /// Same sentences as the module's (ClaudeSessions.phrase, snapshot, live).
    static func sessions(_ moment: SessionsMoment) -> [ModuleSnapshot] {
        var all = modules(musicPlaying: false)
        guard let index = all.firstIndex(where: { $0.id == "claude-code" }) else { return all }
        let now = Date.now
        var claude = all[index]
        var atelier = ModuleRow(id: "s2", title: loc("atelier"), detail: loc("Modifie Accueil.swift"), state: .busy,
                                label: loc("travaille"), date: now.addingTimeInterval(-720), action: "s2")
        atelier.agent = "Claude Code"; atelier.place = "atelier"; atelier.isRepository = true
        atelier.branch = "refonte-accueil"; atelier.model = "Opus 4.5"
        switch moment {
        case .working:
            claude.status = loc("1 session")
            claude.title = loc("Claude modifie Accueil.swift sur atelier.")
            claude.subtitle = loc("Une session ouverte.")
            claude.rows = [atelier]
        case .waiting:
            claude.status = loc("3 sessions")
            claude.title = loc("Claude veut ton accord sur api. Je laisse passer ?")
            claude.subtitle = loc("Trois sessions ouvertes, une t'attend.")
            claude.needsAttention = true
            claude.live = ModuleLive(text: loc("3 sessions · accord sur api"), priority: ModuleLivePriority.attention,
                                     controls: [ModuleControl(id: "primary", symbol: "eye.fill", label: loc("Voir"))])
            var api = ModuleRow(id: "s1", title: loc("api"), detail: loc("Veut lancer npm test"), state: .waiting,
                                label: loc("attend un accord"), date: now.addingTimeInterval(-40), action: "s1")
            api.agent = "Claude Code"; api.place = "api"; api.isRepository = true; api.branch = "main"; api.model = "Sonnet 4.5"
            var notes = ModuleRow(id: "s3", title: loc("Notes"), detail: loc("C'est passé."), state: .success,
                                  label: loc("terminée"), date: now.addingTimeInterval(-7200), action: "s3")
            notes.agent = "Claude Code"; notes.place = "Notes"; notes.model = "Haiku 4.5"
            claude.rows = [api, atelier, notes]
        case .answered:
            claude.status = loc("3 sessions")
            claude.title = loc("C'est passé sur api.")
            claude.subtitle = loc("Trois sessions ouvertes.")
            claude.rows = [
                ModuleRow(id: "s1", title: loc("api"), detail: loc("C'est passé."), state: .success,
                          label: loc("terminée"), date: now, action: "s1"),
                atelier,
                ModuleRow(id: "s3", title: loc("site"), detail: loc("C'est passé."), state: .success,
                          label: loc("terminée"), date: now.addingTimeInterval(-120), action: "s3"),
            ]
        }
        all[index] = claude
        return all
    }

    // MARK: - Alpha 5 shots

    /// A session's journal as the hooks build it, for the example project "atelier".
    static func liveJournal() -> SessionJournal {
        var journal = SessionJournal(started: Date.now.addingTimeInterval(-540))
        journal.request = "Refais l'écran d'accueil, plus calme"
        journal.todos = [
            SessionTodo(text: "Lire l'écran d'accueil", state: .completed),
            SessionTodo(text: "Simplifier la mise en page", state: .inProgress),
            SessionTodo(text: "Lancer les tests", state: .pending),
            SessionTodo(text: "Adoucir les couleurs", state: .pending),
            SessionTodo(text: "Revoir les textes", state: .pending),
            SessionTodo(text: "Vérifier le mode sombre", state: .pending),
            SessionTodo(text: "Résumer les changements", state: .pending),
        ]
        journal.history = [ToolStep(tool: "Read", input: ["file_path": "/atelier/Sources/AccueilView.swift"])]
        journal.current = ToolStep(tool: "Edit", input: ["file_path": "/atelier/Sources/AccueilView.swift"])
        return journal
    }

    /// The example modules with Claude Code as ClaudeSessions makes it from that journal:
    /// the row enriched with the progress and the details, the live line of the folded island.
    static func liveSession(_ journal: SessionJournal, now: Date) -> [ModuleSnapshot] {
        var all = modules(musicPlaying: false)
        guard let index = all.firstIndex(where: { $0.id == "claude-code" }) else { return all }
        var claude = all[index]
        let base = ModuleRow(id: "studio-session", title: "atelier", detail: "", state: .busy, label: loc("travaille"),
                             date: journal.started, action: "studio-session")
        let row = SessionBoard.enriched(base, journal, now: now)
        let what = journal.current?.sentence ?? journal.currentTask ?? ""
        let progress = journal.progress.map { " \($0)" } ?? ""
        claude.status = loc("1 session")
        claude.title = "Claude \(what.prefix(1).lowercased() + what.dropFirst()) sur atelier."
        claude.subtitle = journal.currentTask.map { loc("Tâche \(journal.progress ?? "") : \($0)") } ?? ""
        claude.rows = [row]
        claude.live = ModuleLive(text: "atelier\(progress) · \(what)", priority: ModuleLivePriority.activity)
        all[index] = claude
        return all
    }

    /// GitHub as its module shows it, built by GitHubActivity from example pushes on two
    /// repositories. `fresh` adds a push made a few seconds ago.
    static func githubActivity(fresh: Bool) -> [ModuleSnapshot] {
        let now = Date.now
        func commit(_ sha: String, _ message: String) -> GitHubCommit {
            GitHubCommit(sha: sha, message: message, author: "alex", url: URL(string: "https://github.com/alex/atelier/commit/\(sha)"))
        }
        var pushes = [
            GitHubPush(eventID: 3, repo: "alex/atelier", branch: "main", actor: "alex", date: now.addingTimeInterval(-3600), total: 2,
                       commits: [commit("a41c9e27d0", "Accueil : une mise en page plus calme"), commit("9be03f1c55", "Tests de l'écran d'accueil")]),
            GitHubPush(eventID: 2, repo: "alex/site", branch: "main", actor: "lea", date: now.addingTimeInterval(-7200), total: 1,
                       commits: [GitHubCommit(sha: "77d2a0b913", message: "Page tarifs : corrige le lien", author: "lea", url: nil)]),
        ]
        if fresh {
            pushes.append(GitHubPush(eventID: 4, repo: "alex/atelier", branch: "main", actor: "alex", date: now.addingTimeInterval(-5), total: 3,
                                     commits: [commit("c0ffee1a2b", "Couleurs plus douces sur l'accueil"), commit("5e6f7a8b9c", "Mode sombre de l'accueil"),
                                               commit("1d2e3f4a5b", "Textes de l'accueil revus")]))
        }
        var all = modules(musicPlaying: false)
        guard let index = all.firstIndex(where: { $0.id == "github" }) else { return all }
        var github = all[index]
        github.status = "2"
        github.title = loc("Ce qui bouge sur tes dépôts")
        github.subtitle = "alex/atelier, alex/site"
        github.rows = GitHubActivity.rows(pushes: pushes, events: [], hidden: [], now: now)
        if let push = GitHubActivity.livePush(pushes, hidden: [], now: now) {
            github.live = ModuleLive(text: loc("\(push.repoName) · \(push.total) commits sur \(push.branch)"), priority: ModuleLivePriority.activity)
        }
        all[index] = github
        return all
    }

    /// Example mails for the Gmail shot, in the language of the app: two important, one from a
    /// friend, one newsletter. Nobody real.
    static func gmailMails(now: Date = .now) -> [GmailMail] {
        let fr = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") ?? true
        func mail(_ uid: Int, _ from: String, _ subject: (String, String), _ minutes: Double, unread: Bool,
                  important: Bool = false, bulk: Bool = false) -> GmailMail {
            var mail = GmailMail(uid: uid, from: from, subject: fr ? subject.0 : subject.1,
                                 date: now.addingTimeInterval(-minutes * 60), unread: unread, thread: nil)
            mail.important = important
            mail.bulk = bulk
            mail.replyAddress = bulk ? "" : "\(from.lowercased().replacingOccurrences(of: " ", with: "."))@example.com"
            return mail
        }
        return [
            mail(104, "Camille Martin", ("Devis pour le site, une question", "Quote for the site, one question"), 12, unread: true, important: true),
            mail(103, "Studio Lumen", ("Réunion de lancement jeudi ?", "Kick-off meeting on Thursday?"), 48, unread: true, important: true),
            mail(102, "Paul", ("Photos du week-end", "Weekend photos"), 95, unread: true),
            mail(101, "Atelier Hebdo", ("Les nouveautés de la semaine", "This week's news"), 180, unread: false, bulk: true),
        ]
    }

    /// The answer Yumi suggests to the first mail. Like the real prompt, it invents nothing:
    /// what it does not know is left to complete.
    static func gmailDraft() -> String {
        let fr = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") ?? true
        return fr
            ? "Bonjour Camille, merci pour ton message. Oui, le devis comprend la version mobile. Je t'envoie le détail des délais [à compléter]. Alex"
            : "Hi Camille, thanks for your message. Yes, the quote includes the mobile version. I'll send you the timeline details [to complete]. Alex"
    }

    /// The example modules with Gmail as GmailSummary makes it from those mails.
    static func gmail(_ mails: [GmailMail]) -> [ModuleSnapshot] {
        modules(musicPlaying: false) + [GmailSummary.snapshot(mails: mails, connection: .connected, now: .now)]
    }

    /// Notion as NotionModule.snapshot words it, from example tasks: two today, one late.
    static func notionTasks() -> [ModuleSnapshot] {
        let now = Date.now
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tasks = [
            NotionTask(id: "n1", title: "Envoyer la maquette à Léa", due: calendar.date(byAdding: .day, value: -1, to: today), hasTime: false, url: nil, base: "Projets"),
            NotionTask(id: "n2", title: "Relire le texte de la page d'accueil", due: today, hasTime: false, url: nil, base: "Projets"),
            NotionTask(id: "n3", title: "Appel avec le client", due: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: today), hasTime: true, url: nil, base: "Rendez-vous"),
        ]
        var notion = ModuleSnapshot(id: "notion", name: "Notion", colorHex: "#E8E8E8", status: "\(tasks.count)", title: "", subtitle: "",
                                    primaryAction: loc("Ouvrir"), symbol: "checklist")
        let late = tasks.filter { NotionBoard.isLate($0, now: now, calendar: calendar) }
        notion.title = loc("\(tasks.count) tâches à faire")
        notion.subtitle = late.count == 1 ? loc("Une en retard.") : loc("\(late.count) en retard.")
        notion.rows = tasks.map { task in
            let isLate = NotionBoard.isLate(task, now: now, calendar: calendar)
            let when = task.due.map { task.hasTime ? FrenchText.clock($0) : (isLate ? loc("en retard") : loc("aujourd'hui")) } ?? ""
            return ModuleRow(id: task.id, title: task.title, detail: task.base, state: isLate ? .failure : .neutral, label: when,
                             date: task.due, action: "open:\(task.id)")
        }
        return modules(musicPlaying: false) + [notion]
    }

    // MARK: - Starting

    static func startIfRequested(controller: IslandWindowController) {
        guard isOn, self.controller == nil else { return }
        self.controller = controller
        SoundEngine.shared.enabled = false
        controller.holdsOpen = true
        controller.fsm.petitToHiddenDelay = 86_400
        applyData()
        keepData()

        // Keys work whether the island is in front or not: a local monitor when it is,
        // a global one when another application is (this one needs the Accessibility
        // permission, like the Escape key of the island).
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let handled = MainActor.assumeIsolated { key(event.keyCode) }
            return handled ? nil : event
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { event in
            let code = event.keyCode
            MainActor.assumeIsolated { _ = key(code) }
        }) { monitors.append(monitor) }

        if let folder = ProcessInfo.processInfo.environment["YUMI_STUDIO_SHOTS"] { rehearse(into: folder) }
        if let folder = ProcessInfo.processInfo.environment["YUMI_ISLAND_V2_SHOTS"] { shootIsland(into: folder) }
    }

    /// `YUMI_STUDIO_SHOTS=<folder>` plays every shot in turn and saves a picture of the island
    /// twice a second, to check the mode without filming.
    /// `YUMI_STUDIO_ONLY=10,11,12` plays only these shots, in this order.
    private static func rehearse(into folder: String) {
        let lengths: [Int: Double] = [1: 6, 2: 9, 3: 5, 4: 9, 5: 8, 6: 9, 7: 4, 8: 12, 9: 6, 10: 8, 11: 12, 12: 15, 13: 11, 14: 11, 15: 10, 16: 14]
        let only = (ProcessInfo.processInfo.environment["YUMI_STUDIO_ONLY"] ?? "")
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let shots = only.isEmpty ? Array(1...9) : only
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            for shot in shots {
                play(shot)
                for frame in 0..<Int((lengths[shot] ?? 6) * 2) {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard let view = controller?.window?.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(String(format: "shot%d-%02d.png", shot, frame))
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
            }
            NSApp.terminate(nil)
        }
    }

    /// The core may publish its own state: the studio's data comes back at every shot.
    private static func applyData(musicPlaying: Bool = false) {
        let state = AppState.shared
        state.userName = name
        show(modules(musicPlaying: musicPlaying))
        state.memory = []
        state.remark = nil
        state.chatLive = nil
        state.chatHistory = []
        state.promptContext = nil
        state.droppedFile = nil
        state.pendingApproval = nil
        state.isPinned = false
        state.stateOverride = .idle
        if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks[i].name = loc("atelier")
            state.tasks[i].steps = ["Lit · README.md", "Modifie · Accueil.swift", loc("Exécute · swift test")]
        }
        IslandModel.shared.studioPress = false
    }

    // MARK: - Keys

    /// 1 to 9 play a shot, and the three keys after them (0, then the two to its right) play
    /// shots 10 to 12. Space plays the last one again, Escape puts Yumi back at rest, R folds
    /// the island.
    private static func key(_ code: UInt16) -> Bool {
        let shots: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9, 29: 10, 27: 11, 24: 12, 33: 13, 30: 14, 42: 15]
        if let shot = shots[code] { play(shot); return true }
        switch code {
        case 49: if let lastShot { play(lastShot) }; return true        // Space
        case 53: rest(); return true                                     // Escape
        case 15: cancel(); controller?.collapse(); return true           // R
        default: return false
        }
    }

    private static func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem { MainActor.assumeIsolated { work() } }
        timers.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private static func cancel() {
        timers.forEach { $0.cancel() }
        timers = []
    }

    /// Yumi at rest in the folded island, nothing live, nothing pending.
    static func rest() {
        cancel()
        applyData()
        IslandModel.shared.setHabit(nil)
        controller?.studioRest()
    }

    // MARK: - The shots of design/video.md

    static func play(_ shot: Int) {
        guard let controller else { return }
        lastShot = shot
        let state = AppState.shared
        let model = IslandModel.shared
        rest()

        switch shot {
        case 1:
            // The full launch
            controller.studioLaunch()

        case 2:
            // A permission, a click on the green button, and he celebrates
            after(0.6) {
                state.stateOverride = .approval
                state.pendingApproval = ApprovalInfo(sessionId: "studio", tool: "Bash", command: "swift test")
                controller.expand(to: .approval)
            }
            after(3.0) { model.studioPress = true }
            after(3.25) {
                model.studioPress = false
                state.pendingApproval = nil
                state.stateOverride = .finished
                state.view = .finished
            }
            after(8.5) { state.stateOverride = .idle }

        case 3:
            // The music starts, he puts his headphones on
            after(0.6) {
                show(modules(musicPlaying: true))
                model.selectedModuleID = "music"
                controller.expand(to: .module)
            }

        case 4:
            // The chat writes itself, then a file is created
            after(0.6) {
                state.stateOverride = .thinking
                state.chatHistory = [ChatMessage(role: .user, content: loc("Écris-moi un petit mot de bienvenue pour le site, et enregistre-le."))]
                controller.expand(to: .prompt)
            }
            var live = ChatLive()
            var at = 1.8
            for word in loc("Je m'en occupe. Quelques lignes simples, puis je range le fichier dans Téléchargements.").split(separator: " ") {
                at += 0.08
                let text = String(word)
                after(at) {
                    live.text += (live.text.isEmpty ? "" : " ") + text
                    state.chatLive = live
                }
            }
            let lines = [loc("Bienvenue."), "", loc("Ici, on prend le temps de bien faire."), loc("Installe-toi, regarde autour de toi,"), loc("et écris-nous si tu as une question.")]
            for (index, _) in lines.enumerated() {
                after(at + 0.5 + Double(index) * 0.35) {
                    live.activity = ChatActivity(id: "w1", kind: .writing, label: loc("Écrit bienvenue.txt"),
                                                 detail: lines[0...index].joined(separator: "\n"))
                    state.chatLive = live
                }
            }
            let end = at + 0.5 + Double(lines.count) * 0.35 + 0.5
            after(end) {
                live.done = [ChatActivity(id: "w1", kind: .writing, label: loc("Écrit bienvenue.txt"))]
                live.activity = nil
                live.text += loc(" C'est fait : bienvenue.txt t'attend.")
                state.chatLive = live
            }
            after(end + 1.0) {
                let text = live.text
                state.chatLive = nil
                state.stateOverride = .idle
                state.chatHistory.append(ChatMessage(role: .assistant, content: text))
            }

        case 5:
            // Folded, he speaks first
            after(0.8) {
                state.remark = YumiRemark(id: "studio-\(Date.now.timeIntervalSince1970)",
                                          text: loc("Deux heures d'affilée. Une pause ?"), mood: .worried, duration: 6)
            }
            after(7.5) { state.remark = nil }

        case 6:
            // His moods, one after the other: coffee, matcha, cloud, sunglasses, sleep
            after(0.5) { controller.expand(to: .overview) }
            let habits: [YumiHabit] = [.coffee, .matcha, .cloud, .sunglasses, .sleep]
            for (index, habit) in habits.enumerated() {
                after(1.6 + Double(index) * 1.5) {
                    model.setHabit(habit)
                    if habit != .sleep { model.pose(.pop) }
                }
            }
            after(1.6 + Double(habits.count) * 1.5 + 0.8) { model.setHabit(nil) }

        case 7:
            // Yumi alone in his light, and a wink
            controller.studioPortrait()
            after(1.4) { model.setMood(.wink, force: true) }
            after(2.6) { model.setMood(.happy, force: true) }

        case 8:
            // GitHub: a star, a fork, a merge
            after(0.5) {
                model.selectedModuleID = "github"
                controller.expand(to: .module)
            }
            let scenes: [(YumiScene, String, String)] = [
                (.star, loc("Une étoile de plus sur Atelier."), "129 · 12 · 3"),
                (.fork, loc("Quelqu'un a copié Atelier pour y travailler."), "129 · 13 · 3"),
                (.merge, loc("La pull request « Accueil plus calme » est fusionnée."), "129 · 13 · 2"),
            ]
            for (index, scene) in scenes.enumerated() {
                after(1.8 + Double(index) * 3.2) {
                    var changed = wanted
                    if let i = changed.firstIndex(where: { $0.id == "github" }) {
                        changed[i].title = scene.1
                        changed[i].status = scene.2
                    }
                    show(changed)
                    NotificationCenter.default.post(name: .yumiScene, object: scene.0)
                }
            }

        case 9:
            // The goodbye
            controller.studioGoodbye()

        case 10:
            // Tomorrow's free time, asked in the chat. The answer goes through the agent runtime
            // in the app (get_today), which this mode does not run: the sentence is written by
            // the tool's own code, from two example appointments, and arrives as a whole, as
            // the runtime's answers do
            after(0.6) {
                state.stateOverride = .thinking
                state.chatHistory = [ChatMessage(role: .user, content: loc("Combien de temps libre j'ai demain pour avancer sur Yumi ?"))]
                controller.expand(to: .prompt)
            }
            after(2.6) {
                state.chatHistory.append(ChatMessage(role: .assistant, content: freeTimeAnswer()))
                state.stateOverride = .idle
                model.setMood(.happy, force: true)
                model.pose(.celebrate)
            }

        case 11:
            // An agent at work, and Yumi with his matcha: folded first, then open on the
            // session, where he is large enough for the bowl to be seen
            after(0.4) {
                show(sessions(.working))
                state.stateOverride = .working
                model.setHabit(.matcha)
            }
            after(3.0) {
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }

        case 12:
            // Three sessions, one waits for an answer; it is given from the notch
            after(0.5) {
                show(sessions(.waiting))
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }
            after(4.5) {
                // The approval is the one of the api session
                if let i = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
                    state.tasks[i].name = loc("api")
                    state.tasks[i].steps = ["Exécute · npm test"]
                }
                state.stateOverride = .approval
                state.pendingApproval = ApprovalInfo(sessionId: "studio", tool: "Bash", command: "npm test")
                controller.expand(to: .approval)
            }
            after(7.1) { model.studioPress = true }
            after(7.35) {
                model.studioPress = false
                state.pendingApproval = nil
                state.stateOverride = .finished
                state.view = .finished
            }
            after(9.7) {
                state.stateOverride = .idle
                show(sessions(.answered))
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }

        case 13:
            // A Claude Code session at work, as its journal tells it: the task 2/7 then 3/7,
            // the action in progress, the line unfolded on its details
            var journal = liveJournal()
            after(0.4) {
                show(liveSession(journal, now: .now))
            }
            after(2.6) {
                model.selectedModuleID = "claude-code"
                controller.expand(to: .module)
            }
            after(5.6) {
                journal.todos[1].state = .completed
                journal.todos[2].state = .inProgress
                journal.history.append(journal.current!)
                journal.current = ToolStep(tool: "Bash", input: ["command": "swift test --filter Accueil"])
                show(liveSession(journal, now: .now))
            }
            after(8.4) {
                journal.history.append(journal.current!)
                journal.current = ToolStep(tool: "Edit", input: ["file_path": "/atelier/Sources/AccueilView.swift"])
                show(liveSession(journal, now: .now))
            }

        case 14:
            // GitHub: every repository, each push with its exact commits; a push arrives
            after(0.4) {
                show(githubActivity(fresh: false))
                model.selectedModuleID = "github"
                controller.expand(to: .module)
            }
            after(5.5) { show(githubActivity(fresh: true)) }
            after(8.0) { controller.collapse() }

        case 15:
            // Notion: the tasks of today and the late ones, in the island
            after(0.4) {
                show(notionTasks())
                model.selectedModuleID = "notion"
                controller.expand(to: .module)
            }
            after(6.5) { model.setMood(.happy, force: true); model.pose(.celebrate) }

        case 16:
            // Gmail: the important mails apart, one opened, and the answer Yumi suggests.
            // Nothing is sent: the shot ends on the Envoyer button, never pressed
            let mails = gmailMails()
            after(0.4) {
                GmailInbox.shared.show(mails)
                show(gmail(mails))
                IslandActions.showTab(.day)
                controller.expand(to: .overview)
            }
            after(2.8) {
                model.selectedModuleID = "gmail"
                controller.expand(to: .module)
            }
            after(5.6) { NotificationCenter.default.post(name: .yumiStudioGmail, object: StudioGmail.choose(mails[0].uid)) }
            after(6.8) {
                NotificationCenter.default.post(name: .yumiStudioGmail, object: StudioGmail.think)
                model.setMood(.thinking)
            }
            var typed = ""
            var at = 8.4
            for word in gmailDraft().split(separator: " ", omittingEmptySubsequences: false) {
                at += 0.07
                let part = String(word)
                after(at) {
                    typed += (typed.isEmpty ? "" : " ") + part
                    NotificationCenter.default.post(name: .yumiStudioGmail, object: StudioGmail.draft(typed))
                }
            }
            after(at + 0.2) { model.setMood(nil); model.pose(.pop) }

        default:
            break
        }
    }
}

// MARK: - Pictures of the island in cards

extension IslandStudio {
    /// `YUMI_ISLAND_V2_SHOTS=<folder>`: one picture of each view of the island in cards (folded,
    /// the three tabs, a Claude approval, the chat, the settings, three costumes), then quits.
    /// The colour, the costume and the tab of the person are put back before quitting.
    private static func shootIsland(into folder: String) {
        let defaults = UserDefaults.standard
        let kept = [IslandAccent.defaultsKey, YumiCostume.defaultsKey, IslandPrefs.categoryKey]
            .map { ($0, defaults.object(forKey: $0)) }
        let state = AppState.shared
        let model = IslandModel.shared

        func wear(_ costume: YumiCostume, _ accent: IslandAccent) {
            costume.save()
            accent.save()
            NotificationCenter.default.post(name: .yumiLook, object: nil)
        }
        func save(_ name: String) {
            guard let view = controller?.window?.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        func sessions() -> [ModuleSnapshot] {
            var all = IslandStudio.sessions(.waiting)
            if let i = all.firstIndex(where: { $0.id == "claude-code" }) {
                all[i].rows[1].progress = "3/7"
                all[i].rows[1].detail = loc("Modifie Accueil.swift")
                all[i].rows[1].details = [loc("Lire l'écran d'accueil"), loc("Lancer les tests")]
                all[i].rows.swapAt(0, 1)
            }
            return all
        }
        let shots: [(String, @MainActor () -> Void)] = [
            ("01-repliee", { show(sessions()); controller?.collapse() }),
            ("02-travail", { show(sessions()); model.selectedSessionID = nil; IslandActions.showTab(.work); controller?.expand(to: .overview) }),
            ("02b-fiche-claude", {
                let journals = ClaudeSessionJournals.shared
                let notes: [SessionNote.Kind] = [
                    .prompt(loc("Refais l'écran d'accueil, plus calme")),
                    .todos([SessionTodo(text: loc("Lire l'écran d'accueil"), state: .completed),
                            SessionTodo(text: loc("Simplifier la mise en page"), state: .completed),
                            SessionTodo(text: loc("Modifie Accueil.swift"), state: .inProgress),
                            SessionTodo(text: loc("Lancer les tests"), state: .pending)]),
                    .toolFinished(ToolStep(tool: "Read", input: ["file_path": "/atelier/AccueilView.swift"]), failed: false),
                    .toolFinished(ToolStep(tool: "Grep", input: ["pattern": "Theme.spacing"]), failed: false),
                    .toolFinished(ToolStep(tool: "Edit", input: ["file_path": "/atelier/Theme.swift"]), failed: false),
                    .toolFinished(ToolStep(tool: "Bash", input: ["command": "swift build"]), failed: false),
                    .toolStarted(ToolStep(tool: "Edit", input: ["file_path": "/atelier/AccueilView.swift"])),
                ]
                for kind in notes { journals.apply(SessionNote(session: "s2", kind: kind), now: Date.now.addingTimeInterval(-540)) }
                show(sessions()); model.selectedSessionID = nil; IslandActions.showModule("claude-code"); controller?.expand(to: .module)
            }),
            ("03-journee", { show(modules(musicPlaying: false)); IslandActions.showTab(.day); controller?.expand(to: .overview) }),
            ("04-detente", { show(modules(musicPlaying: true)); IslandActions.showTab(.relax); controller?.expand(to: .overview) }),
            ("04b-fiche-musique", { show(modules(musicPlaying: true)); IslandActions.showModule("music"); controller?.expand(to: .module) }),
            ("10-page-agents", { show(sessions()); IslandActions.showModule("claude-code"); controller?.expand(to: .module) }),
            ("11-meteo-pluie-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-pluie", { WeatherAmbiance.forced = .pluie; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-soleil-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-soleil", { WeatherAmbiance.forced = .soleil; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-neige-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-neige", { WeatherAmbiance.forced = .neige; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-nuit-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-nuit", { WeatherAmbiance.forced = .nuit; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-chaud-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-chaud", { WeatherAmbiance.forced = .chaud; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-froid-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-froid", { WeatherAmbiance.forced = .froid; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-doux-avant", { IslandActions.showModule("agenda") }),
            ("11-meteo-doux", { WeatherAmbiance.forced = .doux; show(modules(musicPlaying: false)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("11-meteo-fin", { WeatherAmbiance.forced = nil }),
            ("10-page-agenda", { show(modules(musicPlaying: true)); IslandActions.showModule("agenda"); controller?.expand(to: .module) }),
            ("10-page-weather", { show(modules(musicPlaying: true)); IslandActions.showModule("weather"); controller?.expand(to: .module) }),
            ("10-page-focus", { show(modules(musicPlaying: true)); IslandActions.showModule("focus"); controller?.expand(to: .module) }),
            ("10-page-github", { show(modules(musicPlaying: true)); IslandActions.showModule("github"); controller?.expand(to: .module) }),
            ("10-page-gmail", { show(modules(musicPlaying: true)); IslandActions.showModule("gmail"); controller?.expand(to: .module) }),
            ("05-accord", {
                show(sessions())
                state.stateOverride = .approval
                state.pendingApproval = ApprovalInfo(sessionId: "studio", tool: "Bash", command: "npm test -- --watch=false")
                controller?.expand(to: .approval)
            }),
            ("06-chat", {
                state.chatHistory = [ChatMessage(role: .user, content: loc("Rappelle-moi d'appeler Paul demain à 15 h")),
                                     ChatMessage(role: .assistant, content: loc("C'est noté, je te le rappelle demain à 15 h."))]
                controller?.expand(to: .prompt)
            }),
            ("06b-voix-ecoute", { state.chatHistory = []; IslandVoice.shared.phase = .listening(loc("Où est le réglage du Wi-Fi")); controller?.expand(to: .prompt) }),
            ("06c-voix-reponse", {
                IslandVoice.shared.canPoint = true
                IslandVoice.shared.phase = .answer(question: loc("Où est le réglage du Wi-Fi ?"),
                                                   text: loc("Dans la barre des menus, en haut à droite : l'icône Wi-Fi."), note: nil)
                controller?.expand(to: .prompt)
            }),
            ("06d-fin-voix", { IslandVoice.shared.phase = .idle }),
            ("17-trou-noir", { show(modules(musicPlaying: false)); controller?.collapse(); withAnimation(nil) { BlackHole.shared.open = true } }),
            ("17b-avale", { BlackHole.shared.heldAt = 0.45; BlackHole.shared.open = true; BlackHole.shared.swallowing = ("Contrat-v3.pdf", Date()) }),
            ("17c-fichier", {
                BlackHole.shared.heldAt = nil; BlackHole.shared.open = false; BlackHole.shared.swallowing = nil
                state.droppedFile = DroppedFile(url: URL(fileURLWithPath: "/tmp/Contrat-v3.pdf"), name: "Contrat-v3.pdf")
                controller?.expand(to: .choose)
            }),
            ("17d-fin", { state.droppedFile = nil }),
            ("18-termine", { show(sessions()); controller?.expand(to: .finished) }),
            ("19-demarrage", { controller?.collapse(); controller?.studioLaunch() }),
            ("20-personnage", { show(modules(musicPlaying: true)); IslandModel.shared.selectedModuleID = IslandHomeOrder.characterID; controller?.expand(to: .module) }),
            ("21-meteo-ou", {
                var all = modules(musicPlaying: false)
                if let i = all.firstIndex(where: { $0.id == "weather" }) {
                    all[i].status = loc("où ?"); all[i].title = loc("Je ne sais pas où tu es."); all[i].subtitle = loc("Dis-moi où tu es pour voir le ciel."); all[i].primaryAction = loc("Autoriser")
                }
                show(all); IslandActions.showModule("weather"); controller?.expand(to: .module)
            }),
            ("07-reglages", { controller?.expand(to: .settings) }),
            ("08-skin-couronne", { wear(.crown, .yumi); show(sessions()); IslandActions.showTab(.work); controller?.expand(to: .overview) }),
            ("09-skin-chat", { wear(.cat, .pink); show(modules(musicPlaying: false)); IslandActions.showTab(.day); controller?.expand(to: .overview) }),
            ("10-skin-sorciere", { wear(.witch, .green); show(modules(musicPlaying: true)); IslandActions.showTab(.relax); controller?.expand(to: .overview) }),
            ("12-skin-licorne", { wear(.unicorn, .sky); show(sessions()); IslandActions.showTab(.work); controller?.expand(to: .overview) }),
            ("13-skin-antennes", { wear(.antennae, .orange); show(modules(musicPlaying: false)); IslandActions.showTab(.day); controller?.expand(to: .overview) }),
            ("14-skin-pirate", { wear(.pirate, .yumi); show(modules(musicPlaying: false)); IslandActions.showTab(.day); controller?.expand(to: .overview) }),
            ("15-skin-fete", { wear(.party, .pink); show(modules(musicPlaying: true)); IslandActions.showTab(.relax); controller?.expand(to: .overview) }),
            ("16-skin-noeud", { wear(.bow, .yumi); show(modules(musicPlaying: true)); IslandActions.showTab(.relax); controller?.expand(to: .overview) }),
            ("98-stress-onglets", {
                // Views switched faster than their animations: Yumi must end in the last one's place
                show(sessions()); controller?.expand(to: .overview)
                let steps: [@MainActor () -> Void] = [
                    { IslandActions.showTab(.day) }, { IslandActions.showModule("claude-code") }, { IslandActions.go(.settings) },
                    { IslandActions.showTab(.relax) }, { IslandActions.showModule("music") }, { IslandActions.go(.prompt) },
                    { IslandActions.showTab(.work) }, { IslandActions.showModule("agenda") }, { IslandActions.showTab(.day) },
                ]
                for (i, step) in steps.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 + Double(i) * 0.12) { MainActor.assumeIsolated { step() } }
                }
            }),
            ("11-skin-repliee", { wear(.witch, .green); show(modules(musicPlaying: true)); controller?.collapse() }),
        ]
        Task { @MainActor in
            wear(.none, .yumi)
            try? await Task.sleep(for: .seconds(7))
            // `YUMI_ISLAND_V2_ONLY=17,05` takes only the shots whose name starts so
            let only = (ProcessInfo.processInfo.environment["YUMI_ISLAND_V2_ONLY"] ?? "")
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for (name, setUp) in shots where only.isEmpty || only.contains(where: { name.hasPrefix($0) }) {
                rest()
                try? await Task.sleep(for: .seconds(1.2))
                setUp()
                try? await Task.sleep(for: .seconds(2.6))
                save(name)
            }
            for (key, value) in kept { defaults.set(value, forKey: key) }
            NSApp.terminate(nil)
        }
    }
}

/// What the Gmail shot asks of the Gmail sheet, which keeps its steps to itself.
enum StudioGmail {
    case choose(Int)
    case think
    case draft(String)
}

extension Notification.Name {
    /// Filming mode only: a step of the Gmail shot.
    static let yumiStudioGmail = AppIdentity.notification("studioGmail")
}
