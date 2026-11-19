import SwiftUI

// Where am I, and how do I go back: the trail on top of every view that is not the home,
// the grid of every module ("Tout voir"), the home's one sentence, and the past conversations.

// MARK: - The trail: ‹ Accueil · Mail

struct BackTrail: View {
    let title: String
    var color: Color? = nil
    /// Where "‹" goes: the home, or the view the trail names first.
    var back: IslandView = .overview
    var backLabel: String = loc("Accueil")
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.islandSpring(0.5)) { IslandActions.go(back) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10.5, weight: .bold))
                    Text(backLabel).font(IslandTheme.text(12, .semibold))
                }
                .foregroundStyle(hover ? Color.white : IslandTheme.muted)
                .padding(.leading, 6)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(hover ? 0.12 : 0.06)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .help(loc("Revenir : \(backLabel)"))
            .accessibilityLabel(loc("Revenir : \(backLabel)"))

            if let color { Circle().fill(color).frame(width: 6, height: 6) }
            Text(title)
                .font(IslandTheme.text(12, .semibold))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Tout voir: every module, the tasks, the memory and the conversations

struct AllModulesGrid: View {
    @ObservedObject var state: AppState

    private struct Entry: Identifiable {
        let id: String
        let name: String
        let status: String
        let symbol: String
        let color: Color
        let open: @MainActor () -> Void
    }

    private var entries: [Entry] {
        var out = state.modules.map { module in
            Entry(id: module.id, name: module.name, status: module.status, symbol: module.symbol, color: module.color) {
                IslandActions.showModule(module.id)
            }
        }
        out.append(Entry(id: IslandModel.tasksID, name: loc("Tâches"), status: "", symbol: "checklist", color: IslandTheme.amber) {
            IslandActions.showModule(IslandModel.tasksID)
        })
        out.append(Entry(id: "talk", name: loc("Conversations"), status: ChatArchiveStore.shared.chats.isEmpty ? "" : "\(ChatArchiveStore.shared.chats.count)",
                         symbol: "bubble.left.and.bubble.right.fill", color: IslandTheme.pink) {
            IslandModel.shared.showChatHistory = true
            IslandActions.talk()
        })
        out.append(Entry(id: "memory", name: loc("Mémoire"), status: state.memory.isEmpty ? "" : "\(state.memory.count)",
                         symbol: "brain.head.profile", color: IslandTheme.violet) {
            IslandActions.go(.memory)
        })
        return out
    }

    /// The module or the space a dragged one hovers, lit to show where it lands.
    @State private var dropTarget: String?

