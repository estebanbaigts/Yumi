import SwiftUI

// The pieces of the open island in cards: the row of
// tabs in the height of the menu bar, the chips of the tab's modules, the dark cards, the
// sessions of Claude Code as small characters, and the place kept for Yumi.

// MARK: - The island's colour

private struct IslandAccentKey: EnvironmentKey {
    static let defaultValue = Color(hex: "#8B6CFF")
}

extension EnvironmentValues {
    /// The colour chosen in the settings: active tab, buttons, bars (IslandAccent).
    var islandAccent: Color {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}

extension IslandAccent {
    var color: Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    var label: String {
        switch self {
        case .yumi:   return "Yumi"
        case .blue:   return loc("Bleu")
        case .pink:   return loc("Rose")
        case .orange: return loc("Orange")
        case .green:  return loc("Vert")
        case .sky:    return loc("Ciel")
        case .grey:   return loc("Gris")
        }
    }
}

enum IslandCardTheme {
    static let card = Color(hex: "#161618")
    static let line = Color(hex: "#26262A")
    static let button = Color(hex: "#1C1C1E")
    static let chipLine = Color(hex: "#2C2C2E")
    static let mute = Color(hex: "#ADADB5")
}

// MARK: - Yumi's place

/// The coordinate space of the open island's content, before its zoom.
let islandOpenSpace = "islandOpen"

/// A space the size of Yumi's 100 × 84 box at `width`: he comes and sits there. It tells the
/// model where it is, so that he travels to it when the view changes.
struct YumiSlot: View {
    let width: CGFloat
    @ObservedObject private var model = IslandModel.shared
    @AppStorage(YumiCostume.defaultsKey) private var costume = YumiCostume.none.rawValue
    /// Who this slot is, among the ones on screen during a change of view.
    @State private var owner = UUID()

    /// Room kept above him for what he wears on his head (a hat, a horn, antennae): it never
    /// covers the text above the slot.
    private var headroom: CGFloat {
        (YumiCostume(rawValue: costume) ?? .none).onHead ? width * 0.36 : 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(width: width, height: headroom)
            Color.clear
                .frame(width: width, height: width * 0.84)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(islandOpenSpace)) } action: { rect in
                    model.seatSlot(owner, at: rect)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { IslandActions.pokeYumi(talking: AppState.shared.view == .prompt) }
        .onAppear { model.slotAppeared(owner) }
        .onDisappear { model.slotLeft(owner) }
        .accessibilityLabel("Yumi")
        .animation(.islandSpring(0.4), value: headroom)
    }
}

extension IslandModel {
    /// While one view gives way to another, both keep a place for Yumi for a moment: only the
    /// newest one decides where he sits, and the one leaving can never pull him back.
    func slotAppeared(_ owner: UUID) {
        YumiSlots.shared.order.removeAll { $0 == owner }
        YumiSlots.shared.order.append(owner)
        settle()
    }

    func slotLeft(_ owner: UUID) {
        YumiSlots.shared.order.removeAll { $0 == owner }
        YumiSlots.shared.rects[owner] = nil
        settle()
    }

    func seatSlot(_ owner: UUID, at rect: CGRect) {
        // A frame that is not real yet (zero size, nothing laid out) is not a seat
        guard rect.width > 1, rect.height > 1, rect.minX.isFinite, rect.minY.isFinite else { return }
        YumiSlots.shared.rects[owner] = rect
        settle()
    }

    /// Yumi sits in the newest slot still on screen.
    private func settle() {
        let slots = YumiSlots.shared
        guard let owner = slots.order.last(where: { slots.rects[$0] != nil }), let rect = slots.rects[owner] else { return }
        let k = IslandConst.openScale
        let slot = CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
        if layout.openSlot != slot { layout.openSlot = slot }
    }
}

/// The places kept for Yumi in the open island, newest last.
@MainActor
final class YumiSlots {
    static let shared = YumiSlots()
    var order: [UUID] = []
    var rects: [UUID: CGRect] = [:]
}

// MARK: - The row in the menu bar

