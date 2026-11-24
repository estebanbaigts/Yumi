import AppKit
import SwiftUI

// MARK: - The home of the open island (★ Proposition, `accueil`)
//
// Yumi sits in the middle, the modules turn round him on an ellipse. The wheel of the mouse
// spins them with some momentum, then they settle on the circle. In "Ranger" mode a module
// dropped on another swaps places with it, ✕ takes one away and + brings one back. The order
// is kept in the defaults.

enum IslandHomeOrder {
    static let key = "yumi.island.homeOrder"
    /// Every place the circle has offered, so a new one is added once and a removed one stays away.
    static let seenKey = "yumi.island.homeSeen"
    static let chatID = "yumi-chat"
    /// Yumi himself: his skins, his habits and his poses.
    static let characterID = "yumi-character"

    /// What can sit on the circle: the chat, then every module the person has.
    @MainActor static func known(_ modules: [ModuleSnapshot]) -> [String] {
        [chatID] + modules.map(\.id) + [characterID]
    }

    /// The order kept, without what no longer exists. Nothing kept yet: everything, in order.
    @MainActor static func ids(stored: String, modules: [ModuleSnapshot]) -> [String] {
        let known = known(modules)
        guard !stored.isEmpty else { return known }
        var kept = stored.split(separator: ",").map(String.init).filter { known.contains($0) }
        // What was never on the circle before (a module just turned on, Yumi himself) joins it
        // once; what the person took away since stays away
        let defaults = UserDefaults.standard
        let seen = Set(defaults.stringArray(forKey: seenKey) ?? stored.split(separator: ",").map(String.init))
        let new = known.filter { !seen.contains($0) && !kept.contains($0) }
        kept += new
        if !new.isEmpty || defaults.stringArray(forKey: seenKey) == nil {
            defaults.set(Array(seen.union(known)), forKey: seenKey)
        }
        return kept
    }

    static func encode(_ ids: [String]) -> String { ids.joined(separator: ",") }
}

/// The wheel of the home: its angle, its speed, and the step it settles on.
@MainActor
final class HomeSpin: ObservableObject {
    @Published var angle: Double = 0
    private var speed: Double = 0
    private var timer: Timer?
    /// Called once the wheel stops a whole number of steps away: the order turns by that many.
    var settled: ((Int) -> Void)?
    var count = 1
    var fast: Bool { abs(speed) > 0.06 }

    func push(_ delta: CGFloat) {
        speed = max(-0.35, min(0.35, speed + Double(delta) * 0.0009))
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        angle += speed
        speed *= 0.965
        guard abs(speed) < 0.004 else { return }
        // Slow enough: glide to the nearest place on the circle
        let step = 2 * Double.pi / Double(max(1, count))
        let target = (angle / step).rounded() * step
        let gap = target - angle
        if abs(gap) < 0.002 {
            let turns = -Int((target / step).rounded())
            angle = 0
            speed = 0
            timer?.invalidate()
            timer = nil
            settled?(turns)
        } else {
            angle += gap * 0.18
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        speed = 0
        angle = 0
    }
}

struct IslandHome: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    @AppStorage(IslandHomeOrder.key) private var stored = ""
    @StateObject private var spin = HomeSpin()
    @State private var wheel: Any?
    @State private var target: String?

    static let radiusX: CGFloat = 236
    static let radiusY: CGFloat = 88
    static let height: CGFloat = 250

    private var ids: [String] { IslandHomeOrder.ids(stored: stored, modules: state.modules) }
    private var hidden: [String] { IslandHomeOrder.known(state.modules).filter { !ids.contains($0) } }
    private var editing: Bool { model.editingModules }

