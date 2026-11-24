import SwiftUI

// MARK: - Approval (★ Proposition, `approbation`)
//
// Centred: who asks, on which model and where, the command, what it does; then Refuser in red,
// Yumi in the middle, Autoriser in green. The answers are the same as before: they go through
// HookServer, and what cannot be undone is never offered "always".

struct ApprovalPage: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: IslandModel
    private let amber = IslandTheme.amber

    /// The agent's line of the Agents module for this session: its model, repository and branch.
    private func session(_ id: String) -> ModuleRow? {
        state.modules.first { $0.id == IslandModel.agentModuleID }?.rows.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let approval = state.pendingApproval, approval.agentRequest == nil {
                hook(approval)
            } else {
                // Yumi's own agent, or a question asked in a session: the card that already says it
                HStack(spacing: 14) {
                    YumiSlot(width: 64)
                    AlertActivity(state: state, model: model)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: IslandHome.height)
    }

    private func hook(_ approval: ApprovalInfo) -> some View {
        let row = session(approval.sessionId)
        let agent = row?.agent ?? loc("Claude Code")
        let reading = AgentRequestReader.read(tool: approval.tool, command: approval.command)
        let shell = ClaudeToolPhrase.label(for: approval.tool) == loc("Exécute")
        let place = [row?.model, row?.place].compactMap { $0 }.joined(separator: " · ")
        return VStack(spacing: 0) {
            Text((shell ? loc("\(agent) veut lancer une commande") : loc("\(agent) veut \(reading.action)")).uppercased())
                .font(IslandTheme.text(11, .bold)).tracking(0.9)
                .foregroundStyle(amber)
            if !place.isEmpty || row?.branch != nil {
                Text(place + (row?.branch.map { " ⎇ \($0)" } ?? ""))
                    .font(IslandTheme.text(12))
                    .foregroundStyle(Color(hex: "#8E8E93"))
                    .padding(.top, 2)
            }
            Text(approval.command.isEmpty ? approval.tool : approval.command)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color(hex: "#FFE3B0"))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(amber.opacity(0.12)))
                .padding(.top, 10)
            if let undo = reading.undo {
                Text(undo).font(IslandTheme.text(12)).foregroundStyle(Color(hex: "#B9BCC8")).padding(.top, 6)
            }
            HStack(spacing: 46) {
                pin("xmark", loc("Refuser"), color: Color(hex: "#FF453A")) {
                    HookServer.shared.sendApprovalDecision("deny", for: approval.requestID)
                }
                YumiSlot(width: 66)
                pin("checkmark", loc("Autoriser"), color: Color(hex: "#30D158")) {
                    HookServer.shared.sendApprovalDecision("allow", for: approval.requestID)
                }
            }
            .padding(.top, 12)
            HStack(spacing: 14) {
                // What cannot be undone or leaves the Mac is allowed one time at most.
                if reading.risk < .high {
                    link(loc("Toujours autoriser \(Self.short(approval))")) {
                        HookServer.shared.sendApprovalDecision("always", for: approval.requestID)
                    }
                }
                if let open = ClaudeTaskMirror.openLabel(session: approval.sessionId) {
                    link(open) { ClaudeTaskMirror.openSession(approval.sessionId) }
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// "git push" for `git push origin main`, else the tool's name.
    static func short(_ approval: ApprovalInfo) -> String {
        let words = approval.command.split(separator: " ").prefix(2).joined(separator: " ")
        return words.isEmpty ? approval.tool : words
    }

    /// `pPin`: a round button in its colour, glowing, its label under it.
    private func pin(_ symbol: String, _ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Circle().fill(color))
                    .shadow(color: color.opacity(0.47), radius: 12)
                Text(label).font(IslandTheme.text(12, .semibold)).foregroundStyle(color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func link(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(IslandTheme.text(11.5)).foregroundStyle(Color(hex: "#8E8E93")).underline()
        }
        .buttonStyle(.plain)
    }
}
