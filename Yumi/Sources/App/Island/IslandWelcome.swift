import SwiftUI

// The first launch: Yumi asks the person's first name, in his voice, with a single field
// (design/voix.md), and what he should have in hand while an agent works (coffee,
// tea, a book, nothing...). The name goes to the core through `memorySetName`; it can be passed
// over, he asks again later, without insisting. The choice is made before the name is sent.

struct WelcomeActivity: View {
    @State private var text = ""
    /// Empty until the person picks one.
    @State private var held = YumiWorkHabit.isChosen() ? YumiWorkHabit.current().rawValue : ""
    @FocusState private var focused: Bool
    /// Where Yumi stands without any setup: Apple's model, or the simple mode. Never a question.
    @State private var engine: EngineWelcome?
    /// After the first name: what the person mostly does, when the modules were never chosen.
    @State private var askingActivity = WelcomeActivity.startsOnActivity
    /// The island's demo opens the second step directly (IslandDemo, "welcome-activity").
    nonisolated(unsafe) static var startsOnActivity = false

    var body: some View {
        if askingActivity {
            ActivityProfilesStep()
        } else {
            nameStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ActTitle(text: loc("Moi, c'est Yumi. Et toi ?")).riseIn(0)
                ActSub(text: loc("Juste ton prénom. Je le garde pour moi.")).riseIn(1)
            }
            HStack(spacing: 6) {
                TextField("", text: $text, prompt: Text("Ton prénom").foregroundStyle(IslandTheme.faint))
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .focused($focused)
                    .onSubmit(answer)
                RoundButton(style: .white, symbol: "arrow.up", label: loc("Valider"), small: true, action: answer)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(2)
            HStack(spacing: 8) {
                ActSub(text: loc("Quand je bosse pour toi, je prends"))
                WorkHabitChips(choices: YumiWorkHabit.firstChoices, selected: held) { choose($0) }
                if let choice = YumiWorkHabit(rawValue: held) {
                    WorkHabitPreview(choice: choice, size: 18)
                        .frame(width: 30, height: 22)
                }
            }
            .riseIn(3)
            if let engine {
                VStack(alignment: .leading, spacing: 0) {
                    // Up to three lines: this sentence is the whole answer to "does it work here?"
                    Text(engine.text)
                        .font(IslandTheme.text(12.5, .regular))
                        .foregroundStyle(IslandTheme.muted)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if engine.opensAppleSettings {
                        TextButton(label: loc("Ouvrir les Réglages Système")) { NSWorkspace.shared.open(AppleModelAvailability.settingsURL) }
                    }
                }
                .riseIn(4)
            }
            TextButton(label: loc("Plus tard")) { IslandActions.skipName() }
                .riseIn(4)
            // The menu bar item can hide behind the notch: the other ways in, said once
            ActSub(text: loc("Clic droit sur moi pour les réglages ou pour quitter. Triple Maj m'ouvre de partout."))
                .riseIn(5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            focused = true
            engine = EngineWelcome.message(active: EngineFactory.activeEngine, apple: .current)
        }
    }

    private func choose(_ choice: YumiWorkHabit) {
        held = choice.rawValue
        UserDefaults.standard.set(choice.rawValue, forKey: YumiWorkHabit.defaultsKey)
        IslandActions.tap()
    }

    private func answer() {
        guard !held.isEmpty, let name = FirstName.clean(text) else { return }
        // A first launch goes on with the activity; a first name asked again later does not.
        let firstLaunch = !ModuleRegistry.modulesWereChosen()
        IslandActions.giveName(name, leave: !firstLaunch)
        if firstLaunch { withAnimation(.islandSpring(0.35)) { askingActivity = true } }
    }
}

/// The second step of the first launch: what the person mostly does on their Mac. Several
/// answers, or a word of their own; the modules of the island follow it.
struct ActivityProfilesStep: View {
    @State private var chosen: Set<String> = Set(WorkProfiles.detected(codingAgentInstalled: ActivityProfilesStep.codingAgentInstalled()))
    @State private var other = ""
    @Environment(\.islandAccent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                ActTitle(text: loc("Et tu fais quoi, surtout, sur ton Mac ?")).riseIn(0)
                ActSub(text: loc("Choisis-en autant que tu veux. Je mets les bons modules dans l'encoche.")).riseIn(1)
            }
            ProfileFlow(spacing: 5) {
                ForEach(WorkProfiles.all) { profile in
                    let on = chosen.contains(profile.id)
                    Button {
                        if on { chosen.remove(profile.id) } else { chosen.insert(profile.id) }
                        IslandActions.tap()
                    } label: {
                        Text(profile.label)
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
            .riseIn(2)
            HStack(spacing: 6) {
                TextField("", text: $other, prompt: Text("Autre : ton métier, en un mot").foregroundStyle(IslandTheme.faint))
                    .textFieldStyle(.plain)
                    .font(IslandTheme.text(13, .regular))
                    .foregroundStyle(IslandTheme.fg)
                    .onSubmit(done)
                RoundButton(style: .white, symbol: "arrow.up", label: loc("C'est parti"), small: true, action: done)
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 19).fill(Color.white.opacity(0.1)))
            .riseIn(3)
            TextButton(label: loc("Plus tard")) { IslandActions.go(.overview) }
                .riseIn(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func done() {
        let profiles = WorkProfiles.all.filter { chosen.contains($0.id) }
        IslandActions.chooseProfiles(profiles, freeAnswer: other)
    }

    /// A coding agent on this Mac: "Je code" is ticked in advance.
    static func codingAgentInstalled() -> Bool {
        // Filming: nothing of the Mac is read.
        guard !StudioMode.isOn else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return EngineFactory.hasClaudeCode
            || [".codex", ".gemini"].contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }
}

/// Buttons laid out in lines, wrapping when a line is full.
struct ProfileFlow: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            line = max(line, size.height)
        }
        return CGSize(width: min(widest, width), height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