    var body: some View {
        let list = ids
        ZStack {
            ForEach(Array(list.enumerated()), id: \.element) { index, id in
                let p = Self.place(index, of: list.count, turned: spin.angle)
                orb(id, compact: list.count > 9)
                    .offset(x: p.x, y: p.y + 2)
                    .riseIn(index, duration: 0.4, stagger: 0.035)
            }
            YumiSlot(width: 64)
                .offset(y: 6)
            if editing {
                VStack {
                    if !hidden.isEmpty { addRow }
                    Spacer()
                    Text(loc("Glisse un module sur un autre pour échanger leur place"))
                        .font(IslandTheme.text(11))
                        .foregroundStyle(IslandCardTheme.mute)
                        .allowsHitTesting(false)
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .animation(.islandSpring(0.5), value: list)
        .animation(.islandSpring(0.35), value: editing)
        .onAppear(perform: listen)
        .onDisappear(perform: quiet)
        .onChange(of: spin.fast) { _, fast in model.setMood(fast ? .surprised : nil) }
    }

    // MARK: A module on the circle

    /// Where the module `index` of `count` sits: spread at equal distances along the ellipse,
    /// not at equal angles, so they never pile up on its sides. `turned` is the wheel's turn,
    /// in steps of 2π / count.
    static func place(_ index: Int, of count: Int, turned: Double) -> CGPoint {
        let n = max(1, count)
        let samples = 360
        // Length of the ellipse from its top, sample by sample
        var lengths = [0.0]
        var last = point(at: -Double.pi / 2)
        for k in 1...samples {
            let next = point(at: -Double.pi / 2 + Double(k) / Double(samples) * 2 * .pi)
            lengths.append(lengths[k - 1] + hypot(next.x - last.x, next.y - last.y))
            last = next
        }
        let total = lengths[samples]
        let step = 2 * Double.pi / Double(n)
        var share = (Double(index) + turned / step) / Double(n)
        share -= share.rounded(.down)
        let wanted = share * total
        let k = min(samples, max(1, lengths.firstIndex { $0 >= wanted } ?? samples))
        let before = lengths[k - 1], after = lengths[k]
        let fraction = after > before ? (wanted - before) / (after - before) : 0
        return point(at: -Double.pi / 2 + (Double(k - 1) + fraction) / Double(samples) * 2 * .pi)
    }

    private static func point(at angle: Double) -> CGPoint {
        CGPoint(x: cos(angle) * radiusX, y: sin(angle) * radiusY)
    }

    private struct Item {
        let name: String
        let symbol: String
        let color: Color
        let value: String?
        let badge: Bool
    }

    private func item(_ id: String) -> Item {
        if id == IslandHomeOrder.chatID {
            return Item(name: loc("Chat"), symbol: "bubble.left.fill", color: Color(hex: "#8B6CFF"), value: nil, badge: false)
        }
        if id == IslandHomeOrder.characterID {
            return Item(name: "Yumi", symbol: "person.fill", color: Color(hex: "#C77DFF"), value: nil, badge: false)
        }
        let module = state.modules.first { $0.id == id }
        let status = module?.status ?? ""
        return Item(name: module?.name ?? id, symbol: module?.symbol ?? "circle.fill",
                    color: module?.color ?? IslandTheme.violet,
                    value: status.isEmpty || status.count > 9 ? nil : status,
                    badge: module?.needsAttention ?? false)
    }

    private func orb(_ id: String, compact: Bool) -> some View {
        let it = item(id)
        let lit = target == id
        let side: CGFloat = compact ? 32 : 38
        return VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: it.symbol)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(it.color)
                    .frame(width: side, height: side)
                    .background(Circle().fill(it.color.opacity(0.14)))
                    .overlay(Circle().strokeBorder(it.color.opacity(lit ? 0.95 : 0.34), lineWidth: lit ? 2 : 1))
                    .shadow(color: it.color.opacity(lit ? 0.6 : 0), radius: 8)
                if it.badge && !editing {
                    Circle().fill(IslandTheme.amber).frame(width: 10, height: 10).offset(x: 3, y: -2)
                }
            }
            Text(it.name)
                .font(IslandTheme.text(compact ? 10 : 11, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let value = it.value, !compact {
                Text(value)
                    .font(IslandTheme.text(10).monospacedDigit())
                    .foregroundStyle(IslandCardTheme.mute)
                    .lineLimit(1)
            }
        }
        .frame(width: compact ? 68 : 80, height: compact ? 56 : 70, alignment: .top)
        .overlay(alignment: .topLeading) {
            if editing {
                // A tap here wins over picking the module up: it can be removed from anywhere
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .heavy))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color(hex: "#3A3A3C")))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
                    .highPriorityGesture(TapGesture().onEnded { remove(id) })
                    .offset(x: compact ? 4 : 8, y: -11)
                    .zIndex(2)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(loc("Retirer \(it.name)"))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(lit ? 1.08 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if !editing { open(id) } }
        .modifier(HomeArrange(id: id, enabled: editing, name: it.name, symbol: it.symbol, color: it.color,
                              target: $target, swap: swap))
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(it.name)
    }

