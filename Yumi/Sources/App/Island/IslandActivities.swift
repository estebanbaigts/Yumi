import SwiftUI

// The open island shows one activity at a time, each with its own layout
// (`STATES[...].view()` in design/maquette/reference.html, version 13): a few lines
// on the left, big round buttons on the right. No cards, no caption under Yumi.

// MARK: - Building blocks

/// `.a-meta`: a dot in the colour of the activity, then who it is about.
struct ActMeta: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
                .font(IslandTheme.text(11.5, .medium))
                .foregroundStyle(IslandTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// `.a-title`
struct ActTitle: View {
    let text: String
    var lines = 1

    var body: some View {
        Text(text)
            .font(IslandTheme.text(17, .semibold))
            .tracking(-0.25)
            .foregroundStyle(IslandTheme.fg)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `.a-sub`
struct ActSub: View {
    let text: String
    var lines = 1

    var body: some View {
        Text(text)
            .font(IslandTheme.text(12.5, .regular))
            .foregroundStyle(IslandTheme.muted)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: lines > 1)
    }
}

/// `.a-mono`: a line of code, with an optional prompt sign in the colour of the activity.
struct ActMono: View {
    var prompt: String?
    let text: String
    var color: Color = IslandTheme.fg

    var body: some View {
        (Text(prompt.map { $0 + " " } ?? "").foregroundStyle(color) + Text(text).foregroundStyle(Color(hex: "#C9CEE0")))
            .font(IslandTheme.mono(11.5))
            .lineLimit(1)
            .truncationMode(.tail)
    }
}

/// `.a-time`: the key figure next to the buttons, in the rounded face.
struct ActTime: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(IslandTheme.round(20, .bold))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }
}

/// `.rbtn`: a big round button with a symbol.
struct RoundButton: View {
    enum Style { case plain, tint, fill, white, bare }

    var style: Style = .plain
    let symbol: String
    let label: String
    var color: Color = .white
    var small = false
    /// The tick draws itself instead of appearing (`.rbtn .draw`).
    var drawsCheck = false
    /// Shown pressed without a click (the filming mode plays the clicks itself).
    var pressed = false
    let action: @MainActor () -> Void

    @State private var hover = false

    private var diameter: CGFloat { small ? 32 : 44 }

    var body: some View {
        Button(action: { action() }) {
            ZStack {
                Circle().fill(background)
                if drawsCheck {
                    DrawnCheck().frame(width: small ? 15 : 20, height: small ? 15 : 20)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: small ? 12 : 16, weight: .bold))
                }
            }
            .foregroundStyle(foreground)
            .frame(width: style == .bare ? 30 : diameter, height: diameter)
            .contentShape(Circle())
            .brightness(hover || pressed ? 0.08 : 0)
            .scaleEffect(pressed ? 0.9 : (hover ? 1.08 : 1))
            .animation(.islandSpring(0.18), value: hover)
            .animation(.islandEase(0.12), value: pressed)
        }
        .buttonStyle(RoundPress())
        .onHover { hover = $0 }
        .accessibilityLabel(label)
        .help(label)
    }

    private var background: Color {
        switch style {
        case .plain: return Color.white.opacity(0.15)
        case .tint:  return color.opacity(0.28)
        case .fill:  return color
        case .white: return .white
        case .bare:  return .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .tint:  return color
        case .white: return .black
        default:     return .white
        }
    }
}

/// `.rbtn:active { transform: scale(.9) }`
struct RoundPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.islandEase(0.12), value: configuration.isPressed)
    }
}

/// The tick of the mock-up (`M4.5 10.5l3.6 3.6 7.4-8` in a 20 pt box), drawn stroke by stroke:
/// `animation: draw .5s .25s ease-out forwards`.
struct DrawnCheck: View {
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 20
            Path { p in
                p.move(to: CGPoint(x: 4.5 * k, y: 10.5 * k))
                p.addLine(to: CGPoint(x: 8.1 * k, y: 14.1 * k))
                p.addLine(to: CGPoint(x: 15.5 * k, y: 6.1 * k))
            }
            .trim(from: 0, to: drawn)
            .stroke(style: StrokeStyle(lineWidth: 2.3 * k, lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            if reduceMotion { drawn = 1 } else {
                withAnimation(.easeOut(duration: 0.5).delay(0.25)) { drawn = 1 }
            }
        }
    }
}

