import Foundation

// MARK: - Module contract
// A module is one thing Yumi watches: Claude Code, the calendar, a timer, the weather.
// The core fills `AppState.modules` with snapshots; the island draws them. Both sides
// rely on this file, so neither edits it during the parallel work (see docs/journal.md).

/// What the island needs to draw one module, and nothing else.
struct ModuleSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    /// Shown in full in the island. No abbreviations.
    var name: String
    /// Hex colour, e.g. "#5B8CFF".
    var colorHex: String
    /// One or two words: "14:30", "2 sessions", "19°".
    var status: String
    /// Headline of the detail view: "Point produit dans 12 min".
    var title: String
    /// One line under the headline.
    var subtitle: String
    /// Label of the main button, and of the optional second one.
    var primaryAction: String
    var secondaryAction: String?
    /// True when the user should look now. The island may open by itself.
    var needsAttention: Bool = false
    /// What the folded island shows when this module has something going on right now.
    /// nil when nothing is happening. The folded island shows the live module with the
    /// highest priority; with none, it shows nothing on the right.
    var live: ModuleLive? = nil
    /// SF Symbol of this module in the island's rail and overview: "calendar", "music.note".
    var symbol: String = "circle.fill"
    /// SF Symbols of the main and second buttons where the island draws round buttons:
    /// "pause.fill", "forward.fill", "video.fill". nil lets the island pick a neutral arrow.
    var primarySymbol: String? = nil
    var secondarySymbol: String? = nil
    /// A bar the activity view can draw: a track playing, a timer running. nil without one.
    var progress: ModuleProgress? = nil
    /// Lines the activity view lists under the headline: one Claude Code session each, one pull
    /// request or one GitHub event each. Already in the order to show. Empty for most modules.
    var rows: [ModuleRow] = []
    /// Lines of the activity view's other pages, by page: "recent", "repos" for GitHub.
    /// Empty for most modules.
    var pages: [String: [ModuleRow]] = [:]
    /// The tab of the open island it belongs to. nil: the one its identifier gives
    /// (`ModuleCategory.of(moduleID:)`). The registry fills it from the module.
    var category: ModuleCategory? = nil
    /// The app it comes from, when it says so: "Spotify", "Musique".
    var source: String? = nil

    /// Where the island puts it.
    var tab: ModuleCategory { ModuleSpaces.chosen(id) ?? category ?? ModuleCategory.of(moduleID: id) }
}

/// One line of a module's list: a session, a pull request, an event.
struct ModuleRow: Identifiable, Equatable, Sendable {
    /// Stable while the thing it shows lives: a session id, "owner/name#12".
    let id: String
    /// "yumi", "Fix du repli".
    var title: String
    /// "modifie IslandRootView.swift", "louis", "étoile de lea".
    var detail: String
    var state: ModuleRowState
    /// The state in a few words: "travaille", "attend un accord", "CI rouge".
    var label: String
    /// Since when it is in this state, or when it happened. nil when unknown.
    var date: Date? = nil
    /// Heading of the group the line belongs to: "estebanbaigts/Yumi", "Derniers événements".
    /// nil keeps it with the line before.
    var section: String? = nil
    /// Sent back with `moduleRowAction` when the line is clicked. nil: the line is not a button.
    var action: String? = nil
    /// The button of an unfolded line, named after where it goes: "Ouvrir iTerm2". nil: a generic one.
    var actionLabel: String? = nil
    /// A count shown next to the state: "3/7" for the tasks of a Claude Code session. nil for none.
    var progress: String? = nil
    /// Lines shown when the line is unfolded: the request, the task, the last actions. Empty:
    /// the line does not unfold, a click sends `action` as before.
    var details: [String] = []
    /// A box to tick before the title: sent back with `moduleRowAction` when ticked. nil: none.
    var check: String? = nil
    /// For an agent's session: who it is ("Claude Code"), where it works (the repository's name,
    /// or the folder's when it is not one), the branch checked out there, and the model.
    var agent: String? = nil
    var place: String? = nil
    var isRepository = false
    var branch: String? = nil
    var model: String? = nil
}

/// How a line reads at a glance. The island picks the colour.
enum ModuleRowState: String, Equatable, Sendable {
    /// Nothing to report: an event, an open pull request without checks.
    case neutral
    /// Running: a session working, checks in progress.
    case busy
    /// Someone waits for the user: an answer, an approval, a review.
    case waiting
    /// Done well: a session finished, checks green.
    case success
    /// Done badly: a session in error, checks red.
    case failure
}

