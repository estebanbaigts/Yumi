import SwiftUI

// The open island's home, per tab (the bento of the island demo): Yumi sits in the large tile
// with the tab's lead module, the other modules fill the tiles beside it. A click on a tile
// makes it grow into its sheet; Yumi comes along and sits in the sheet.

/// The modules of a tab in tiles. The lead takes the large tile and Yumi with it.
struct IslandBento: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    let namespace: Namespace.ID

    /// The large tile: the module that says most about the tab, else the person's first one.
    static func lead(of ids: [String]) -> String? {
        // The person's order decides: the first tile of the tab is the large one
        ids.first
    }

    /// Height of a small tile; the large one is two of them and the gap.
    static let row: CGFloat = 96
    static let gap: CGFloat = 8
    /// Tiles beside the large one, before the rest go behind "Tout voir".
    static let sideLimit = 4
    static let moreID = "yumi-more"


    var body: some View {
        let ids = model.entries(in: model.category, modules: state.modules)
        let lead = ids.first
        let others = Self.side(Array(ids.dropFirst()))
        let big = Self.row * 2 + Self.gap
        HStack(alignment: .top, spacing: Self.gap) {
            if let lead {
                tile(lead, index: 0, lead: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: big)
            } else {
                YumiTile().frame(maxWidth: .infinity).frame(height: big)
            }
            if !others.isEmpty {
                side(others)
                    .frame(maxWidth: .infinity)
                    .frame(height: big)
            }
        }
        .animation(.islandSpring(0.5), value: ids)
    }

    /// At most four tiles beside the large one: past that, the last place opens "Tout voir".
    static func side(_ rest: [String]) -> [String] {
        guard rest.count > sideLimit else { return rest }
        return Array(rest.prefix(sideLimit - 1)) + [moreID]
    }

    /// The tiles beside the large one: one fills the column, two stack, three put the first
    /// across the top, four make a square.
    @ViewBuilder private func side(_ ids: [String]) -> some View {
        switch ids.count {
        case 1:
            tile(ids[0], index: 1)
        case 2:
            VStack(spacing: Self.gap) {
                tile(ids[0], index: 1).frame(height: Self.row)
                tile(ids[1], index: 2).frame(height: Self.row)
            }
        case 3:
            VStack(spacing: Self.gap) {
                tile(ids[0], index: 1).frame(height: Self.row)
                HStack(spacing: Self.gap) { tile(ids[1], index: 2); tile(ids[2], index: 3) }
                    .frame(height: Self.row)
            }
        default:
            VStack(spacing: Self.gap) {
                HStack(spacing: Self.gap) { tile(ids[0], index: 1); tile(ids[1], index: 2) }.frame(height: Self.row)
                HStack(spacing: Self.gap) { tile(ids[2], index: 3); tile(ids[3], index: 4) }.frame(height: Self.row)
            }
        }
    }

    @ViewBuilder private func tile(_ id: String, index: Int, lead: Bool = false) -> some View {
        if id == Self.moreID {
            let hidden = model.entries(in: model.category, modules: state.modules).count - Self.sideLimit
            MoreTile(count: hidden).riseIn(index, duration: 0.5, stagger: 0.055)
        } else {
            moduleTile(id, index: index, lead: lead)
        }
    }

    /// The tile a dragged one hovers.
    @State private var dropTarget: String?

    private func moduleTile(_ id: String, index: Int, lead: Bool) -> some View {
        let module = state.modules.first { $0.id == id }
        let movable = module != nil || id == IslandModel.tasksID
        let targeted = dropTarget == id
        return BentoTile(id: id, module: module, lead: lead, namespace: namespace)
            .riseIn(index, duration: 0.5, stagger: 0.055)
            // The place it is about to take sinks a little and lights up in its colour
            .scaleEffect(targeted ? 0.95 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder((module?.color ?? IslandTheme.violet).opacity(targeted ? 0.9 : 0), lineWidth: 2)
                    .shadow(color: (module?.color ?? IslandTheme.violet).opacity(targeted ? 0.6 : 0), radius: 10)
                    .allowsHitTesting(false)
            }
            .animation(.islandSpring(0.35), value: targeted)
            // Tiles glide to their new place instead of jumping
            .draggable(id) { DragChip(name: module?.name ?? loc("À faire"), symbol: module?.symbol ?? "checklist", color: module?.color ?? IslandTheme.amber) }
            .dropDestination(for: String.self) { ids, _ in
                guard movable, let moved = ids.first, moved != id else { return false }
                if moved == IslandModel.tasksID || id == IslandModel.tasksID {
                    return Self.moveTasks(moved: moved, on: id, in: model.category, state: state, model: model)
                }
                return Self.land(moved, on: id, in: model.category, state: state, model: model)
            } isTargeted: { on in
                if on, movable, dropTarget != id {
                    // Yumi watches where it goes
                    model.setMood(.curious)
                    model.pose(.pop)
                }
                dropTarget = on ? id : (dropTarget == id ? nil : dropTarget)
                if dropTarget == nil { model.setMood(nil) }
            }
    }

    /// The tasks tile changes place in the work tab: dropped on a module it takes its place,
    /// and a module dropped on it sends it to where that module was.
    @MainActor static func moveTasks(moved: String, on target: String?, in space: ModuleCategory,
                                     state: AppState, model: IslandModel) -> Bool {
        let tasks = IslandModel.tasksID
        let other = moved == tasks ? target : moved
        // The module that changes place with the tasks follows them into their space
        if moved != tasks, let other, state.modules.contains(where: { $0.id == other }) { ModuleSpaces.put(other, in: space) }
        let modules = state.modules.filter { $0.tab == space }.map(\.id)
        let place = other.flatMap { modules.firstIndex(of: $0) } ?? modules.count
        withAnimation(.islandSpring(0.55)) {
            model.tasksSpace = space
            model.tasksPlace = place
            state.objectWillChange.send()
        }
        celebrate(model)
        return true
    }

    @MainActor private static func celebrate(_ model: IslandModel) {
        SoundEngine.shared.play("pop")
        model.setMood(.happy)
        model.pose(.boing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.setMood(nil) }
    }

    /// A module put down on another of the tab takes its place; the others slide along.
    @MainActor static func land(_ moved: String, on target: String, in space: ModuleCategory,
                                state: AppState, model: IslandModel) -> Bool {
        let lineup = ModuleLineup.shared
        guard state.modules.contains(where: { $0.id == moved }),
              let index = lineup.selected.firstIndex(where: { $0.id == target }) else { return false }
        withAnimation(.islandSpring(0.55)) {
            ModuleSpaces.put(moved, in: space)
            lineup.move(moved, to: index)
            model.objectWillChange.send()
            state.objectWillChange.send()
        }
        SoundEngine.shared.play("pop")
        model.setMood(.happy)
        model.pose(.boing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.setMood(nil) }
        return true
    }
}

