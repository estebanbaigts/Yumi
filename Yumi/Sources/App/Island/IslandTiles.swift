import SwiftUI

// What each module shows in its tile of the bento: real elements at a glance (the contribution
// grid, the sky, the cover and its controls, the timer ring, the first lines of a list), the
// complete view waits in the sheet. A module without a face of its own gets its icon, its key
// figure and its headline.

struct ModuleTileBody: View {
    let module: ModuleSnapshot
    /// The large tile, next to Yumi: more room, more lines.
    var large = false

    var body: some View {
        switch module.id {
        case "github":           GitHubTile(module: module, large: large)
        case "weather", "meteo": WeatherTile(module: module, large: large)
        case "music", "musique": MusicTile(module: module, large: large)
        case "focus":            FocusTile(module: module, large: large)
        case "agenda":           AgendaTile(module: module, large: large)
        case IslandModel.agentModuleID where !module.rows.isEmpty: SessionsTile(module: module, large: large)
        case "notes":            NoteTile(module: module, large: large)
        default:
            if module.rows.isEmpty { PlainTile(module: module, large: large) } else { RowsTile(module: module, large: large) }
        }
    }
}

/// A round button inside a tile: it does its module's action without opening the sheet.
private struct TileButton: View {
    let symbol: String
    let label: String
    var filled = false
    var color: Color = .white
    var size: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(filled ? Color.black : Color.white)
                .frame(width: size, height: size)
                .background(Circle().fill(filled ? color : Color.white.opacity(0.1)))
                .contentShape(Circle())
        }
        .buttonStyle(RoundPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The module's icon in a small rounded square of its colour.
private struct TileIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(color.opacity(0.16)))
    }
}

private struct Headline: View {
    let text: String
    var size: CGFloat = 12.5
    var lines = 1

    var body: some View {
        Text(text)
            .font(IslandTheme.text(size, .semibold))
            .foregroundStyle(IslandTheme.fg)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Faint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(IslandTheme.text(11))
            .foregroundStyle(IslandTheme.muted)
            .lineLimit(1)
    }
}

// MARK: - GitHub: the figures and the contribution grid

private struct GitHubTile: View {
    let module: ModuleSnapshot
    let large: Bool
    @ObservedObject private var contributions = GitHubContributions.shared
    @State private var day: ContributionDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let figures = GitHubFigures.parse(module.status) {
                HStack(spacing: 12) {
                    figure("star.fill", figures.stars, IslandTheme.amber)
                    figure("tuningfork", figures.forks, IslandTheme.blue)
                    figure("arrow.triangle.pull", figures.pulls, IslandTheme.green)
                }
            } else {
                Headline(text: module.title)
            }
            if let calendar = contributions.calendar {
                // The last weeks, as many as the tile can hold
                ContributionGrid(calendar: calendar.lastWeeks(large ? 26 : 30), cell: large ? 5.5 : 3.6, gap: 1.2, selected: $day)
                    .allowsHitTesting(false)
            } else {
                Faint(text: module.title)
            }
        }
    }

    private func figure(_ symbol: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(value).font(IslandTheme.round(15, .bold)).monospacedDigit().foregroundStyle(IslandTheme.fg)
        }
    }
}

extension ContributionCalendar {
    /// The same calendar, keeping only its last `count` weeks.
    func lastWeeks(_ count: Int) -> ContributionCalendar {
        var copy = self
        copy.weeks = Array(weeks.suffix(count))
        return copy
    }
}

// MARK: - Weather: the sky and the temperature

private struct WeatherTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        HStack(spacing: large ? 10 : 8) {
            Image(systemName: module.symbol == "circle.fill" ? "cloud.sun.fill" : module.symbol)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: large ? 40 : 24))
            VStack(alignment: .leading, spacing: 1) {
                Text(module.status)
                    .font(IslandTheme.round(large ? 34 : 21, .bold))
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.fg)
                Faint(text: module.subtitle.isEmpty ? module.title : module.subtitle)
            }
        }
    }
}

// MARK: - Music: the cover, the bar, the controls

