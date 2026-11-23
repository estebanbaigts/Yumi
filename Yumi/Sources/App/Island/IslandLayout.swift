import CoreGraphics

// MARK: - The island's shapes and Yumi's seats

/// The shape the island has right now. `drip` and `greet` only exist during the launch,
/// `bye` during the goodbye.
enum IslandStage: String, CaseIterable {
    case hidden, compact, open, drip, greet, bye
    /// Folded, and a little larger: Yumi is saying something.
    case speak
}

/// Where Yumi sits (`SEATS` in the mock-up): the centre of his 100 × 84 box, as an offset
/// from the centre of the island and a distance from the top of the screen, and his scale.
struct IslandSeat: Equatable {
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var opacity: Double

    /// Side of the square frame given to `BotCanvasView`: his body, 84 units wide, takes
    /// 68.4 % of it (1.14 × the "diameter" of the layouts, which is 0.6 × the frame).
    static func frameSide(scale: CGFloat) -> CGFloat { 84 * scale / 0.684 }
}

/// Sizes and seats of the mock-up, fitted to the notch of this Mac.
struct IslandLayout: Equatable {
    var notchWidth: CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight
    /// A real notch hides whatever is drawn behind it; a screen without one shows everything.
    var hasNotch = false
    /// How far the folded island sticks out on each side of the notch. It grows with what is
    /// live on the right (see `FoldedIsland.ear`).
    var compactEar: CGFloat = IslandConst.compactExtra / 2
    /// Width of the island while Yumi speaks, and its height under the notch.
    var speakWidth: CGFloat = 0
    var speakBand: CGFloat = 0
    /// Width of the open island, in points: it follows the tab and the view (IslandOpenWidth).
    var openWidth: CGFloat = IslandConst.expandedWidth * IslandConst.openScale
    /// The slot the open view keeps for Yumi, in points from the island's top-left corner.
    /// nil until the open view has been laid out once.
    var openSlot: CGRect?

    /// The mock-up has a 32 pt notch. A taller one pushes the launch shapes down by the difference.
    var notchDelta: CGFloat { max(0, notchHeight - IslandConst.mockNotchHeight) }

    /// Open island: the mock-up starts its content 8 pt under the top edge, which a real notch
    /// would cover. The content then starts just under the notch instead.
    var openInset: CGFloat { hasNotch ? max(0, notchHeight + 8 - IslandConst.openPaddingTop * IslandConst.openScale) : 0 }

    /// The island moved to a screen (or the screen changed): only what the screen decides is
    /// taken. What the views measured stays, Yumi's slot first: a view that did not move never
    /// measures it again, and without it he would sit at the default seat, out of his card.
    mutating func fit(notchWidth: CGFloat, notchHeight: CGFloat, hasNotch: Bool) {
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        self.hasNotch = hasNotch
    }

    func size(_ stage: IslandStage, openHeight: CGFloat) -> CGSize {
        let l = IslandConst.launchScale
        switch stage {
        case .hidden:  return CGSize(width: notchWidth, height: notchHeight)
        case .compact: return CGSize(width: notchWidth + compactEar * 2, height: notchHeight)
        case .speak:   return CGSize(width: speakWidth, height: notchHeight + speakBand)
        case .open:    return CGSize(width: openWidth, height: openHeight)
        case .drip:    return CGSize(width: (notchWidth + IslandConst.dripExtra) * l, height: IslandConst.dripHeight * l + notchDelta)
        case .greet:   return CGSize(width: IslandConst.greetWidth * l, height: IslandConst.greetHeight * l + notchDelta)
        case .bye:     return CGSize(width: IslandConst.byeWidth * l, height: IslandConst.byeHeight * l + notchDelta)
        }
    }

    func cornerRadius(_ stage: IslandStage) -> CGFloat {
        switch stage {
        case .hidden, .compact: return IslandConst.roundedCorner
        case .speak:            return 20
        case .open:             return IslandConst.expandedCorner * IslandConst.openScale
        case .greet, .bye:      return IslandConst.expandedCorner * IslandConst.launchScale
        case .drip:             return IslandConst.dripCorner * IslandConst.launchScale
        }
    }