/// A tile: its colour glows in the corner, it lifts under the pointer, and grows into its
/// sheet when clicked.
struct BentoTile: View {
    let id: String
    let module: ModuleSnapshot?
    var lead = false
    let namespace: Namespace.ID
    @Environment(\.islandAccent) private var accent
    @State private var hover = false

    private var color: Color { module?.color ?? accent }

    var body: some View {
        Button { open() } label: {
            Group {
                if lead { LeadTileContent(id: id, module: module) } else { SmallTileContent(id: id, module: module) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, lead ? 12 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background {
                BentoSurface(color: color, lifted: hover, accent: accent)
                    .matchedGeometryEffect(id: "sheet-\(id)", in: namespace)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(TilePress())
        .frame(maxHeight: .infinity)
        .scaleEffect(hover ? 1.012 : 1)
        .offset(y: hover ? -1.5 : 0)
        .animation(.islandSpring(0.35), value: hover)
        .onHover { hover = $0 }
        .accessibilityLabel(loc("Ouvrir \(module?.name ?? loc("À faire"))"))
    }

    private func open() {
        withAnimation(.islandSpring(0.6)) { IslandActions.showModule(id) }
    }
}

/// Pressed, a tile sinks a little.
private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.islandSpring(0.25), value: configuration.isPressed)
    }
}

/// The ground of a tile and of the sheet it grows into: dark, the module's colour glowing
/// from the top right corner, the island colour round it when the pointer is on it.
struct BentoSurface: View {
    let color: Color
    var lifted = false
    var accent: Color = .clear

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: "#1B1B20"), Color(hex: "#141417")], startPoint: .topLeading, endPoint: .bottomTrailing))
            // A thin line of the module's colour along the top, nothing blurred behind the content
            .overlay(alignment: .top) {
                LinearGradient(colors: [color.opacity(0), color.opacity(0.7), color.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                    .padding(.horizontal, 22)
            }
            .overlay(shape.strokeBorder(lifted ? accent.opacity(0.6) : Color.white.opacity(0.075), lineWidth: 1))
            .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: 12, y: 6)
    }
}

