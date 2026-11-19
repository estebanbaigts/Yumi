import Foundation

/// The space (Travail, Journée, Détente) the person put a module in, by dragging it onto the
/// space's tab. It wins over the space the module says for itself.
enum ModuleSpaces {
    static let key = "modules.spaces"

    static func chosen(_ id: String, in defaults: UserDefaults = .standard) -> ModuleCategory? {
        (defaults.dictionary(forKey: key)?[id] as? String).flatMap(ModuleCategory.init(rawValue:))
    }

    static func put(_ id: String, in space: ModuleCategory, defaults: UserDefaults = .standard) {
        var all = defaults.dictionary(forKey: key) ?? [:]
        all[id] = space.rawValue
        defaults.set(all, forKey: key)
    }
}
