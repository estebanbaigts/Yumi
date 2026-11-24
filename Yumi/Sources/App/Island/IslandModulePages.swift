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

/// The seven moods of the weather page (`WX` in the workshop), picked from the sky, the
/// temperature, the hour and the season.
enum WeatherAmbiance: String, CaseIterable {
    case pluie, soleil, neige, nuit, chaud, froid, doux

    var name: String {
        switch self {
        case .pluie: loc("Pluie")
        case .soleil: loc("Soleil")
        case .neige: loc("Neige")
        case .nuit: loc("Nuit")
        case .chaud: loc("Chaud")
        case .froid: loc("Froid")
        case .doux: loc("Doux")
        }
    }

    var color: Color {
        switch self {
        case .pluie: Color(hex: "#7FB4FF")
        case .soleil: Color(hex: "#FFC94D")
        case .neige: Color(hex: "#DDEBFF")
        case .nuit: Color(hex: "#8B9CFF")
        case .chaud: Color(hex: "#FF8A4D")
        case .froid: Color(hex: "#9FD8FF")
        case .doux: Color(hex: "#9CF2C8")
        }
    }

    /// What Yumi does in it (`WX` of the workshop: scene, face, costume).
    var habit: YumiHabit? {
        switch self {
        case .pluie: .cloud
        case .soleil: .sunglasses
        case .nuit: .sleep
        case .chaud: .exhausted
        case .doux: .whistle
        case .neige, .froid: nil
        }
    }

    /// The face when no habit brings its own.
    var mood: YumiMood? {
        switch self {
        case .neige: .surprised
        case .froid: .worried
        default: nil
        }
    }

    var wearsBeanie: Bool { self == .neige || self == .froid }

    /// `symbol` is the module's SF Symbol, which follows the WMO code; `status` reads "19°".
    /// The filming mode shows each mood in turn.
    @MainActor static var forced: WeatherAmbiance?

    @MainActor static func pick(symbol: String, status: String, now: Date = .now, calendar: Calendar = .current) -> WeatherAmbiance {
        if let forced { return forced }
        let temperature = Int(status.filter { $0.isNumber || $0 == "-" || $0 == "−" }.replacingOccurrences(of: "−", with: "-"))
        let hour = calendar.component(.hour, from: now)
        let month = calendar.component(.month, from: now)
        let winter = [12, 1, 2].contains(month), summer = [6, 7, 8].contains(month)
        if symbol.contains("snow") { return .neige }
        if symbol.contains("rain") || symbol.contains("drizzle") || symbol.contains("bolt") { return .pluie }
        if let t = temperature, t >= (summer ? 30 : 28) { return .chaud }
        if let t = temperature, t <= (winter ? 3 : 1) { return .froid }
        if hour < 7 || hour >= 21 { return .nuit }
        if symbol.hasPrefix("sun") { return .soleil }
        return .doux
    }
}

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