/// Tabs on the left of the notch, what is going on and two buttons on its right. It takes the
/// height of the menu bar: the island gains none for it.
struct IslandTopBar: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let screen: IslandScreen
    let height: CGFloat
    @Environment(\.islandAccent) private var accent

    /// The tab lights up while one of its modules is on screen.
    private var tabShown: Bool { screen == .home || screen == .module || screen == .working }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.tabs(modules: state.modules), id: \.self) { tab in
                let on = tabShown && tab == model.category
                Button { IslandActions.showTab(tab) } label: {
                    Text(tab.label)
                        .font(IslandTheme.text(12.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.white : IslandCardTheme.mute)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(on ? accent.opacity(0.3) : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                // Where the tab is: the island's drop zone finds the space under the pointer
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(islandOpenSpace)) } action: { model.tabFrames[tab] = $0 }
                .overlay {
                    Capsule().strokeBorder(accent, lineWidth: 1.5).opacity(model.dropTab == tab ? 1 : 0)
                        .scaleEffect(model.dropTab == tab ? 1.06 : 0.9)
                        .animation(.islandSpring(0.3), value: model.dropTab)
                        .allowsHitTesting(false)
                }
            }
            Spacer(minLength: 8)
            if let status = IslandSessions.status(state.modules) {
                Text(status.text)
                    .font(IslandTheme.text(11.5, .medium))
                    .foregroundStyle(status.waiting ? IslandTheme.amber : IslandCardTheme.mute)
                    .lineLimit(1)
                    .padding(.trailing, 4)
            }
            IconCircle(symbol: "square.grid.2x2", label: loc("Tout voir"), on: screen == .apps) { IslandActions.go(.apps) }
            IconCircle(symbol: "pencil", label: loc("Parler à Yumi"), on: screen == .talk) { IslandActions.talk() }
            IconCircle(symbol: "gearshape", label: loc("Réglages"), on: screen == .settings) { IslandActions.go(.settings) }
        }
        .frame(height: height)
    }
}