private struct MusicTile: View {
    let module: ModuleSnapshot
    let large: Bool

    private var playing: Bool { module.live.map { $0.priority >= ModuleLivePriority.activity } ?? false }

    var body: some View {
        // Whatever the size of its tile: the full player when it fits, else one line
        ViewThatFits(in: .vertical) {
            full
            compact
        }
    }

    private var compact: some View {
        HStack(spacing: 8) {
            Headline(text: module.title, size: 12.5)
            Spacer(minLength: 4)
            TileButton(symbol: playing ? "pause.fill" : "play.fill", label: module.primaryAction, filled: true, size: 24) {
                IslandActions.module(module.id, "primary")
            }
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(AngularGradient(colors: [Color(hex: "#F58AD9"), Color(hex: "#8B6CFF"), Color(hex: "#5B8CFF"), Color(hex: "#F58AD9")],
                                          center: .center))
                    .frame(width: large ? 54 : 40, height: large ? 54 : 40)
                    .overlay {
                        if playing { WaveBars(color: .white) } else {
                            Image(systemName: "music.note").font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        }
                    }
                    .shadow(color: Color(hex: "#F58AD9").opacity(0.3), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Headline(text: module.title, size: large ? 14 : 12.5)
                    Faint(text: module.subtitle)
                }
            }
            if let progress = module.progress {
                ProgressLine(fraction: progress.fraction, color: .white)
            }
            HStack(spacing: 6) {
                TileButton(symbol: "backward.fill", label: loc("Précédent")) { IslandActions.module(module.id, "previous") }
                TileButton(symbol: playing ? "pause.fill" : "play.fill", label: module.primaryAction, filled: true, size: 28) {
                    IslandActions.module(module.id, "primary")
                }
                TileButton(symbol: "forward.fill", label: module.secondaryAction ?? loc("Suivant")) { IslandActions.module(module.id, "secondary") }
            }
        }
    }
}

// MARK: - Focus: the ring and its button

private struct FocusTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        ViewThatFits(in: .vertical) {
            full
            compact
        }
    }

    /// One line: the time left and its button, for a short tile.
    private var compact: some View {
        HStack(spacing: 8) {
            Text(module.status)
                .font(IslandTheme.round(15, .bold))
                .monospacedDigit()
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            ProgressLine(fraction: module.progress?.fraction ?? 0, color: module.color)
            TileButton(symbol: module.primarySymbol ?? "play.fill", label: module.primaryAction, filled: true, color: module.color, size: 24) {
                IslandActions.module(module.id, "primary")
            }
        }
    }

    private var full: some View {
        let side: CGFloat = large ? 76 : 62
        return VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: module.progress?.fraction ?? 0)
                    .stroke(module.color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(module.status)
                    .font(IslandTheme.round(module.status.count > 5 ? 11 : 15, .bold))
                    .monospacedDigit()
                    .foregroundStyle(IslandTheme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(6)
            }
            .frame(width: side, height: side)
            TileButton(symbol: module.primarySymbol ?? "play.fill", label: module.primaryAction, filled: true, color: module.color, size: 26) {
                IslandActions.module(module.id, "primary")
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Agenda: a calendar page with the time

private struct AgendaTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(IslandTheme.text(8.5, .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                        .background(IslandTheme.red)
                    Text(module.status.isEmpty ? Date.now.formatted(.dateTime.day()) : module.status)
                        .font(IslandTheme.round(module.status.count > 3 ? 13 : 18, .bold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Headline(text: module.title, size: large ? 15 : 12.5, lines: 2)
                    Faint(text: module.subtitle)
                }
            }
            if large, !module.primaryAction.isEmpty {
                Button { IslandActions.module(module.id, "primary") } label: {
                    Label(module.primaryAction, systemImage: module.primarySymbol ?? "video.fill")
                        .font(IslandTheme.text(11.5, .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(IslandTheme.green))
                        .contentShape(Capsule())
                }
                .buttonStyle(RoundPress())
            }
        }
    }
}

// MARK: - Claude Code, small: its sessions as little characters

private struct SessionsTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(module.rows.prefix(large ? 4 : 2)) { row in
                HStack(spacing: 7) {
                    MiniYumi(color: IslandSessions.color(row.id), size: 17, asleep: row.state == .neutral)
                    Text(row.title).font(IslandTheme.text(12, .semibold)).lineLimit(1)
                    Text(row.label).font(IslandTheme.text(11)).foregroundStyle(IslandTheme.muted).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - A note: a small yellow sheet

private struct NoteTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(module.title)
                .font(IslandTheme.text(11.5, .bold))
                .foregroundStyle(Color(hex: "#3B2F00"))
                .lineLimit(1)
            Text(module.subtitle)
                .font(IslandTheme.text(11))
                .foregroundStyle(Color(hex: "#5A4A10"))
                .lineLimit(large ? 4 : 1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, large ? 8 : 5)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "#F7D774")))
        .rotationEffect(.degrees(-1.2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - A list: its first lines

private struct RowsTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(module.rows.prefix(large ? 4 : 3)) { row in
                HStack(spacing: 7) {
                    if row.check != nil {
                        Circle().strokeBorder(IslandTheme.faint, lineWidth: 1.4).frame(width: 11, height: 11)
                    } else {
                        Circle().fill(color(row.state)).frame(width: 6, height: 6).frame(width: 11)
                    }
                    Text(row.title).font(IslandTheme.text(11.5, .medium)).foregroundStyle(IslandTheme.fg).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(row.label).font(IslandTheme.text(10.5)).foregroundStyle(row.state == .failure ? IslandTheme.red : IslandTheme.muted).lineLimit(1)
                }
            }
        }
    }

    private func color(_ state: ModuleRowState) -> Color {
        switch state {
        case .busy: return IslandTheme.blue
        case .waiting: return IslandTheme.amber
        case .success: return IslandTheme.green
        case .failure: return IslandTheme.red
        case .neutral: return module.color
        }
    }
}