/// `.wave`: four bars that breathe, for something that plays.
struct WaveBars: View {
    let color: Color
    private static let delays: [Double] = [0, 0.2, 0.45, 0.1]
    @Environment(\.islandLayerShown) private var shown

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shown)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    // `@keyframes wave { 50% { height: 14px } }`, 1 s, ease-in-out
                    let phase = (t - Self.delays[i]).truncatingRemainder(dividingBy: 1)
                    let up = 0.5 - 0.5 * cos(phase * 2 * .pi)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: 2.5, height: 4 + 10 * up)
                }
            }
            .frame(height: 14)
        }
    }
}

/// `.prog` and `.times`: the bar of a track or of a timer, with a label at each end.
struct ActProgress: View {
    let progress: ModuleProgress

    var body: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.16))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * min(1, max(0, progress.fraction)))
                        .animation(.linear(duration: 0.5), value: progress.fraction)
                }
            }
            .frame(height: 4)
            HStack {
                Text(progress.leading)
                Spacer()
                Text(progress.trailing)
            }
            .font(IslandTheme.text(10, .medium))
            .monospacedDigit()
            .foregroundStyle(IslandTheme.faint)
        }
        .padding(.top, 5)
    }
}

/// `.shim`: a light that runs along a line while something is being done.
struct ActShimmer: View {
    let color: Color
    @Environment(\.islandLayerShown) private var shown

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !shown)) { timeline in
            // `background-position` from -80 % to 180 % in 1.3 s, on a band 45 % wide
            let p = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.3) / 1.3
            GeometryReader { geo in
                let band = geo.size.width * 0.45
                let free = geo.size.width - band
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    LinearGradient(colors: [.clear, color, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .offset(x: free * (-0.8 + 2.6 * p))
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 3)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }
}

/// `.tbtn`: a quiet text button.
struct TextButton: View {
    let label: String
    let action: @MainActor () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: { action() }) {
            Text(label)
                .font(IslandTheme.text(11.5, .medium))
                .foregroundStyle(hover ? Color.white : IslandTheme.muted)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.top, 3)
    }
}

// MARK: - The row of an activity (`.act`): a few lines, then its buttons

struct ActRow<Lines: View, Trail: View>: View {
    var trailGap: CGFloat = 10
    @ViewBuilder let lines: () -> Lines
    @ViewBuilder let trail: () -> Trail

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) { lines() }
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: trailGap) { trail() }
        }
    }
}

// MARK: - Activities

/// A module, in the layout that suits it: the agenda, the music and the focus timer have
/// their own; the others follow the common model.
struct ModuleActivity: View {
    let module: ModuleSnapshot

    private func primary() { IslandActions.module(module.id, "primary") }
    private func secondary() { IslandActions.module(module.id, "secondary") }

    var body: some View {
        switch module.id {
        case "agenda":            agenda
        case "music", "musique":  music
        case "focus":             focus
        case "github":            github
        case ScreenTimeSummary.moduleID: ScreenTimeActivity(module: module)
        case "claude-code" where !module.rows.isEmpty: sessions
        default:                  common
        }
    }

    /// The next event, with one button: join.
    private var agenda: some View {
        ActRow {
            ActMeta(color: module.color, text: module.status.isEmpty ? module.name : "\(module.name) · \(module.status)").riseIn(0)
            ActTitle(text: module.title).riseIn(1)
            ActSub(text: module.subtitle).riseIn(2)
        } trail: {
            RoundButton(style: .fill, symbol: module.primarySymbol ?? "video.fill", label: module.primaryAction,
                        color: IslandTheme.green, action: primary)
        }
    }

