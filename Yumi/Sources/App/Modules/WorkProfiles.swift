import Foundation

/// What the person mostly does on their Mac, asked once at the first launch: the modules they
/// start with follow it, and Yumi remembers it. Several can be chosen; "Autre" takes a word,
/// matched to the nearest profile. Pure.
struct WorkProfile: Equatable, Sendable, Identifiable {
    let id: String
    /// The modules, the five that go in the island first.
    let modules: [String]
    /// Lowercase word starts that point to this profile in a free answer ("boulang", "infirm").
    let keywords: [String]

    /// The button: "Je code".
    var label: String {
        switch id {
        case "code": loc("Je code")
        case "shop": loc("J'ai un commerce ou une boutique")
        case "field": loc("Je suis artisan ou sur le terrain")
        case "freelance": loc("Je suis freelance")
        case "office": loc("Je travaille en équipe, au bureau")
        case "create": loc("Je crée (design, illustration, photo)")
        case "video": loc("Je fais des vidéos ou du contenu")
        case "music": loc("Je fais de la musique")
        case "study": loc("J'étudie")
        case "teach": loc("J'enseigne")
        case "personal": loc("C'est surtout pour ma vie perso")
        default: loc("Un peu de tout")
        }
    }

    /// What Yumi keeps in his memory: "Tu codes."
    var memory: String {
        switch id {
        case "code": loc("Tu codes.")
        case "shop": loc("Tu as un commerce ou une boutique.")
        case "field": loc("Tu es artisan ou tu travailles sur le terrain.")
        case "freelance": loc("Tu es freelance.")
        case "office": loc("Tu travailles en équipe, au bureau.")
        case "create": loc("Tu fais de la création : design, illustration ou photo.")
        case "video": loc("Tu fais des vidéos ou du contenu.")
        case "music": loc("Tu fais de la musique.")
        case "study": loc("Tu fais des études.")
        case "teach": loc("Tu enseignes.")
        case "personal": loc("Tu utilises surtout ton Mac pour ta vie perso.")
        default: loc("Tu fais un peu de tout sur ton Mac.")
        }
    }
}

enum WorkProfiles {
    // Module identifiers (ModuleRegistry): the agents, GitHub, mail, calendar, notes and reminders,
    // weather, music, focus timer, Notion, screen time.
    private static let agents = "claude-code", github = "github", mail = "gmail", agenda = "agenda", notes = "notes",
                        weather = "weather", music = "music", focus = "focus", notion = "notion", screen = "screen-time"