// MARK: - Any other module: its icon, its figure, its headline

private struct PlainTile: View {
    let module: ModuleSnapshot
    let large: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TileIcon(symbol: module.glyph, color: module.color, size: large ? 32 : 26)
            VStack(alignment: .leading, spacing: 2) {
                if !module.status.isEmpty {
                    Text(module.status)
                        .font(IslandTheme.round(large ? 22 : 18, .bold))
                        .monospacedDigit()
                        .foregroundStyle(IslandTheme.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Headline(text: module.title, size: 11.5, lines: 2)
            }
        }
    }
}

// MARK: - Focus: choosing the length by hand

/// Ready-made lengths, and minutes to the minute with − and +. "Démarrer" starts it at once;
/// Yumi can also be asked in the chat ("un focus de 50 minutes").
struct FocusLengthPicker: View {
    @AppStorage("focus.chosenMinutes") private var minutes = 25
    @Environment(\.islandAccent) private var accent
    private static let presets = [15, 25, 45, 60, 90]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.presets, id: \.self) { preset in
                let on = minutes == preset
                Button { minutes = preset; IslandActions.tap() } label: {
                    Text("\(preset)")
                        .font(IslandTheme.round(12, on ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(on ? Color.white : IslandTheme.muted)
                        .frame(width: 32, height: 24)
                        .background(Capsule().fill(on ? accent.opacity(0.45) : Color.white.opacity(0.07)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            HStack(spacing: 2) {
                stepButton("minus") { minutes = max(1, minutes - 5) }
                Text(loc("\(minutes) min"))
                    .font(IslandTheme.round(13, .bold))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                stepButton("plus") { minutes = min(240, minutes + 5) }
            }
            .padding(2)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            Button {
                NotificationCenter.default.post(name: .focusStartMinutes, object: nil, userInfo: ["minutes": minutes])
                SoundEngine.shared.play("approve")
                IslandModel.shared.pose(.pop)
            } label: {
                Label(loc("Démarrer"), systemImage: "play.fill")
                    .font(IslandTheme.text(11.5, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(accent))
                    .contentShape(Capsule())
            }
            .buttonStyle(RoundPress())
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button { action(); IslandActions.tap() } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