    private var addRow: some View {
        HStack(spacing: 6) {
            ForEach(hidden, id: \.self) { id in
                Button { add(id) } label: {
                    Text("+ \(item(id).name)")
                        .font(IslandTheme.text(11, .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .offset(y: -6)
    }

    // MARK: Actions

    private func open(_ id: String) {
        if id == IslandHomeOrder.chatID {
            IslandActions.talk()
        } else if id == IslandHomeOrder.characterID {
            IslandModel.shared.selectedModuleID = id
            withAnimation(.islandSpring(0.6)) { IslandActions.go(.module) }
        } else {
            withAnimation(.islandSpring(0.6)) { IslandActions.showModule(id) }
        }
    }

    private func save(_ list: [String]) {
        stored = IslandHomeOrder.encode(list)
    }

    private func remove(_ id: String) {
        save(ids.filter { $0 != id })
        SoundEngine.shared.play("pop")
    }

    private func add(_ id: String) {
        save(ids + [id])
        SoundEngine.shared.play("pop")
        model.pose(.boing)
    }

    private func swap(_ moved: String, _ other: String) {
        var list = ids
        guard let a = list.firstIndex(of: moved), let b = list.firstIndex(of: other), a != b else { return }
        list.swapAt(a, b)
        withAnimation(.islandSpring(0.55)) { save(list) }
        SoundEngine.shared.play("pop")
        model.setMood(.happy)
        model.pose(.boing)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { model.setMood(nil) }
    }

    // MARK: The wheel

    private func listen() {
        spin.settled = { turns in
            // Read again: what the view held when it appeared may be older than a removal
            let list = IslandHomeOrder.ids(stored: UserDefaults.standard.string(forKey: IslandHomeOrder.key) ?? "",
                                           modules: AppState.shared.modules)
            guard !list.isEmpty else { return }
            let r = ((turns % list.count) + list.count) % list.count
            if r != 0 { save(Array(list[r...] + list[..<r])) }
            model.setMood(nil)
        }
        guard wheel == nil else { return }
        wheel = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated {
                if !model.editingModules {
                    spin.count = IslandHomeOrder.ids(stored: UserDefaults.standard.string(forKey: IslandHomeOrder.key) ?? "",
                                                     modules: AppState.shared.modules).count
                    spin.push(event.scrollingDeltaY + event.scrollingDeltaX)
                }
            }
            return event
        }
    }

    private func quiet() {
        if let wheel { NSEvent.removeMonitor(wheel) }
        wheel = nil
        spin.stop()
        if model.editingModules { model.editingModules = false }
    }
}

/// In "Ranger" mode a module can be picked up and dropped on another.
private struct HomeArrange: ViewModifier {
    let id: String
    let enabled: Bool
    let name: String
    let symbol: String
    let color: Color
    @Binding var target: String?
    let swap: (String, String) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(id) { DragChip(name: name, symbol: symbol, color: color) }
                .dropDestination(for: String.self) { items, _ in
                    target = nil
                    guard let moved = items.first, moved != id else { return false }
                    swap(moved, id)
                    return true
                } isTargeted: { on in
                    if on { target = id } else if target == id { target = nil }
                }
        } else {
            content
        }
    }
}