    /// A dragged module lands: in the space it was dropped in, at the place of the module it
    /// was dropped on (or at the end of that space).
    private func land(_ moved: String, in space: ModuleCategory, on target: String?) -> Bool {
        let lineup = ModuleLineup.shared
        let tasks = IslandModel.tasksID
        if moved == tasks || target == tasks {
            guard moved != target else { return false }
            return IslandBento.moveTasks(moved: moved, on: target, in: space, state: state, model: IslandModel.shared)
        }
        guard state.modules.contains(where: { $0.id == moved }), moved != target else { return false }
        withAnimation(.islandSpring(0.45)) {
            ModuleSpaces.put(moved, in: space)
            if let target, let index = lineup.selected.firstIndex(where: { $0.id == target }) {
                lineup.move(moved, to: index)
            }
            IslandModel.shared.objectWillChange.send()
            state.objectWillChange.send()
        }
        SoundEngine.shared.play("pop")
        IslandModel.shared.setMood(.happy)
        IslandModel.shared.pose(.boing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { IslandModel.shared.setMood(nil) }
        return true
    }

    private func cell(_ entry: Entry, space: ModuleCategory?) -> some View {
        let cell = ModuleCell(name: entry.name, status: entry.status, symbol: entry.symbol, color: entry.color,
                              target: dropTarget == entry.id, action: entry.open)
        return Group {
            if let space {
                cell
                    .draggable(entry.id) { DragChip(name: entry.name, symbol: entry.symbol, color: entry.color) }
                    .dropDestination(for: String.self) { ids, _ in
                        ids.first.map { land($0, in: space, on: entry.id) } ?? false
                    } isTargeted: { on in
                        dropTarget = on ? entry.id : (dropTarget == entry.id ? nil : dropTarget)
                    }
                    .accessibilityAction(named: loc("Avancer")) { ModuleLineup.shared.nudge(entry.id, by: -1) }
                    .accessibilityAction(named: loc("Reculer")) { ModuleLineup.shared.nudge(entry.id, by: 1) }
            } else {
                cell
            }
        }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    @State private var gridHeight: CGFloat = 0
    /// Past this, the spaces scroll: the island keeps room for the trail and the line under.
    static let gridLimit: CGFloat = 250

    /// One space: its name, its modules, and room to drop one more.
    private func section(_ space: ModuleCategory) -> some View {
        let order = IslandModel.shared.entries(in: space, modules: state.modules)
        let shown = order.compactMap { id in entries.first { $0.id == id } }
        let lit = dropTarget == "space-" + space.rawValue
        return VStack(alignment: .leading, spacing: 6) {
            Text(space.label).font(IslandTheme.text(12, .semibold)).foregroundStyle(IslandTheme.muted).padding(.leading, 2)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(shown) { entry in cell(entry, space: space) }
                if shown.isEmpty {
                    Text(loc("Glisse un module ici"))
                        .font(IslandTheme.text(11.5, .regular)).foregroundStyle(IslandTheme.muted)
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(lit ? 0.08 : 0)))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(IslandTheme.violet.opacity(lit ? 0.8 : 0), lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .dropDestination(for: String.self) { ids, _ in
            ids.first.map { land($0, in: space, on: nil) } ?? false
        } isTargeted: { on in
            let key = "space-" + space.rawValue
            dropTarget = on ? key : (dropTarget == key ? nil : dropTarget)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            YumiSlot(width: 52)
            VStack(alignment: .leading, spacing: 6) {
              // Everything scrolls past the island's height, so no module is ever cut off
              ScrollView(.vertical, showsIndicators: true) {
               VStack(alignment: .leading, spacing: 6) {
                ForEach(ModuleCategory.allCases, id: \.self) { space in section(space) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(loc("Toi")).font(IslandTheme.text(12, .semibold)).foregroundStyle(IslandTheme.muted).padding(.leading, 2)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(entries.filter { e in e.id != IslandModel.tasksID && !state.modules.contains { $0.id == e.id } }) { entry in cell(entry, space: nil) }
                    }
                }
                .padding(6)
               }
               .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { gridHeight = $0 }
              }
              .frame(height: min(max(gridHeight, 1), Self.gridLimit))
                HStack(spacing: 12) {
                    ActSub(text: loc("Glisse un module dans un autre espace, ou sur un autre pour changer l'ordre."), lines: 2)
                    Spacer(minLength: 0)
                    TextButton(label: loc("Ajouter ou retirer…")) { IslandActions.openSettings(.modules) }
                }
                .padding(.horizontal, 6)
            }
        }
    }
}

private struct ModuleCell: View {
    let name: String
    let status: String
    let symbol: String
    let color: Color
    var target = false
    let action: @MainActor () -> Void
    @State private var hover = false

    var body: some View {
        Button { action() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(color.gradient))
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(IslandTheme.text(12, .semibold)).foregroundStyle(IslandTheme.fg).lineLimit(1)
                    if !status.isEmpty {
                        Text(status).font(IslandTheme.text(11, .regular)).foregroundStyle(IslandTheme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(hover || target ? 0.12 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(color, lineWidth: target ? 1.5 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(status.isEmpty ? name : "\(name), \(status)")
    }
}

// MARK: - The past conversations, in the chat

struct ChatHistoryList: View {
    @ObservedObject private var store = ChatArchiveStore.shared
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.chats.isEmpty {
                ActSub(text: loc("Tes conversations passées s'afficheront ici."))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(store.chats) { chat in
                            HistoryRow(chat: chat) {
                                IslandActions.resume(chat)
                                close()
                            } remove: {
                                store.remove(chat.id)
                            }
                        }
                    }
                }
                .frame(maxHeight: 170)
            }
        }
    }
}

private struct HistoryRow: View {
    let chat: SavedChat
    let open: () -> Void
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    Text(chat.title.isEmpty ? loc("Conversation") : chat.title)
                        .font(IslandTheme.text(12.5, .medium))
                        .foregroundStyle(IslandTheme.fg)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(chat.date.formatted(.relative(presentation: .named)))
                        .font(IslandTheme.text(11, .regular))
                        .foregroundStyle(IslandTheme.muted)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(loc("Reprendre : \(chat.title)"))
            Button(action: remove) {
                Image(systemName: "trash").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(IslandTheme.muted)
            }
            .buttonStyle(.plain)
            .opacity(hover ? 1 : 0)
            .help(loc("Oublier cette conversation"))
            .accessibilityLabel(loc("Oublier cette conversation"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.08 : 0)))
        .onHover { hover = $0 }
    }
}