    static let all: [WorkProfile] = [
        WorkProfile(id: "code", modules: [agents, github, focus, music, agenda, notes, weather, mail],
                    keywords: ["dev", "développ", "developp", "code", "codeu", "program", "informati", "logiciel", "data", "web", "ingénieur", "ingenieur", "devops"]),
        WorkProfile(id: "shop", modules: [mail, agenda, notes, weather, music, focus, screen],
                    keywords: ["boulang", "pâtiss", "patiss", "boutique", "magasin", "commer", "restaura", "café", "cafe", "bar",
                               "coiff", "fleur", "épic", "epic", "vendeu", "caiss", "traiteu", "boucher", "librair", "esthéti", "estheti"]),
        WorkProfile(id: "field", modules: [agenda, notes, weather, mail, music, focus],
                    keywords: ["artisan", "plomb", "électric", "electric", "menuis", "maçon", "macon", "chantier", "peintre en bâtiment",
                               "jardin", "paysag", "chauff", "livr", "infirm", "aide-soign", "kiné", "kine", "médecin", "medecin",
                               "pharmac", "santé", "sante", "agricult", "mécani", "mecani", "terrain", "btp", "facteu", "postier"]),
        WorkProfile(id: "freelance", modules: [mail, agenda, notes, focus, notion, music, weather],
                    keywords: ["freelance", "indépendant", "independant", "consultant", "auto-entrepreneu", "autoentrepreneu", "micro-entrepr"]),
        WorkProfile(id: "office", modules: [agenda, mail, notes, focus, screen, music, weather],
                    keywords: ["bureau", "équipe", "equipe", "manager", "rh", "ressources humaines", "comptab", "assistant", "commercial",
                               "chef de projet", "juriste", "avocat", "notaire", "banque", "assuran", "marketing", "administrat"]),
        WorkProfile(id: "create", modules: [music, focus, agenda, notes, notion, weather, mail],
                    keywords: ["design", "graphi", "illustr", "photo", "archi", "dessin", "peintre", "artiste", "styli"]),
        WorkProfile(id: "video", modules: [agenda, notes, music, focus, mail, notion, weather],
                    keywords: ["vidéo", "video", "youtube", "tiktok", "stream", "podcast", "influen", "contenu", "monteu", "réalisat",
                               "realisat", "twitch", "instagram"]),
        WorkProfile(id: "music", modules: [music, focus, agenda, notes, weather, mail],
                    keywords: ["musique", "musicien", "dj", "compos", "chant", "beatmak", "producteur", "productrice", "ingé son"]),
        WorkProfile(id: "study", modules: [agenda, notes, focus, music, screen, weather],
                    keywords: ["étudi", "etudi", "élève", "eleve", "fac", "lycée", "lycee", "école", "ecole", "master", "licence", "bts", "prépa", "prepa"]),
        WorkProfile(id: "teach", modules: [agenda, mail, notes, focus, weather, music],
                    keywords: ["prof", "enseign", "formateu", "formatrice", "instit", "maîtresse", "maitresse", "coach", "tuteu"]),
        WorkProfile(id: "personal", modules: [agenda, notes, weather, music, screen, mail],
                    keywords: ["perso", "retrait", "parent", "maman", "papa", "maison", "famille", "loisir"]),
        WorkProfile(id: "mix", modules: [agenda, mail, notes, weather, music, focus],
                    keywords: []),
    ]

    static func profile(_ id: String) -> WorkProfile? { all.first { $0.id == id } }

    /// The modules for the chosen profiles: their first modules come first, one profile after
    /// the other in the order of the list (work before personal life), then the rest. Only
    /// modules this build has, each once, at most `limit`.
    static func modules(for chosen: [WorkProfile], available: [String], limit: Int) -> [String] {
        let ordered = all.filter { profile in chosen.contains { $0.id == profile.id } }
        guard !ordered.isEmpty else { return [] }
        var result: [String] = []
        let depth = ordered.map(\.modules.count).max() ?? 0
        for rank in 0..<depth {
            for profile in ordered where rank < profile.modules.count {
                let id = profile.modules[rank]
                if available.contains(id), !result.contains(id) { result.append(id) }
            }
        }
        return Array(result.prefix(limit))
    }

    /// The profile a free answer points to ("boulangère" → shop), or nil when no word matches.
    static func match(_ text: String) -> WorkProfile? {
        let words = text.lowercased()
            .split { !$0.isLetter && $0 != "-" && $0 != "é" }
            .map(String.init)
        let whole = text.lowercased()
        // Several words ("chef de projet") first, then word starts.
        for profile in all {
            if profile.keywords.contains(where: { $0.contains(" ") && whole.contains($0) }) { return profile }
        }
        for profile in all {
            if words.contains(where: { word in profile.keywords.contains { !$0.contains(" ") && word.hasPrefix($0) } }) { return profile }
        }
        return nil
    }

    /// Profiles ticked in advance from what is on the Mac: a coding agent means "Je code".
    static func detected(codingAgentInstalled: Bool) -> [String] {
        codingAgentInstalled ? ["code"] : []
    }

    /// What Yumi keeps of a free answer, the person's own word: "Ton métier : boulangère."
    static func memory(ofFreeAnswer text: String) -> String? {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !clean.isEmpty else { return nil }
        return loc("Ton activité : \(String(clean.prefix(60))).")
    }
}