/// The animated ground of the weather page, drawn in a Canvas.
struct WeatherEffects: View {
    let ambiance: WeatherAmbiance

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { g, size in
                switch ambiance {
                case .pluie: rain(g, size, t)
                case .soleil: sun(g, size, t, color: Color(hex: "#FFC94D"), speed: 18, glow: true)
                case .chaud:
                    g.fill(Path(CGRect(origin: .zero, size: size)),
                           with: .linearGradient(Gradient(colors: [Color(hex: "#FF6A2A").opacity(0.18 + 0.1 * sin(t * 2.5)), .clear]),
                                                 startPoint: CGPoint(x: 0, y: size.height), endPoint: CGPoint(x: 0, y: size.height * 0.3)))
                    sun(g, size, t, color: Color(hex: "#FF8A4D"), speed: 6, glow: false)
                    waves(g, size, t)
                case .neige: snow(g, size, t)
                case .nuit: night(g, size, t)
                case .froid: frost(g, size, t)
                case .doux: mild(g, size, t)
                }
            }
        }
    }

    private func rain(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#1B2333"), .black]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.75)))
        for i in 0..<45 {
            let x = size.width * Double((i * 37) % 100) / 100
            let duration = 0.55 + Double(i % 5) * 0.08
            let phase = ((t + Double(i) * 0.13) / duration).truncatingRemainder(dividingBy: 1)
            let length = 14 + Double(i % 4) * 5
            let y = -30 + phase * (size.height + 60)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - length * 0.18, y: y + length))
            g.stroke(path, with: .color(Color(hex: "#9CC4FF").opacity([0.35, 0.55, 0.75][i % 3])), lineWidth: 1.6)
        }
        for i in 0..<12 {
            let phase = ((t + Double(i) * 0.21) / 1.2).truncatingRemainder(dividingBy: 1)
            let x = size.width * Double((i * 53 + 7) % 100) / 100
            let w = 10 * (0.4 + phase)
            let rect = CGRect(x: x - w / 2, y: size.height - 8, width: w, height: 4)
            g.stroke(Path(ellipseIn: rect), with: .color(Color(hex: "#9CC4FF").opacity(1 - phase)), lineWidth: 1.2)
        }
    }

    private func sun(_ g: GraphicsContext, _ size: CGSize, _ t: Double, color: Color, speed: Double, glow: Bool) {
        let center = CGPoint(x: size.width - 100, y: 90)
        if glow {
            let r = 130 * (1 + 0.05 * sin(t * .pi / 2))
            g.fill(Path(ellipseIn: CGRect(x: size.width + 60 - 2 * r, y: -60, width: 2 * r, height: 2 * r)),
                   with: .radialGradient(Gradient(colors: [color.opacity(0.53), color.opacity(0.13), .clear]),
                                         center: CGPoint(x: size.width + 60 - r, y: -60 + r), startRadius: 0, endRadius: r))
        }
        var rays = g
        rays.translateBy(x: center.x, y: center.y)
        rays.rotate(by: .degrees(t / speed * 360))
        for k in 0..<12 {
            var ray = rays
            ray.rotate(by: .degrees(Double(k) * 30))
            ray.fill(Path(roundedRect: CGRect(x: -3, y: -52, width: 6, height: 16), cornerRadius: 3), with: .color(color))
        }
        g.fill(Path(ellipseIn: CGRect(x: center.x - 26, y: center.y - 26, width: 52, height: 52)), with: .color(color == Color(hex: "#FFC94D") ? Color(hex: "#FFD24A") : Color(hex: "#FF7A3D")))
    }

    private func waves(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        for i in 0..<6 {
            let phase = ((t + Double(i) * 0.4) / 2.4).truncatingRemainder(dividingBy: 1)
            let x = size.width * (0.08 + Double(i) * 0.15)
            let y = size.height + 10 - phase * size.height * 0.8
            var path = Path()
            path.move(to: CGPoint(x: x, y: y + 70))
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 12, y: y + 35))
            g.stroke(path, with: .color(Color(red: 1, green: 0.55, blue: 0.3).opacity(0.45 * (1 - phase))), lineWidth: 2)
        }
    }

    private func snow(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        let flakes: [(CGFloat, CGFloat, CGFloat)] = [(20, 30, 2.2), (80, 90, 1.6), (150, 50, 2), (120, 150, 1.4), (190, 120, 2.4)]
        let drift = (t / 6).truncatingRemainder(dividingBy: 1) * 200
        var x0: CGFloat = 0
        while x0 < size.width {
            var y0: CGFloat = -200
            while y0 < size.height {
                for f in flakes {
                    let y = y0 + f.1 + drift
                    g.fill(Path(ellipseIn: CGRect(x: x0 + f.0 + sin((t + Double(f.1)) * 0.8) * 4, y: y, width: f.2 * 2, height: f.2 * 2)), with: .color(.white.opacity(0.85)))
                }
                y0 += 200
            }
            x0 += 220
        }
    }

    private func night(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .linearGradient(Gradient(colors: [Color(hex: "#0B1030"), .black]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.8)))
        let stars: [(CGFloat, CGFloat, CGFloat)] = [(40, 60, 1.4), (140, 40, 1), (260, 90, 1.6), (380, 50, 1), (520, 110, 1.3), (600, 70, 1)]
        for (i, s) in stars.enumerated() {
            let a = 0.55 + 0.45 * sin(t * 2 + Double(i))
            g.fill(Path(ellipseIn: CGRect(x: s.0, y: s.1, width: s.2 * 2, height: s.2 * 2)), with: .color(.white.opacity(a)))
        }
        // The crescent: a disc with another cut out of it
        let moon = CGRect(x: size.width - 160, y: 50, width: 40, height: 40)
        var crescent = Path(ellipseIn: moon.offsetBy(dx: -8, dy: 6))
        crescent = crescent.subtracting(Path(ellipseIn: moon))
        g.fill(crescent, with: .color(Color(hex: "#E8ECFF").opacity(0.9)))
    }

    private func frost(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [Color(hex: "#9FD8FF").opacity(0.27), .clear]),
                                     center: CGPoint(x: size.width / 2, y: size.height * 1.2), startRadius: 0, endRadius: size.width * 0.6))
        for i in 0..<14 {
            let phase = ((t + Double(i) * 0.37) / 2.4).truncatingRemainder(dividingBy: 1)
            let a = sin(phase * .pi)
            let p = CGPoint(x: size.width * Double((i * 41 + 5) % 100) / 100, y: size.height * Double((i * 23 + 8) % 100) / 100)
            g.draw(Text("✦").font(.system(size: 11)).foregroundStyle(Color(hex: "#CFEFFF").opacity(a)), at: p)
        }
        for i in 0..<5 {
            let duration = 2.2 + Double(i % 3) * 0.5
            let phase = ((t + Double(i) * 0.7) / duration).truncatingRemainder(dividingBy: 1)
            let x = -170 + phase * (size.width + 340)
            let y = size.height * (0.18 + Double(i) * 0.15)
            var path = Path()
            path.move(to: CGPoint(x: x, y: y + 12))
            path.addCurve(to: CGPoint(x: x + 100, y: y + 10), control1: CGPoint(x: x + 30, y: y + 4), control2: CGPoint(x: x + 60, y: y + 20))
            path.addQuadCurve(to: CGPoint(x: x + 150, y: y + 8), control: CGPoint(x: x + 140, y: y + 4))
            g.stroke(path, with: .color(Color(red: 0.81, green: 0.94, blue: 1).opacity(0.55)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
    }

    private func mild(_ g: GraphicsContext, _ size: CGSize, _ t: Double) {
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [Color(hex: "#9CF2C8").opacity(0.2), .clear]),
                                     center: CGPoint(x: size.width * 0.8, y: 0), startRadius: 0, endRadius: size.width * 0.5))
        let leaves: [(String, String)] = [("❀", "#9CF2C8"), ("✿", "#FFD6A5"), ("❀", "#C8F29C"), ("✦", "#FFB3D1")]
        for i in 0..<9 {
            let duration = [6.0, 7.5, 9.0][i % 3]
            let phase = ((t + Double(i) * 0.9) / duration).truncatingRemainder(dividingBy: 1)
            let leaf = leaves[i % 4]
            let x = -20 + phase * (size.width + 40)
            let y = size.height * Double((i * 29 + 10) % 75) / 100 + sin(phase * .pi * 4) * 14
            var c = g
            c.translateBy(x: x, y: y)
            c.rotate(by: .degrees(phase * 360))
            c.draw(Text(leaf.0).font(.system(size: 14)).foregroundStyle(Color(hex: leaf.1).opacity(0.8)), at: .zero)
        }
    }
}