    /// The track, a playback bar, three commands.
    private var music: some View {
        let playing = module.live.map { $0.priority >= ModuleLivePriority.activity } ?? false
        return ActRow(trailGap: 2) {
            HStack(spacing: 8) {
                ActTitle(text: module.title)
                if playing { WaveBars(color: module.color) }
            }
            .riseIn(0)
            ActSub(text: module.subtitle).riseIn(1)
            if let progress = module.progress {
                ActProgress(progress: progress).riseIn(2)
            }
        } trail: {
            RoundButton(style: .bare, symbol: "backward.end.fill", label: loc("Précédent")) {
                IslandActions.module(module.id, "previous")
            }
            RoundButton(style: .white, symbol: module.primarySymbol ?? (playing ? "pause.fill" : "play.fill"),
                        label: module.primaryAction, action: primary)
            RoundButton(style: .bare, symbol: module.secondarySymbol ?? "forward.end.fill",
                        label: module.secondaryAction ?? loc("Suivant"), action: secondary)
        }
    }

    /// The timer: big figures, two buttons.
    private var focus: some View {
        ActRow {
            ActMeta(color: module.color, text: "\(module.name) · \(module.subtitle)").riseIn(0)
            Text(module.status)
                .font(IslandTheme.round(40, .bold))
                .tracking(-0.8)
                .monospacedDigit()
                .foregroundStyle(module.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .riseIn(1)
            if let progress = module.progress {
                ActProgress(progress: progress).riseIn(2)
            }
        } trail: {
            RoundButton(style: .tint, symbol: module.primarySymbol ?? "pause.fill", label: module.primaryAction,
                        color: module.color, action: primary)
            if let second = module.secondaryAction {
                RoundButton(symbol: module.secondarySymbol ?? "stop.fill", label: second, action: secondary)
            }
        }
    }

    /// Claude Code with sessions open: what the first one does, then one line per session,
    /// the ones waiting for something first. A line brings its terminal or editor forward.
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActRow {
                ActMeta(color: module.needsAttention ? IslandTheme.amber : module.color,
                        text: "\(module.name) · \(module.status)").riseIn(0)
                ActTitle(text: module.title).riseIn(1)
            } trail: {
                RoundButton(style: module.needsAttention ? .fill : .plain, symbol: module.primarySymbol ?? "eye.fill",
                            label: module.primaryAction, color: IslandTheme.amber, action: primary)
            }
            ModuleRowsList(module: module, elapsed: true)
                .padding(.leading, -7)
                .riseIn(2)
        }
    }

    /// GitHub: once connected, three pages one at a time (activity, recent, repositories);
    /// before, the repository line with its button. A pull request that waits, or checks gone
    /// red, stay above the pages with their button.
    @ViewBuilder private var github: some View {
        if module.pages.isEmpty {
            githubHead
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if module.needsAttention { githubHead }
                GitHubPager(module: module).riseIn(module.needsAttention ? 3 : 0)
            }
        }
    }

    private var githubHead: some View {
        let waiting = module.needsAttention
        return ActRow {
            ActMeta(color: waiting ? IslandTheme.amber : module.color,
                    text: module.subtitle.isEmpty ? module.name : "\(module.name) · \(module.subtitle)").riseIn(0)
            ActTitle(text: module.title, lines: waiting ? 2 : 1).riseIn(1)
            if let figures = GitHubFigures.parse(module.status) {
                HStack(spacing: 12) {
                    GitHubFigure(symbol: "star.fill", value: figures.stars, label: loc("étoiles"))
                    GitHubFigure(symbol: "arrow.triangle.branch", value: figures.forks, label: loc("forks"))
                    GitHubFigure(symbol: "arrow.triangle.pull", value: figures.pulls, label: loc("pull requests ouvertes"))
                }
                .padding(.top, 2)
                .riseIn(2)
            } else if !module.status.isEmpty {
                ActSub(text: module.status).riseIn(2)
            }
        } trail: {
            if waiting {
                RoundButton(style: .fill, symbol: module.primarySymbol ?? "eye.fill", label: module.primaryAction,
                            color: IslandTheme.amber, action: primary)
            } else if module.primarySymbol == "link" {
                // Not connected yet: the token field is in the island's own settings
                RoundButton(style: .tint, symbol: "link", label: module.primaryAction, color: module.color) {
                    IslandActions.go(.settings)
                }
            } else {
                RoundButton(symbol: module.primarySymbol ?? "arrow.up.forward", label: module.primaryAction, action: primary)
            }
        }
    }

    /// The common model: the key figure in colour, one sentence, one button.
    private var common: some View {
        ActRow {
            ActMeta(color: module.color, text: module.name).riseIn(0)
            ActTitle(text: module.title).riseIn(1)
            ActSub(text: module.subtitle).riseIn(2)
            if let progress = module.progress {
                ActProgress(progress: progress).riseIn(3)
            }
        } trail: {
            ActTime(text: module.status, color: module.color)
            RoundButton(symbol: module.primarySymbol ?? "arrow.right", label: module.primaryAction, action: primary)
            if let second = module.secondaryAction, let symbol = module.secondarySymbol {
                RoundButton(symbol: symbol, label: second, action: secondary)
            }
        }
    }
}