/// How far along something is, with the two labels at the ends of the bar.
struct ModuleProgress: Equatable, Sendable {
    /// 0 to 1.
    var fraction: Double
    /// Left label: "1:52".
    var leading: String
    /// Right label: "3:14".
    var trailing: String
}

/// Something happening now, small enough for the folded island.
struct ModuleLive: Equatable, Sendable {
    /// A few words: "Lueur · Halo Nord", "18:42", "14:30 Point produit".
    var text: String
    /// Higher wins. Use the values of `ModuleLivePriority`.
    var priority: Int
    /// Buttons the folded island shows on hover, two at most.
    var controls: [ModuleControl] = []
}

/// A button of the folded island. Pressing it posts `moduleAction` with `id` as the action.
struct ModuleControl: Identifiable, Equatable, Sendable {
    /// "primary" or "secondary", the same actions as the buttons of the detail view.
    let id: String
    /// SF Symbol name: "pause.fill", "play.fill", "forward.fill".
    var symbol: String
    /// Accessibility label: "Pause", "Suivant".
    var label: String
}

enum ModuleLivePriority {
    /// Good to know, nothing to do: the next event, the weather.
    static let ambient = 10
    /// Something running that the user started: music playing, a focus timer.
    static let activity = 50
    /// Someone is waiting for the user: an approval, a question.
    static let attention = 100
}

enum ModuleCatalog {
    /// Modules shown in the island itself; the others go in the second square.
    static let pinnedLimit = 5
    /// Modules the user can have selected at once.
    static let selectionLimit = 10

    /// Example data so the island can be built before the real modules exist.
    /// The core replaces `AppState.modules` with live snapshots.
    static let placeholders: [ModuleSnapshot] = [
        .init(id: "claude-code", name: "Claude Code", colorHex: "#FFB547", status: loc("2 sessions"), title: loc("yumi : écrit les tests"), subtitle: loc("2 sessions ouvertes, 1 attend ta réponse"), primaryAction: loc("Voir"), secondaryAction: loc("Ouvrir le terminal")),
        .init(id: "agenda", name: "Agenda", colorHex: "#5B8CFF", status: "14:30", title: loc("Point produit dans 12 min"), subtitle: loc("14:30 à 15:00, en visio"), primaryAction: loc("Rejoindre"), secondaryAction: loc("Voir la journée"),
              live: ModuleLive(text: loc("14:30 Point produit"), priority: ModuleLivePriority.ambient)),
        .init(id: "notes", name: "Notes", colorHex: "#F2C744", status: "3", title: loc("Dernière note"), subtitle: loc("Idée : mode nuit pour Yumi"), primaryAction: loc("Nouvelle note"), secondaryAction: loc("Tout voir")),
        .init(id: "focus", name: "Focus", colorHex: "#8B6CFF", status: "18:42", title: loc("Focus en cours"), subtitle: loc("Session 2 sur 4, reste 18 min 42"), primaryAction: loc("Pause"), secondaryAction: loc("Arrêter")),
        .init(id: "music", name: loc("Musique"), colorHex: "#F58AD9", status: loc("lecture"), title: loc("Lueur"), subtitle: loc("Halo Nord, Premières heures"), primaryAction: loc("Pause"), secondaryAction: loc("Suivant"),
              live: ModuleLive(text: loc("Lueur · Halo Nord"), priority: ModuleLivePriority.activity, controls: [
                  ModuleControl(id: "primary", symbol: "pause.fill", label: loc("Pause")),
                  ModuleControl(id: "secondary", symbol: "forward.fill", label: loc("Suivant")),
              ])),
        .init(id: "weather", name: loc("Météo"), colorHex: "#7FD0FF", status: "19°", title: loc("19° et des éclaircies"), subtitle: loc("Pluie vers 18 h, prends une veste"), primaryAction: loc("Détail"), secondaryAction: nil),
    ]
}

extension Notification.Name {
    /// Posted by the island when a module button is pressed.
    /// userInfo: ["module": String (module id), "action": String ("primary" or "secondary")]
    static let moduleAction = AppIdentity.notification("moduleAction")
    /// Posted by the island when a line of a module's list is clicked.
    /// userInfo: ["module": String (module id), "row": String (the row's `action`)]
    static let moduleRowAction = AppIdentity.notification("moduleRowAction")
    /// Posted by the first launch with the modules of the profiles the person chose.
    /// userInfo: ["modules": [String]]. Applied only while the modules were never chosen.
    static let profilesChosen = AppIdentity.notification("profilesChosen")
}