// MARK: Agents

/// The agents in three groups: those working, those waiting for the person, those asleep.
/// For each one: who, on which model, in which repository and branch (or local folder), and
/// what it is doing.
struct AgentsPage: View {
    let module: ModuleSnapshot
    private let blue = Color(hex: "#5B8CFF")

    private var working: [ModuleRow] { module.rows.filter { $0.state == .busy } }
    private var waiting: [ModuleRow] { module.rows.filter { $0.state == .waiting } }
    private var asleep: [ModuleRow] { module.rows.filter { $0.state != .busy && $0.state != .waiting } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModHead(symbol: "terminal.fill", title: loc("Agents"), color: blue) { YumiSlot(width: 40) }
            if module.rows.isEmpty {
                Text(loc("Aucun agent en cours.")).font(IslandTheme.text(13, .semibold))
                Text(module.subtitle).font(IslandTheme.text(12)).foregroundStyle(IslandCardTheme.mute)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        group(working, title: loc("Travaillent"), color: blue)
                        group(waiting, title: loc("T'attendent"), color: IslandTheme.amber)
                        if !asleep.isEmpty { sleepers }
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
                .padding(.top, rows.first?.state == .waiting && !working.isEmpty ? 10 : 0)
            ForEach(rows) { row in line(row, color: color) }
        }
    }

    private func line(_ row: ModuleRow, color: Color) -> some View {
        let waits = row.state == .waiting
        return Button {
            if waits { IslandActions.go(.approval) } else if let action = row.action { IslandActions.row(module.id, action) }
        } label: {
            HStack(spacing: 12) {
                Circle().fill(color).frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.7), radius: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(row.agent ?? row.title).font(IslandTheme.text(13, .bold))
                        if let model = row.model {
                            Text("· \(model)").font(IslandTheme.text(13)).foregroundStyle(Color(hex: "#8E8E93"))
                        }
                    }
                    HStack(spacing: 6) {
                        Text(row.place ?? row.title).font(IslandTheme.text(11.5)).foregroundStyle(Color(hex: "#B9BCC8"))
                        if let branch = row.branch {
                            Text("⎇ \(branch)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(hex: "#8E8E93"))
                        } else if row.isRepository == false, row.place != nil {
                            Text(loc("dossier local")).font(IslandTheme.text(11)).foregroundStyle(Color(hex: "#8E8E93"))
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.detail).font(IslandTheme.text(12)).foregroundStyle(color).lineLimit(1)
                    if let date = row.date {
                        Text(date, style: .relative).font(IslandTheme.text(11).monospacedDigit()).foregroundStyle(Color(hex: "#8E8E93"))
                    }
                }
                .frame(maxWidth: 220, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(waits ? IslandTheme.amber.opacity(0.1) : Color.white.opacity(0.05)))
            .overlay { if waits { RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(IslandTheme.amber.opacity(0.33)) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
    }

    private var sleepers: some View {
        let names = asleep.map { row in
            [row.agent ?? row.title, row.place].compactMap { $0 }.joined(separator: " · ")
        }
        return HStack(spacing: 8) {
            Image(systemName: "moon.zzz.fill").font(.system(size: 12)).foregroundStyle(Color(hex: "#8E8E93"))
            Text(asleep.count == 1 ? loc("1 agent dort : \(names.joined(separator: ", "))")
                                   : loc("\(asleep.count) agents dorment : \(names.joined(separator: ", "))"))
                .font(IslandTheme.text(12)).foregroundStyle(Color(hex: "#8E8E93")).lineLimit(2)
        }
        .padding(.top, 10)
    }
}