/// An agent at work: what it does, since when.
struct WorkingActivity: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel

    var body: some View {
        ActRow {
            ActMeta(color: IslandTheme.blue, text: IslandAgent.name(state.focusTask)).riseIn(0)
            ActTitle(text: IslandAgent.doing(state)).riseIn(1)
            ActShimmer(color: IslandTheme.blue).riseIn(2)
            ActSub(text: IslandAgent.watching(model)).riseIn(3)
        } trail: {
            // The minutes move on by themselves
            TimelineView(.periodic(from: .now, by: 20)) { _ in
                ActTime(text: IslandAgent.elapsed(model) ?? "", color: IslandTheme.blue)
            }
            RoundButton(symbol: "arrow.up.forward", label: loc("Voir")) { IslandActions.openAgent(state.focusTask) }
        }
    }
}

/// A permission, like an incoming call: red to refuse, green to allow.
struct AlertActivity: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel

    var body: some View {
        if let request = state.pendingApproval?.agentRequest {
            AgentApprovalCard(request: request, model: model)
        } else if let approval = state.pendingApproval {
            ActRow {
                ActMeta(color: IslandTheme.amber, text: IslandAgent.name(state.focusTask)).riseIn(0)
                let agent = state.focusTask?.speaker ?? "Claude"
                let shell = ClaudeToolPhrase.label(for: approval.tool) == loc("Exécute")
                // What the request does, in plain words, and whether it can be undone.
                let reading = AgentRequestReader.read(tool: approval.tool, command: approval.command)
                ActTitle(text: loc("\(agent) veut \(reading.action). Je laisse passer ?"), lines: 2).riseIn(1)
                ActMono(prompt: shell ? "$" : nil, text: approval.command, color: IslandTheme.amber).riseIn(2)
                if let undo = reading.undo { ActSub(text: undo).riseIn(2) }
                HStack(spacing: 14) {
                    // What cannot be undone or leaves the Mac is allowed one time at most.
                    if reading.risk < .high {
                        TextButton(label: loc("Toujours autoriser")) { HookServer.shared.sendApprovalDecision("always", for: approval.requestID) }
                    }
                    // Where the request was made: to read the whole conversation before answering
                    if let open = ClaudeTaskMirror.openLabel(session: approval.sessionId) {
                        TextButton(label: open) { ClaudeTaskMirror.openSession(approval.sessionId) }
                    }
                }.riseIn(3)
            } trail: {
                RoundButton(style: .fill, symbol: "xmark", label: loc("Refuser"), color: IslandTheme.red) {
                    HookServer.shared.sendApprovalDecision("deny", for: approval.requestID)
                }
                RoundButton(style: .fill, symbol: "checkmark", label: loc("Autoriser"), color: IslandTheme.green, drawsCheck: true, pressed: model.studioPress) {
                    HookServer.shared.sendApprovalDecision("allow", for: approval.requestID)
                }
            }
        } else {
            // A question asked in the session: it can only be answered there
            ActRow {
                ActMeta(color: IslandTheme.amber, text: IslandAgent.name(state.focusTask)).riseIn(0)
                ActTitle(text: state.focusTask?.steps.last ?? loc("\(state.focusTask?.speaker ?? "Claude") a une question pour toi."), lines: 2).riseIn(1)
                ActSub(text: loc("Il t'attend dans la session.")).riseIn(2)
            } trail: {
                RoundButton(style: .tint, symbol: "arrow.up.forward", label: loc("Voir"), color: IslandTheme.amber) {
                    IslandActions.openAgent(state.focusTask)
                }
            }
        }
    }
}

