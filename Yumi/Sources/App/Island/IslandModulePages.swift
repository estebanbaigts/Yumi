import SwiftUI

// MARK: - The pages of the modules (★ Proposition, `m:*`)
//
// One thing at a time, laid straight on the island (no card): a small heading in the module's
// colour, then what the module says. The frame around (‹ Accueil, ×, halo) is IslandFrameBar.

/// `modHead`: a square icon in the module's colour, its name in small capitals, something on the right.
struct ModHead<Trailing: View>: View {
    let symbol: String
    let title: String
    let color: Color
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(color.opacity(0.15)))
            Text(title.uppercased())
                .font(IslandTheme.text(11, .bold))
                .tracking(0.9)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.bottom, 12)
    }
}

extension ModHead where Trailing == EmptyView {
    init(symbol: String, title: String, color: Color) {
        self.init(symbol: symbol, title: title, color: color) { EmptyView() }
    }
}

/// The page of a module, picked by its identifier.
struct ModulePage: View {
    let module: ModuleSnapshot

    var body: some View {
        Group {
            switch module.id {
            case "agenda":  AgendaPage(module: module)
            case "music":   MusicPage(module: module)
            case "weather": WeatherPage(module: module)
            case "focus":   FocusPage(module: module)
            case "github":  GitHubPage2(module: module)
            case IslandModel.agentModuleID: AgentsPage(module: module)
            case "gmail":
                VStack(alignment: .leading, spacing: 0) {
                    ModHead(symbol: "envelope.fill", title: module.status.isEmpty ? loc("Mail") : loc("Mail · \(module.status)"), color: Color(hex: "#6FB4FF")) { YumiSlot(width: 40) }
                    GmailSheet()
                }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    ModHead(symbol: module.symbol, title: module.name, color: module.color)
                    HStack(spacing: 14) { YumiSlot(width: 60); ModuleActivity(module: module) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .frame(height: IslandHome.height, alignment: .top)
        .clipped()
    }
}

// MARK: Agenda

private struct AgendaPage: View {
    let module: ModuleSnapshot
    private let coral = Color(hex: "#FF8A7A")
    private static let palette = ["#8B9CFF", "#FF8A7A", "#F2B36B", "#3DDC97", "#7FD8FF", "#C77DFF"]

    private var dayTitle: String {
        loc("Aujourd'hui · \(Date.now.formatted(.dateTime.weekday(.wide).day()))")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "calendar", title: dayTitle, color: coral) { YumiSlot(width: 40) }
                if module.rows.isEmpty {
                    Text(module.title).font(IslandTheme.text(14, .semibold))
                    Text(module.subtitle).font(IslandTheme.text(12)).foregroundStyle(IslandCardTheme.mute)
                    // No access yet: the button that asks for it, right here
                    if [loc("Autoriser"), loc("Ouvrir les réglages")].contains(module.primaryAction) {
                        Button { IslandActions.module(module.id, "primary") } label: {
                            Text(module.primaryAction)
                                .font(IslandTheme.text(12.5, .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 14)
                                .frame(height: 32)
                                .background(Capsule().fill(coral))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                } else {
                    ForEach(Array(module.rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                        line(row, color: Color(hex: Self.palette[index % Self.palette.count]))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "calendar", title: loc("La semaine"), color: Color(hex: "#8E8E93"))
                ForEach(module.pages["week"] ?? []) { day in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(day.title).font(IslandTheme.text(12, .bold))
                            Spacer()
                            Text(day.label).font(IslandTheme.text(12)).foregroundStyle(Color(hex: "#8E8E93"))
                        }
                        Text(day.detail).font(IslandTheme.text(11)).foregroundStyle(Color(hex: "#B9BCC8")).lineLimit(1)
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                }
            }
            .frame(width: 170, alignment: .leading)
            .padding(.leading, 18)
            .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
        }
    }

    private func line(_ row: ModuleRow, color: Color) -> some View {
        let next = row.state == .waiting
        let past = row.state == .success
        return HStack(spacing: 12) {
            Text(row.detail).font(IslandTheme.text(13, .bold).monospacedDigit()).frame(width: 42, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3, height: 18)
            Text(row.title).font(IslandTheme.text(13)).lineLimit(1)
            Spacer(minLength: 6)
            if next {
                if !row.label.isEmpty { Text(row.label).font(IslandTheme.text(11.5)).foregroundStyle(color) }
                Button { IslandActions.module(module.id, "primary") } label: {
                    Text(module.primaryAction)
                        .font(IslandTheme.text(11.5, .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .overlay(Capsule().strokeBorder(color, lineWidth: 1.4))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background {
            if next {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.33)))
            }
        }
        .opacity(past ? 0.4 : 1)
    }
}

// MARK: Music

private struct MusicPage: View {
    let module: ModuleSnapshot
    private let pink = Color(hex: "#FF6FA8")

    var body: some View {
        HStack(spacing: 26) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [pink, Color(hex: "#8B6CFF")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 120, height: 120)
                .shadow(color: pink.opacity(0.33), radius: 15, y: 10)
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "music.note", title: module.source.map { "\(loc("Musique")) · \($0)" } ?? loc("Musique"), color: pink)
                Text(module.title).font(.system(size: 30, weight: .bold)).lineLimit(1)
                Text(module.subtitle.replacingOccurrences(of: ", ", with: " · "))
                    .font(IslandTheme.text(13)).foregroundStyle(Color(hex: "#B9BCC8")).lineLimit(1)
                if let progress = module.progress {
                    HStack(spacing: 8) {
                        Text(progress.leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.12))
                                .overlay(alignment: .leading) { Capsule().fill(pink).frame(width: geo.size.width * progress.fraction) }
                        }
                        .frame(height: 4)
                        Text(progress.trailing)
                    }
                    .font(IslandTheme.text(11).monospacedDigit())
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .padding(.top, 14)
                }
                HStack(spacing: 14) {
                    round("backward.end.fill", size: 38, fill: Color.white.opacity(0.1), label: loc("Morceau précédent")) { IslandActions.module(module.id, "previous") }
                    round(module.primarySymbol ?? "pause.fill", size: 48, fill: pink, label: module.primaryAction) { IslandActions.module(module.id, "primary") }
                    round("forward.end.fill", size: 38, fill: Color.white.opacity(0.1), label: loc("Morceau suivant")) { IslandActions.module(module.id, "secondary") }
                }
                .padding(.top, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            YumiSlot(width: 70)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    private func round(_ symbol: String, size: CGFloat, fill: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: Focus

private struct FocusPage: View {
    let module: ModuleSnapshot
    private let amber = Color(hex: "#F2B36B")

    var body: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "timer", title: loc("Focus"), color: amber)
                Text(module.progress?.leading ?? module.status)
                    .font(.system(size: 52, weight: .bold).monospacedDigit())
                Text(module.subtitle).font(IslandTheme.text(13)).foregroundStyle(Color(hex: "#B9BCC8")).padding(.top, 6)
                if module.progress != nil {
                    // Running: one button to stop, as in the workshop
                    Button { IslandActions.module(module.id, "primary") } label: {
                        Text(module.primaryAction)
                            .font(IslandTheme.text(13, .semibold))
                            .padding(.horizontal, 20)
                            .frame(height: 38)
                            .overlay(Capsule().strokeBorder(amber, lineWidth: 1.6))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                } else {
                    FocusLengthPicker().padding(.top, 16)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            YumiSlot(width: 86)
        }
        .padding(.horizontal, 20)
    }
}

// MARK: GitHub

private enum GitHubTab: String, CaseIterable {
    case activity, repos, contributions, compact

    var label: String {
        switch self {
        case .activity:      return loc("Activité")
        case .repos:         return loc("Repos")
        case .contributions: return loc("Contributions")
        case .compact:       return loc("Tout (compact)")
        }
    }
}

private struct GitHubPage2: View {
    let module: ModuleSnapshot
    @AppStorage("island.github.tab") private var stored = GitHubTab.activity.rawValue

    private var tab: GitHubTab { GitHubTab(rawValue: stored) ?? .activity }
    private var activity: [ModuleRow] { (module.pages["recent"] ?? []) + (module.pages["pulls"] ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModHead(symbol: "arrow.triangle.branch", title: "GitHub", color: Color(hex: "#C9D1D9")) { HStack(spacing: 10) { tabs; YumiSlot(width: 40) } }
            Group {
                switch tab {
                case .activity:      scrolling(activity)
                case .repos:         scrolling(module.pages["repos"] ?? [])
                case .contributions: IslandContributions(cell: 9, gap: 2.5).padding(.top, 14)
                case .compact:
                    // Everything at once, scrolling: the grid, then the activity and the repositories
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            IslandContributions(cell: 7, gap: 2)
                            HStack(alignment: .top, spacing: 20) {
                                list(activity, limit: activity.count, big: false).frame(maxWidth: .infinity)
                                list(module.pages["repos"] ?? [], limit: (module.pages["repos"] ?? []).count, big: false)
                                    .frame(width: 170)
                                    .padding(.leading, 18)
                                    .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1) }
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
            .id(tab)
            .transition(.opacity.combined(with: .offset(y: 6)))
        }
        .animation(.easeOut(duration: 0.3), value: stored)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(GitHubTab.allCases, id: \.self) { each in
                Button { stored = each.rawValue } label: {
                    Text(each.label)
                        .font(IslandTheme.text(11.5, .semibold))
                        .foregroundStyle(each == tab ? Color.black : Color(hex: "#B9BCC8"))
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(Capsule().fill(each == tab ? Color.white : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    /// Every line, scrolling under the heading: the older pushes, commits and pull requests too.
    @ViewBuilder private func scrolling(_ rows: [ModuleRow]) -> some View {
        if rows.isEmpty {
            list(rows, limit: 0, big: true)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                list(rows, limit: rows.count, big: true)
                    .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder private func list(_ rows: [ModuleRow], limit: Int, big: Bool) -> some View {
        if rows.isEmpty {
            Text(loc("Rien de récent.")).font(IslandTheme.text(12)).foregroundStyle(IslandCardTheme.mute)
        } else {
            VStack(alignment: .leading, spacing: big ? 6 : 0) {
                ForEach(rows.prefix(limit)) { row in line(row, big: big) }
            }
        }
    }

    private func line(_ row: ModuleRow, big: Bool) -> some View {
        GitHubLine(row: row, big: big, open: { action in IslandActions.row(module.id, action) })
    }

}

/// A line of GitHub: what happened, where, when. A click unfolds its details (the commits,
/// the files, the checks) when it has some, and opens it on GitHub otherwise or from there.
private struct GitHubLine: View {
    let row: ModuleRow
    let big: Bool
    let open: (String) -> Void
    @State private var unfolded = false

    private var color: Color {
        switch row.state {
        case .success: Color(hex: "#3FB950")
        case .failure: IslandTheme.red
        case .waiting: IslandTheme.amber
        case .busy:    Color(hex: "#5B8CFF")
        case .neutral: Color(hex: "#A371F7")
        }
    }

    /// "il y a 12 min", "hier, 18:40", "lun. 21, 09:12".
    private var when: String? {
        guard let date = row.date else { return nil }
        let calendar = Calendar.current
        if Date.now.timeIntervalSince(date) < 3600 * 6 {
            return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        }
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInYesterday(date) { return loc("hier, \(time)") }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + ", " + time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if !row.details.isEmpty {
                    withAnimation(.islandSpring(0.35)) { unfolded.toggle() }
                } else if let action = row.action {
                    open(action)
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: big ? 13 : 11, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: big ? 30 : 24, height: big ? 30 : 24)
                        .background(Circle().fill(color.opacity(0.13)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title).font(IslandTheme.text(big ? 13 : 12, .semibold)).lineLimit(1)
                        Text(row.detail).font(.system(size: big ? 11 : 10.5, design: .monospaced)).foregroundStyle(Color(hex: "#8E8E93")).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        if !row.label.isEmpty {
                            Text(row.label).font(IslandTheme.text(11)).foregroundStyle(color).lineLimit(1)
                        }
                        if let when {
                            Text(when).font(IslandTheme.text(10.5).monospacedDigit()).foregroundStyle(Color(hex: "#8E8E93")).lineLimit(1)
                        }
                    }
                    if !row.details.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color(hex: "#8E8E93"))
                            .rotationEffect(.degrees(unfolded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if unfolded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(row.details.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(hex: "#B9BCC8"))
                            .lineLimit(2)
                    }
                    if let action = row.action {
                        Button { open(action) } label: {
                            Text(loc("Voir sur GitHub")).font(IslandTheme.text(11.5, .semibold)).foregroundStyle(color)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
                .padding(.leading, big ? 42 : 36)
                .transition(.opacity)
            }
        }
        .padding(big ? 10 : 0)
        .padding(.vertical, big ? 0 : 6)
        .background { if big { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)) } }
    }
}

// MARK: Weather

private struct WeatherPage: View {
    let module: ModuleSnapshot

    private var ambiance: WeatherAmbiance { WeatherAmbiance.pick(symbol: module.symbol, status: module.status) }

    /// "Météo · Paris" when a city was typed, else "Météo".
    static func title(_ module: ModuleSnapshot) -> String {
        let city = (UserDefaults.standard.string(forKey: WeatherModule.cityKey) ?? "").trimmingCharacters(in: .whitespaces)
        return city.isEmpty ? module.name : "\(module.name) · \(city)"
    }


    /// The weather is not known yet: no place, or no network.
    private var needsSetup: Bool { !module.status.contains("°") }

    @ViewBuilder var body: some View {
        if needsSetup { setup } else { weather }
    }

    /// Where to look: one click on « Autoriser », then Yumi finds the place himself.
    private var setup: some View {
        HStack(spacing: 24) {
            YumiSlot(width: 80)
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "sun.max", title: module.name, color: Color(hex: "#7FD8FF"))
                Text(module.title).font(.system(size: 19, weight: .semibold))
                Text(module.subtitle).font(IslandTheme.text(12.5)).foregroundStyle(Color(hex: "#B9BCC8")).padding(.top, 2)
                HStack(spacing: 8) {
                    Button { IslandActions.module(module.id, "primary") } label: {
                        Label(module.primaryAction, systemImage: "location.fill")
                            .font(IslandTheme.text(12.5, .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background(Capsule().fill(Color(hex: "#7FD8FF")))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    private var weather: some View {
        let mood = ambiance
        return HStack(spacing: 24) {
            YumiSlot(width: 96)
            VStack(alignment: .leading, spacing: 0) {
                ModHead(symbol: "sun.max", title: Self.title(module), color: mood.color)
                Text(module.status).font(.system(size: 56, weight: .bold).monospacedDigit())
                Text(mood.name).font(IslandTheme.text(16, .semibold)).padding(.top, 4)
                Text(module.subtitle).font(IslandTheme.text(12.5)).foregroundStyle(Color(hex: "#B9BCC8")).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}


// MARK: Agents

/// The agents in three groups: those working, those waiting for the person, those asleep.
/// For each one: who, on which model, in which repository and branch (or local folder), and
/// what it is doing.
struct AgentsPage: View {
    let module: ModuleSnapshot
    private let blue = Color(hex: "#5B8CFF")
    /// The agent opened: what it was asked, what it did, its files and its tasks.
    @State private var opened: String?

    private var working: [ModuleRow] { module.rows.filter { $0.state == .busy } }
    private var waiting: [ModuleRow] { module.rows.filter { $0.state == .waiting } }
    private var asleep: [ModuleRow] { module.rows.filter { $0.state != .busy && $0.state != .waiting } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModHead(symbol: "terminal.fill", title: loc("Agents"), color: blue) { YumiSlot(width: 40) }
            if let id = opened, let row = module.rows.first(where: { $0.id == id }) {
                detail(row)
            } else if module.rows.isEmpty {
                Text(loc("Aucun agent en cours.")).font(IslandTheme.text(13, .semibold))
                Text(module.subtitle).font(IslandTheme.text(12)).foregroundStyle(IslandCardTheme.mute)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        group(working, title: loc("Travaillent"), color: blue)
                        group(waiting, title: loc("T'attendent"), color: IslandTheme.amber)
                        group(asleep, title: loc("Terminés"), color: Color(hex: "#8E8E93"))
                    }
                }
            }
        }
    }

    @ViewBuilder private func group(_ rows: [ModuleRow], title: String, color: Color) -> some View {
        if !rows.isEmpty {
            Text("\(title.uppercased()) · \(rows.count)")
                .font(IslandTheme.text(10.5, .bold)).tracking(0.8)
                .foregroundStyle(color)
                .padding(.bottom, 6)
                .padding(.top, rows.first.map { first in module.rows.first?.id != first.id } == true ? 10 : 0)
            ForEach(rows) { row in line(row, color: color) }
        }
    }

    /// One agent in full: back to the list, what it did, and its terminal.
    private func detail(_ row: ModuleRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { withAnimation(.islandSpring(0.4)) { opened = nil } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        Text(loc("Tous les agents")).font(IslandTheme.text(12, .semibold))
                    }
                    .foregroundStyle(blue)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let action = row.action {
                    Button { IslandActions.row(module.id, action) } label: {
                        Text(row.actionLabel ?? loc("Ouvrir le terminal"))
                            .font(IslandTheme.text(11.5, .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            ScrollView(.vertical, showsIndicators: false) {
                SessionLive(row: row, journal: ClaudeSessionJournals.shared.journal(row.id))
                    .padding(.bottom, 8)
            }
        }
        .transition(.opacity)
    }

    /// A card: the project on top, the agent, its model and its branch under it, what it does on the right.
    private func line(_ row: ModuleRow, color: Color) -> some View {
        let waits = row.state == .waiting
        let done = row.state != .busy && !waits
        return Button {
            if waits { IslandActions.go(.approval) } else { withAnimation(.islandSpring(0.4)) { opened = row.id } }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: done ? (row.state == .failure ? "exclamationmark" : "checkmark") : "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.place ?? row.title).font(IslandTheme.text(13.5, .bold)).lineLimit(1)
                        if let branch = row.branch {
                            Text("⎇ \(branch)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "#8E8E93")).lineLimit(1)
                        } else if !row.isRepository, row.place != nil {
                            Text(loc("dossier local")).font(IslandTheme.text(11)).foregroundStyle(Color(hex: "#8E8E93"))
                        }
                    }
                    Text([row.agent, row.model].compactMap { $0 }.joined(separator: " · "))
                        .font(IslandTheme.text(11.5)).foregroundStyle(Color(hex: "#B9BCC8")).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.detail).font(IslandTheme.text(12)).foregroundStyle(done ? Color(hex: "#B9BCC8") : color).lineLimit(1)
                    if let date = row.date {
                        Text(done ? date.formatted(.dateTime.hour().minute()) : date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                            .font(IslandTheme.text(11).monospacedDigit()).foregroundStyle(Color(hex: "#8E8E93"))
                    }
                }
                .frame(maxWidth: 230, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(waits ? IslandTheme.amber.opacity(0.1) : Color.white.opacity(done ? 0.035 : 0.05)))
            .overlay { if waits { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IslandTheme.amber.opacity(0.33)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

}