    /// `SEATS`: [x in the island, y, scale, opacity]. The rim width of each seat is the
    /// character's own business: it derives it from the size it is drawn at.
    func seat(_ stage: IslandStage) -> IslandSeat {
        let k = IslandConst.openScale, l = IslandConst.launchScale
        switch stage {
        case .hidden:
            return IslandSeat(x: 0, y: notchHeight / 2 - 2, scale: 0.05, opacity: 0)
        case .speak:
            return IslandSeat(x: 32 - speakWidth / 2, y: notchHeight + speakBand / 2 - 2, scale: 0.36, opacity: 1)
        case .compact:
            return IslandSeat(x: 28 - (notchWidth + compactEar * 2) / 2, y: notchHeight / 2, scale: 0.27, opacity: 1)
        case .open:
            guard let slot = openSlot else {
                return IslandSeat(x: 60 * k - openWidth / 2, y: 80 * k + openInset, scale: 0.68 * k, opacity: 1)
            }
            return IslandSeat(x: slot.midX - openWidth / 2, y: slot.midY, scale: slot.width / 100, opacity: 1)
        case .drip:
            return IslandSeat(x: 0, y: 62 * l + notchDelta, scale: 0.42 * l, opacity: 1)
        case .greet:
            return IslandSeat(x: (130 - IslandConst.greetWidth / 2) * l, y: 84 * l + notchDelta, scale: l, opacity: 1)
        case .bye:
            return IslandSeat(x: (150 - IslandConst.byeWidth / 2) * l, y: 62 * l + notchDelta, scale: 0.86 * l, opacity: 1)
        }
    }
}

// MARK: - Constants (sizes of design/maquette/reference.html)

enum IslandConst {
    static let notchWidth: CGFloat  = 184
    static let notchHeight: CGFloat = 32
    /// The compact island sticks out this much on both sides of the notch (344 for a 184 notch).
    static let compactExtra: CGFloat = 160
    /// Folded island, right of the notch: paddings, the colour dot, the longest live text,
    /// and the buttons that appear on hover.
    static let foldedLeading: CGFloat = 10
    static let foldedTrailing: CGFloat = 14
    static let foldedDot: CGFloat = 7
    static let foldedGap: CGFloat = 7
    static let foldedTextMax: CGFloat = 190
    static let foldedControl: CGFloat = 22
    static let foldedControlGap: CGFloat = 4
    /// Open island: 480 wide in the mock-up. On a real screen that frame is too tight around
    /// its content, so the island is wider and airier than the mock-up while its text stays
    /// close to the mock-up's size.
    static let expandedWidth: CGFloat = 600
    /// Zoom of what the open island and its second square contain (text, Yumi, buttons).
    /// The island is `expandedWidth × openScale` wide; the panel below has to stay wider.
    static let openScale: CGFloat = 0.85
    /// Zoom of the launch (the drop and the greeting).
    static let launchScale: CGFloat = 1.25
    static let openHeightDefault: CGFloat = 150
    static let openHeightMax: CGFloat = 380
    /// Left column of the open island: Yumi's seat and his caption.
    static let seatColumn: CGFloat = 92
    /// `.act { padding: 18px 22px 8px 0; min-height: 102px }`
    static let openPaddingTop: CGFloat = 18
    static let openPaddingBottom: CGFloat = 8
    static let openPaddingTrailing: CGFloat = 22
    static let actMinHeight: CGFloat = 76
    /// The notch of the mock-up. A taller real notch pushes the launch shapes down by the difference.
    static let mockNotchHeight: CGFloat = 32
    /// Launch: the drop under the notch, then the wide greeting.
    static let dripExtra: CGFloat = 12
    static let dripHeight: CGFloat = 102
    static let greetWidth: CGFloat = 260
    static let greetHeight: CGFloat = 150
    /// The goodbye: a little wider, Yumi in the middle.
    static let byeWidth: CGFloat = 300
    static let byeHeight: CGFloat = 132
    /// The second square, detached under the island.
    /// The bubble of the second activity, detached from the folded island.
    static let bubbleWidth: CGFloat = 34
    static let bubbleGap: CGFloat = 10

    static let roundedCorner: CGFloat = 14    // hidden and compact
    static let expandedCorner: CGFloat = 38   // open and greeting
    static let dripCorner: CGFloat = 80

    /// Size of the transparent panel the island lives in.
    static let panelWidth: CGFloat = 880
    static let panelHeight: CGFloat = 680
}