/// Yumi itself asks, in one sentence: what will change and where. The planner's goal sits
/// above it; the tool, the files, the scope, the risk, the reason and the consequences wait
/// behind "Voir les détails". Red to refuse, green to allow once, "Pour cette session" in small
/// text when the risk allows it.
private struct AgentApprovalCard: View {
    let request: ApprovalRequest
    @ObservedObject var model: IslandModel
    @State private var showsDetails = false

    private var color: Color { request.riskLevel >= .high ? IslandTheme.red : IslandTheme.amber }
    /// The queue entry of this very approval: a click answers it, or nothing.
    private var answering: String { request.id.uuidString }

    var body: some View {
        ActRow {
            ActMeta(color: color, text: request.intro ?? "Yumi").riseIn(0)
            ActTitle(text: request.headline, lines: 2).riseIn(1)
            if showsDetails {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(request.details, id: \.self) { ActMono(text: $0) }
                }
            } else if let preview = request.contentPreview {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(preview.enumerated()), id: \.offset) { ActMono(text: $0.element) }
                }.riseIn(2)
            } else if let subject = request.subject {
                ActMono(prompt: "$", text: subject, color: color).riseIn(2)
            }
            HStack(spacing: 14) {
                TextButton(label: showsDetails ? loc("Masquer les détails") : loc("Voir les détails")) { showsDetails.toggle() }
                if request.offersSession {
                    TextButton(label: loc("Pour cette session")) { HookServer.shared.sendApprovalDecision("always", for: answering) }
                }
            }.riseIn(3)
        } trail: {
            RoundButton(style: .fill, symbol: "xmark", label: loc("Refuser"), color: IslandTheme.red) {
                HookServer.shared.sendApprovalDecision("deny", for: answering)
            }
            RoundButton(style: .fill, symbol: "checkmark", label: loc("Autoriser"), color: IslandTheme.green, drawsCheck: true, pressed: model.studioPress) {
                HookServer.shared.sendApprovalDecision("allow", for: answering)
            }
        }
    }
}