/// `.ib`: a round button of the top row.
struct IconCircle: View {
    let symbol: String
    let label: String
    var on = false
    let action: () -> Void
    @Environment(\.islandAccent) private var accent
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on || hover ? Color.white : Color(hex: "#D1D1D6"))
                .frame(width: 24, height: 24)
                .background(Circle().fill(on ? accent : IslandCardTheme.button.opacity(hover ? 1.6 : 1)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips of the tab's modules

struct ModuleChips: View {
    let ids: [String]
    let current: String?
    let modules: [ModuleSnapshot]
    @Environment(\.islandAccent) private var accent

    private func name(_ id: String) -> String {
        id == IslandModel.tasksID ? loc("À faire") : modules.first { $0.id == id }?.name ?? id
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(ids, id: \.self) { id in
                let on = id == current
                Button { IslandActions.showModule(id) } label: {
                    Text(name(id))
                        .font(IslandTheme.text(11.5, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.white : IslandCardTheme.mute)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().strokeBorder(on ? accent : IslandCardTheme.chipLine, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Card

/// `.card`: dark and rounded inside the black island. `tint` washes its bottom with the colour
/// of what it says (an approval, a question, done, an error).
struct IslandCard<Content: View>: View {
    var tint: Color? = nil
    var padding: CGFloat = 12
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(stops: [.init(color: IslandCardTheme.card, location: 0.55),
                                                 .init(color: tint.map { $0.opacity(0.14) } ?? IslandCardTheme.card, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.map { $0.opacity(0.35) } ?? IslandCardTheme.line, lineWidth: 1))
    }
}

// MARK: - Small characters

/// `drawMini`: a session as a small character in its colour.
struct MiniYumi: View {
    let color: Color
    var size: CGFloat = 18
    var asleep = false

    var body: some View {
        Canvas { context, _ in
            var c = context
            c.scaleBy(x: size / 100, y: size / 100)
            YumiRenderer.drawMini(color: color, blink: 1, asleep: asleep, in: c)
        }
        .frame(width: size, height: size * 0.84)
        .accessibilityHidden(true)
    }
}

// MARK: - Claude Code sessions

@MainActor
enum IslandSessions {
    static let palette = ["#BF5AF2", "#FF9F0A", "#30D158", "#64D2FF", "#FF6FB5", "#5B8CFF"]

    /// A colour of its own for each session, the same at every opening.
    static func color(_ id: String) -> Color {
        let sum = id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: palette[sum % palette.count])
    }

    static func rows(_ modules: [ModuleSnapshot]) -> [ModuleRow] {
        modules.first { $0.id == IslandModel.agentModuleID }?.rows ?? []
    }

    /// "3 en cours", or "1 attend" in orange when a session waits for the person.
    static func status(_ modules: [ModuleSnapshot]) -> (text: String, waiting: Bool)? {
        let rows = rows(modules)
        let waiting = rows.filter { $0.state == .waiting }.count
        if waiting > 0 || AppState.shared.pendingApproval != nil {
            return (loc("\(max(waiting, 1)) attend"), true)
        }
        let busy = rows.filter { $0.state == .busy }.count
        return busy > 0 ? (loc("\(busy) en cours"), false) : nil
    }

    /// " · à toi", " · fini": what a pill adds after the name.
    static func suffix(_ row: ModuleRow) -> String {
        switch row.state {
        case .waiting: return loc(" · à toi")
        case .success: return loc(" · fini")
        case .failure: return loc(" · erreur")
        case .busy, .neutral: return ""
        }
    }
}

/// Claude Code in the work tab: Yumi large with the chosen session on the left, the other
/// sessions as coloured pills on the right.
struct ClaudeCodeCards: View {
    let module: ModuleSnapshot
    @ObservedObject var model: IslandModel

    var body: some View {
        let rows = module.rows
        let chosen = rows.first { $0.id == model.selectedSessionID } ?? rows.first
        HStack(alignment: .top, spacing: 10) {
            IslandCard {
                HStack(spacing: 14) {
                    YumiSlot(width: 74)
                    if let chosen {
                        SessionSteps(row: chosen).riseIn(0)
                    } else {
                        ModuleActivity(module: module)
                    }
                }
            }
            let others = rows.filter { $0.id != chosen?.id }
            if !others.isEmpty {
                IslandCard {
                    FlowLayout(spacing: 7) {
                        ForEach(others) { row in
                            SessionPill(row: row) { model.selectedSessionID = row.id; IslandActions.tap() }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .riseIn(1)
                }
                .frame(width: 214)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The session in the large card: its name, where it is, and its last steps.
struct SessionSteps: View {
    let row: ModuleRow

    private var color: Color {
        switch row.state {
        case .waiting: return IslandTheme.amber
        case .failure: return IslandTheme.red
        case .success: return IslandTheme.green
        case .busy, .neutral: return IslandSessions.color(row.id)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(row.title).font(IslandTheme.text(13, .semibold)).lineLimit(1)
                Text(row.progress.map { loc("étape \($0)") } ?? row.label)
                    .font(IslandTheme.text(12, .regular))
                    .foregroundStyle(IslandCardTheme.mute)
                    .lineLimit(1)
            }
            if !row.detail.isEmpty {
                line(symbol: "chevron.right", text: row.detail, bright: true)
            }
            ForEach(Array(row.details.prefix(2).enumerated()), id: \.offset) { _, text in
                line(symbol: "square", text: text, bright: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(symbol: String, text: String, bright: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 11)
            Text(text).lineLimit(1).truncationMode(.tail)
        }
        .font(IslandTheme.text(bright ? 12.5 : 11.5, bright ? .medium : .regular))
        .foregroundStyle(bright ? IslandTheme.fg : IslandCardTheme.mute)
    }
}

/// `.pill`: a small character in the session's colour, its name, and what it waits for.
struct SessionPill: View {
    let row: ModuleRow
    let action: () -> Void

    var body: some View {
        let color = IslandSessions.color(row.id)
        Button(action: action) {
            HStack(spacing: 6) {
                MiniYumi(color: color, size: 17, asleep: row.state == .neutral)
                Text(row.title + IslandSessions.suffix(row))
                    .font(IslandTheme.text(11.5, .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(color)
            .padding(.leading, 5)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.12)))
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.title + IslandSessions.suffix(row))
    }
}

/// The other sessions, beside a request that takes the whole width.
struct SessionColumn: View {
    let rows: [ModuleRow]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows.prefix(4)) { row in
                MiniYumi(color: IslandSessions.color(row.id), size: 22, asleep: row.state == .neutral)
                    .help(row.title + IslandSessions.suffix(row))
            }
        }
        .frame(width: 26)
    }
}

// MARK: - Flow

/// Lays its children in rows, going to the next row when one is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

// MARK: - Colour and costume in the settings

/// "Couleur": seven swatches.
struct AccentSwatches: View {
    @AppStorage(IslandAccent.defaultsKey) private var accent = IslandAccent.yumi.rawValue

    var body: some View {
        HStack(spacing: 7) {
            ForEach(IslandAccent.allCases, id: \.self) { choice in
                let on = accent == choice.rawValue
                Button {
                    accent = choice.rawValue
                    IslandActions.setAccent(choice)
                } label: {
                    Circle()
                        .fill(choice == .yumi
                              ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#5B8CFF"), Color(hex: "#8B6CFF"), Color(hex: "#F58AD9")],
                                                             startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(choice.color))
                        .frame(width: 17, height: 17)
                        .padding(2.5)
                        .overlay(Circle().strokeBorder(Color.white.opacity(on ? 1 : 0), lineWidth: 1.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(choice.label)
                .accessibilityLabel(loc("Couleur \(choice.label)"))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// "Skin": what he wears.
struct CostumeChips: View {
    /// All on one line (in a horizontal scroll), instead of wrapping.
    var oneRow = false
    @AppStorage(YumiCostume.defaultsKey) private var costume = YumiCostume.none.rawValue
    @Environment(\.islandAccent) private var accent

    var body: some View {
        if oneRow {
            HStack(spacing: 5) { chips }
        } else {
            FlowLayout(spacing: 5) { chips }
        }
    }

    @ViewBuilder private var chips: some View {
        Group {
            ForEach(YumiCostume.allCases, id: \.self) { choice in
                let on = costume == choice.rawValue
                Button {
                    costume = choice.rawValue
                    IslandActions.setCostume(choice)
                } label: {
                    Text(choice.label)
                        .font(IslandTheme.text(11, on ? .semibold : .medium))
                        .foregroundStyle(on ? Color.white : IslandCardTheme.mute)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3.5)
                        .overlay(Capsule().strokeBorder(on ? accent : IslandCardTheme.chipLine, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
