import AppKit
import SwiftUI

// The everyday settings, without leaving the island (`.set` in the mock-up): sounds and
// their volume, how long before the island folds back, and what he holds while an agent
// works. They act at once.

struct SettingsActivity: View {
    @ObservedObject var state: AppState
    @AppStorage(IslandPrefs.workHabitKey) private var workHabit = YumiWorkHabit.current().rawValue
    @State private var githubToken = ""
    @ObservedObject private var updates = YumiUpdates.shared
    @State private var githubConnected = IslandActions.githubConnected
    /// How much he speaks first (Contracts/RemarkTypes.swift).
    @AppStorage(YumiTalk.defaultsKey) private var talk = YumiTalk.discreet.rawValue
    private static let talks: [(value: YumiTalk, label: String)] =
        [(.silent, loc("Silencieux")), (.discreet, loc("Discret")), (.chatty, loc("Bavard"))]

    /// `foldDelay`: seconds, 0 for never.
    private static let delays: [(seconds: TimeInterval, label: String)] =
        [(5, "5 s"), (15, "15 s"), (30, "30 s"), (60, "1 min"), (0, loc("Jamais"))]

    var body: some View {
        VStack(spacing: 9) {
            row(loc("Mes sons")) {
                Slider(value: $state.soundVolume, in: 0...0.2) { editing in
                    if !editing { SoundEngine.shared.play("pop") }
                }
                .controlSize(.mini)
                .tint(.white)
                .frame(width: 96)
                .disabled(!state.soundEnabled)
                .opacity(state.soundEnabled ? 1 : 0.35)
                .accessibilityLabel("Volume")
                IslandToggle(isOn: $state.soundEnabled, label: loc("Sons"))
            }
            .riseIn(0)
            row(loc("Je me replie après")) {
                HStack(spacing: 0) {
                    ForEach(Self.delays, id: \.seconds) { delay in
                        SegmentButton(label: delay.label, on: selected == delay.seconds) {
                            state.autoCloseInterval = delay.seconds
                            IslandActions.tap()
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(1)
            row(loc("Quand un agent bosse")) {
                HStack(spacing: 0) {
                    ForEach(YumiWorkHabit.allCases, id: \.self) { choice in
                        SegmentButton(label: choice.label, on: workHabit == choice.rawValue) {
                            workHabit = choice.rawValue
                            IslandActions.tap()
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(2)
            row(loc("Yumi parle")) {
                HStack(spacing: 0) {
                    ForEach(Self.talks, id: \.value) { choice in
                        SegmentButton(label: choice.label, on: talk == choice.value.rawValue) {
                            talk = choice.value.rawValue
                            IslandActions.tap()
                        }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
            }
            .riseIn(3)
            row("GitHub") {
                if githubConnected {
                    Text("Branché")
                        .font(IslandTheme.text(11.5, .medium))
                        .foregroundStyle(IslandTheme.green)
                    TextButton(label: loc("Retirer")) {
                        IslandActions.connectGitHub(nil)
                        githubConnected = false
                    }
                } else {
                    HStack(spacing: 4) {
                        SecureField("", text: $githubToken, prompt: Text("Colle ton jeton d'accès").foregroundStyle(IslandTheme.faint))
                            .textFieldStyle(.plain)
                            .font(IslandTheme.text(12, .regular))
                            .foregroundStyle(IslandTheme.fg)
                            .frame(width: 170)
                            .onSubmit(connectGitHub)
                        RoundButton(style: .white, symbol: "checkmark", label: loc("Brancher"), small: true, action: connectGitHub)
                            .scaleEffect(0.8)
                    }
                    .padding(.leading, 10)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.1)))
                }
            }
            .riseIn(4)
            row(loc("Ce que je sais de toi")) {
                TextButton(label: state.memory.isEmpty ? loc("Voir") : loc("Voir (\(state.memory.count))")) { IslandActions.go(.memory) }
            }
            .riseIn(3)
            row("Yumi \(YumiUpdates.installed)") {
                if let newer = updates.newer {
                    TextButton(label: loc("\(newer.tag) est là")) { updates.openRelease() }
                }
                TextButton(label: loc("Envoyer un retour")) {
                    if let url = YumiUpdates.feedbackURL() { NSWorkspace.shared.open(url) }
                }
            }
            .riseIn(5)
            row(loc("Préviens-moi des nouvelles versions")) {
                IslandToggle(isOn: Binding(get: { updates.enabled }, set: { updates.enabled = $0 }), label: loc("Nouvelles versions"))
            }
            .riseIn(6)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity)
    }

    private func connectGitHub() {
        guard let token = GitHubFigures.cleanToken(githubToken) else { return }
        IslandActions.connectGitHub(token)
        githubToken = ""
        githubConnected = true
    }

    /// The choice that matches the stored delay; an older value falls on the nearest one.
    private var selected: TimeInterval {
        let value = state.autoCloseInterval
        if value <= 0 { return 0 }
        return Self.delays.filter { $0.seconds > 0 }.min { abs($0.seconds - value) < abs($1.seconds - value) }?.seconds ?? 15
    }

    /// `.srow`
    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(IslandTheme.text(12.5, .medium))
                .foregroundStyle(IslandTheme.fg)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 10) { control() }
        }
    }
}

/// `.tgl`
struct IslandToggle: View {
    @Binding var isOn: Bool
    let label: String

    var body: some View {
        Button {
            isOn.toggle()
            IslandActions.tap()
        } label: {
            Capsule()
                .fill(isOn ? IslandTheme.green : Color.white.opacity(0.2))
                .frame(width: 34, height: 20)
                .overlay(alignment: .leading) {
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .offset(x: isOn ? 16 : 2)
                }
                .animation(.islandSpring(0.25), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? loc("activé") : loc("désactivé"))
    }
}

/// `.seg button`
struct SegmentButton: View {
    let label: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(IslandTheme.text(11, .semibold))
                .monospacedDigit()
                .foregroundStyle(on ? Color.white : IslandTheme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(on ? 0.22 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