// MARK: - What a tile shows

/// `.eyebrow`: the module's dot and its name, in small capitals.
struct BentoEyebrow: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text.uppercased())
                .font(IslandTheme.text(9.5, .bold))
                .tracking(0.8)
                .foregroundStyle(IslandTheme.muted)
                .lineLimit(1)
        }
    }
}

/// The large tile: Yumi, and the lead module beside him with its real elements.
private struct LeadTileContent: View {
    let id: String
    let module: ModuleSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BentoEyebrow(color: module?.color ?? IslandTheme.violet,
                         text: [module?.name ?? loc("À faire"), module?.status ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
            HStack(alignment: .center, spacing: 12) {
                YumiSlot(width: 66)
                if let module, module.id == IslandModel.agentModuleID, let first = module.rows.first {
                    SessionSteps(row: first)
                } else if let module {
                    ModuleTileBody(module: module, large: true)
                } else {
                    TasksSummary()
                }
            }
            Spacer(minLength: 0)
            if let module, module.id == IslandModel.agentModuleID, module.rows.count > 1 {
                HStack(spacing: 5) {
                    ForEach(module.rows.dropFirst().prefix(3)) { row in
                        SessionPill(row: row) {}
                            .allowsHitTesting(false)
                    }
                }
            }
        }
    }
}

/// A small tile: the module's name, then its real elements.
private struct SmallTileContent: View {
    let id: String
    let module: ModuleSnapshot?
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            BentoEyebrow(color: module?.color ?? IslandTheme.violet, text: module?.name ?? loc("À faire"))
            if let module {
                ModuleTileBody(module: module, large: large)
            } else {
                TasksSummary()
            }
            Spacer(minLength: 0)
        }
    }
}

/// The tasks tile: what it is for, and the shortcut that fills it.
private struct TasksSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc("Une idée, une tâche"))
                .font(IslandTheme.text(12.5, .semibold))
                .foregroundStyle(IslandTheme.fg)
            Text("⌥ Espace")
                .font(IslandTheme.mono(10.5))
                .foregroundStyle(IslandTheme.muted)
        }
    }
}

struct ProgressLine: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 4)
    }
}

/// The large tile when the tab has nothing: Yumi on his own.
private struct YumiTile: View {
    var body: some View {
        IslandCard {
            HStack(spacing: 12) {
                YumiSlot(width: 66)
                VStack(alignment: .leading, spacing: 3) {
                    ActTitle(text: loc("Je ne surveille rien pour l'instant."))
                    ActSub(text: loc("Choisis mes modules dans les réglages de l'app."))
                }
            }
        }
    }
}

// MARK: - The sheet a tile grows into

/// Back to the bento, and the module's name: on top of every sheet.
struct SheetHeader: View {
    let name: String
    let color: Color

    /// The way back lives in the frame of the island: here only the module's name, in its colour.
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(name.uppercased())
                .font(IslandTheme.text(11, .bold))
                .tracking(0.9)
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

/// What follows the pointer while a module is dragged: its icon and name, lifted.
struct DragChip: View {
    let name: String
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 7).fill(color.gradient))
            Text(name).font(IslandTheme.text(13, .semibold)).foregroundStyle(IslandTheme.fg)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(hex: "#1B1E2A")))
        .overlay(Capsule().strokeBorder(color.opacity(0.7), lineWidth: 1.2))
        .shadow(color: color.opacity(0.45), radius: 12, y: 4)
        .rotationEffect(.degrees(-3))
    }
}

/// The last small tile when a tab holds more modules than fit: it opens "Tout voir".
private struct MoreTile: View {
    let count: Int
    @State private var hover = false

    var body: some View {
        Button { withAnimation(.islandSpring(0.5)) { IslandActions.go(.apps) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "square.grid.2x2").font(.system(size: 14, weight: .semibold)).foregroundStyle(IslandTheme.muted)
                Spacer(minLength: 0)
                Text(loc("+\(count) autres")).font(IslandTheme.text(13, .semibold)).foregroundStyle(IslandTheme.fg)
                Text(loc("Tout voir")).font(IslandTheme.text(11, .regular)).foregroundStyle(IslandTheme.muted)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(hover ? 0.1 : 0.05)))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(loc("\(count) autres modules : tout voir"))
    }
}
