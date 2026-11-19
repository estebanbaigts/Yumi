import CoreGraphics
import Foundation

// How the person dresses the island and Yumi: the colour of the open island, and what Yumi
// wears. Pure values, saved in the defaults; the island and the character read them.

/// The colour of the open island: its outline, its accents, and Yumi's rim at rest. The
/// colours of a state (an approval in orange, an error in red, done in green) stay on top.
enum IslandAccent: String, CaseIterable, Sendable {
    /// Yumi's own colours: his rim at rest is the blue, violet and pink of the concept sheet.
    case yumi, blue, pink, orange, green, sky, grey

    static let defaultsKey = "islandAccent"

    /// The colour of the swatch and of the accents, as 0xRRGGBB.
    var hex: UInt32 {
        switch self {
        case .yumi:   return 0x8B6CFF
        case .blue:   return 0x5B8CFF
        case .pink:   return 0xFF6FB5
        case .orange: return 0xFF9F0A
        case .green:  return 0x30D158
        case .sky:    return 0x64D2FF
        case .grey:   return 0xA1A1AA
        }
    }

    /// The three stops of Yumi's rim at rest, left to right, as 0xRRGGBB. The default keeps
    /// his own; another colour runs from itself to a touch of pink, then to a light tint
    /// (the `color-mix` of the demo).
    var restStops: [UInt32] {
        guard self != .yumi else { return [0x5B8CFF, 0x8B6CFF, 0xF58AD9] }
        return [hex, Self.mix(hex, 0xF58AD9, 0.4), Self.mix(hex, 0xFFFFFF, 0.65)]
    }

    /// `t` of the way from `a` to `b`, channel by channel.
    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }

    static func current(in defaults: UserDefaults = .standard) -> IslandAccent {
        defaults.string(forKey: defaultsKey).flatMap(IslandAccent.init(rawValue:)) ?? .yumi
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// What Yumi wears, on top of his habits and scenes. The head ones follow the top of his body,
/// the face ones follow his face.
enum YumiCostume: String, CaseIterable, Sendable {
    case none, beanie, crown, cat, witch, halo, flower, glasses, mustache, party, unicorn, antennae, bow, pirate

    static let defaultsKey = "yumiCostume"

    /// Worn on the head: it rides the top of the body as it squashes and stretches.
    var onHead: Bool {
        switch self {
        case .beanie, .crown, .cat, .witch, .halo, .flower, .party, .unicorn, .antennae, .bow, .pirate: return true
        case .none, .glasses, .mustache:                    return false
        }
    }

    /// Something on the face (the cat's whiskers, the glasses, the moustache).
    var onFace: Bool { self == .cat || self == .glasses || self == .mustache || self == .pirate }

    /// Every costume lives a little (a bounce, a glint, a twitch): Yumi keeps drawing while he wears one.
    var moves: Bool { self != .none }

    var label: String {
        switch self {
        case .none:     return loc("Aucun")
        case .beanie:   return loc("Bonnet")
        case .crown:    return loc("Couronne")
        case .cat:      return loc("Chat")
        case .witch:    return loc("Sorcière")
        case .halo:     return loc("Auréole")
        case .flower:   return loc("Fleur")
        case .glasses:  return loc("Lunettes rondes")
        case .mustache: return loc("Moustache")
        case .party:    return loc("Fête")
        case .unicorn:  return loc("Licorne")
        case .antennae: return loc("Antennes")
        case .bow:      return loc("Nœud")
        case .pirate:   return loc("Pirate")
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> YumiCostume {
        defaults.string(forKey: defaultsKey).flatMap(YumiCostume.init(rawValue:)) ?? .none
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// How wide the open island is, in the units of its content (before `IslandConst.openScale`).
/// It depends on what it shows: the work tab is the widest, the relax tab the narrowest. It
/// never gets so narrow that the tabs and the buttons on each side of the notch overlap it.
enum IslandOpenWidth: Equatable, Sendable {
    case tab(ModuleCategory)
    case chat, alert, settings

    /// The width the content asks for, before the notch is taken into account.
    var preferred: CGFloat {
        switch self {
        case .tab(.work):  return 640
        case .tab(.day):   return 560
        case .tab(.relax): return 540
        case .chat:        return 580
        case .alert:       return 680
        case .settings:    return 620
        }
    }

    /// What the menu bar row needs on each side of the notch: the three tabs on the left,
    /// the status and two buttons on the right.
    static let side: CGFloat = 250

    /// The width, in content units. `notch` is the notch's width in content units, 0 without one.
    func width(notch: CGFloat) -> CGFloat {
        max(preferred, notch + 2 * Self.side)
    }
}