/// Success: the tick draws itself.
struct FinishedActivity: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    /// The turn's summary, read once the journal has it: it is written a moment after the end
    /// of the turn reaches the island.
    @State private var summary: String?

    var body: some View {
        // The summary of the turn that just ended (files, commands, the agent's last sentence), and
        // what the person refused in it: the agent's answer to the refusal is that last sentence.
        let session = ClaudeTaskMirror.lastFinished
        let refused = session.flatMap { ClaudeTaskMirror.refusals[$0] }
        ActRow {
            ActMeta(color: refused == nil ? IslandTheme.green : IslandTheme.amber, text: IslandAgent.name(state.focusTask)).riseIn(0)
            ActTitle(text: refused.map { loc("Tu as refusé : \($0). Voilà ce qu'il a fait ensuite.") } ?? loc("C'est passé."), lines: 2).riseIn(1)
            if let summary { ActSub(text: summary, lines: 3).riseIn(2) }
        } trail: {
            EmptyView()
        }
        // Nothing to answer: the summary is read, then the island folds by itself. Longer text,
        // longer stay; another view opened meanwhile is left alone.
        .task(id: session?.value) {
            summary = nil
            for _ in 0..<10 {
                if let text = session.flatMap({ ClaudeSessionJournals.shared.journals[$0.value]?.summary }) {
                    summary = text
                    break
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            let seconds = min(12, 6 + Double((summary ?? "").count) / 40)
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, state.view == .finished else { return }
            IslandActions.fold()
        }
    }
}

/// The error, with the line that broke.
struct ErrorActivity: View {
    @ObservedObject var state: AppState

    var body: some View {
        ActRow {
            ActMeta(color: IslandTheme.red, text: IslandAgent.name(state.focusTask)).riseIn(0)
            ActTitle(text: loc("Ça a planté. Tu veux voir où ?")).riseIn(1)
            if let last = state.focusTask?.steps.last {
                ActMono(text: last).riseIn(2)
            } else {
                ActSub(text: loc("Je n'ai pas le détail. Il est dans la session.")).riseIn(2)
            }
        } trail: {
            RoundButton(style: .tint, symbol: "arrow.up.forward", label: loc("Voir"), color: IslandTheme.red) {
                IslandActions.openAgent(state.focusTask)
            }
        }
    }
}

/// A file handed to Yumi (`.dropz`), then what to do with it.
struct DropActivity: View {
    @ObservedObject var state: AppState

    private var file: DroppedFile? { state.view == .upload ? nil : state.droppedFile }
    @State private var handed: ClaudeCodeModule.HandOff?

    /// "Claude", "Codex": the agent of the session the pill shows.
    private var agentSpeaker: String {
        state.tasks.first(where: { $0.id == ClaudeTaskMirror.taskID })?.speaker ?? "Claude"
    }

    private var handedLine: String? {
        switch handed {
        case .typed:  return loc("C'est dans la session. Ajoute ta consigne et valide.")
        case .copied: return loc("Chemin copié. Colle-le dans la session avec ⌘V.")
        case nil:     return nil
        }
    }

    var body: some View {
        if let file {
            ActRow(trailGap: 8) {
                ActMeta(color: IslandTheme.blue, text: loc("Bien reçu")).riseIn(0)
                ActTitle(text: file.name).riseIn(1)
                ActSub(text: handedLine ?? loc("J'en fais quoi ? Je résume, j'envoie ou je range.")).riseIn(2)
            } trail: {
                if let target = ClaudeTaskMirror.fileTarget {
                    RoundButton(style: .tint, symbol: "arrow.right.doc.on.clipboard", label: loc("Donner à \(agentSpeaker)"),
                                color: IslandTheme.red) {
                        Task {
                            handed = await ClaudeCodeModule.hand(file.url, to: target)
                            if handed != nil {
                                SoundEngine.shared.play("send")
                                IslandModel.shared.pose(.pop)
                            }
                        }
                    }
                }
                RoundButton(style: ClaudeTaskMirror.fileTarget == nil ? .tint : .plain, symbol: "text.alignleft", label: loc("Résumer"),
                            color: IslandTheme.blue) { IslandActions.summarize() }
                RoundButton(symbol: "paperplane.fill", label: loc("Envoyer")) { IslandActions.sendByMail() }
                RoundButton(symbol: "tray.and.arrow.down.fill", label: loc("Ranger")) { IslandActions.putAway() }
            }
            .onChange(of: file.name) { handed = nil }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                ActTitle(text: loc("Donne, je m'en occupe."))
                ActSub(text: loc("Je résume, j'envoie ou je range. Tu choisis."))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(Color.white.opacity(state.fileDragOver ? 0.55 : 0.28),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
            .riseIn(0)
        }
    }
}

/// One figure of the GitHub activity: a small symbol, then the number in the rounded face.
struct GitHubFigure: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(IslandTheme.muted)
            Text(value)
                .font(IslandTheme.round(12.5, .semibold))
                .monospacedDigit()
                .foregroundStyle(IslandTheme.fg)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
        .help(label)
    }
}
