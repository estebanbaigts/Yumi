import Foundation

/// The Mac's side of the link with the iPhone (Contracts/YumiLink.swift). Off unless this build
/// carries an iCloud container and the person turned it on in the settings.
///
/// It publishes a summary of what the island already shows (sessions, coding agents' requests
/// waiting, GitHub), and reads the answers given on the iPhone. An answer is checked again by
/// `HookServer.answerFromLink` against what is really waiting before anything happens.
@MainActor
final class MacLink {
    static let shared = MacLink()

    private var loop: Task<Void, Never>?
    private var lastPublished: LinkSnapshot?
    private var lastPublishedAt = Date.distantPast

    func start() {
        guard loop == nil, YumiLinks.isBuiltIn, !StudioMode.isOn else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let waiting = await self?.tick() ?? false
                // Every 4 s: the iPhone may answer a request or ask Yumi something. Reading an
                // unchanged zone costs almost nothing; the picture itself is sent only when it changed.
                _ = waiting
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    /// One round: publish when something changed, read the answers. True when a request waits.
    private func tick() async -> Bool {
        let link = YumiLinks.current()
        guard await link.isAvailable() else {
            Self.trace("link not available (setting \(LinkSetting.isOn()), built in \(YumiLinks.isBuiltIn))")
            return false
        }
        let snapshot = Self.snapshot()
        var compared = snapshot
        compared.sentAt = lastPublished?.sentAt ?? snapshot.sentAt
        // A picture that did not change is sent again once a minute, so the iPhone knows the Mac is there
        if compared != lastPublished || Date().timeIntervalSince(lastPublishedAt) > 60 {
            do {
                try await link.publish(snapshot)
                lastPublished = snapshot
                lastPublishedAt = Date()
            } catch {
                Self.trace("publish failed: \(error)")
                return !snapshot.approvals.isEmpty
            }
            Self.trace("published \(snapshot.sessions.count) sessions, \(snapshot.approvals.count) requests")
        }
        for ask in (try? await link.takeAsks()) ?? [] {
            Task { await Self.think(about: ask, link: link) }
        }
        for reply in (try? await link.takeReplies()) ?? [] {
            if reply.approvalID == LinkHello.id { Self.hello(from: reply.fingerprint); continue }
            HookServer.shared.answerFromLink(reply)
        }
        return !snapshot.approvals.isEmpty
    }

    /// What the iPhone asked, answered with the person's own Claude Code: the conversation only,
    /// as a model (no tool, no file, no action: `ClaudeCodeLLMProvider`).
    private static func think(about ask: LinkAsk, link: any YumiLink) async {
        trace("ask \(ask.id)")
        var answer = LinkAnswer(askID: ask.id, text: nil, failure: nil)
        if let provider = thinker {
            let messages = ask.lines.map { LLMMessage(role: $0.fromPerson ? .user : .assistant, content: $0.text) }
            do {
                let response = try await provider.complete(LLMRequest(system: ask.system, messages: messages,
                                                                      expectsJSON: false, maxOutputTokens: 900, fast: true))
                answer.text = response.text
            } catch {
                answer.failure = loc("Claude Code n'a pas pu répondre sur ton Mac.")
            }
        } else {
            answer.failure = loc("Claude Code n'est pas installé sur ton Mac.")
        }
        try? await link.answer(answer)
        trace("answered \(ask.id): \(answer.text == nil ? "failed" : "ok")")
    }

    /// Claude Code as a model, when this build may run it and it is installed.
    private static var thinker: (any LLMProvider)? {
        #if APPSTORE
        return nil
        #else
        guard ClaudeCLI.find() != nil else { return nil }
        return EngineFactory.provider(.claudeCode, EngineSettings.load())
        #endif
    }

    /// The iPhone just found this Mac: the island says so, happy, with a sound.
    private static func hello(from phone: String) {
        trace("hello from \(phone)")
        let state = AppState.shared
        let remark = YumiRemark(id: "link-hello-\(Date().timeIntervalSince1970)",
                                text: loc("C'est bon, on est connectés avec \(phone.isEmpty ? "ton iPhone" : phone)."), mood: .happy, duration: 7)
        state.remark = remark
        SoundEngine.shared.play("love")
        // The celebration of the island: surprised, then joy, confetti and stars, he jumps for it
        let center = NotificationCenter.default
        center.post(name: .yumiMood, object: YumiMood.surprised)
        center.post(name: .yumiRim, object: YumiRimTone.joy)
        center.post(name: .yumiPose, object: YumiPose.pop)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            center.post(name: .yumiMood, object: YumiMood.happy)
            center.post(name: .yumiScene, object: YumiScene.release)
            center.post(name: .yumiPose, object: YumiPose.celebrate)
            try? await Task.sleep(for: .milliseconds(1800))
            center.post(name: .yumiScene, object: YumiScene.star)
            try? await Task.sleep(for: .seconds(3))
            center.post(name: .yumiMood, object: nil)
            center.post(name: .yumiRim, object: nil)
        }
        Task { @MainActor [weak state] in
            try? await Task.sleep(for: .seconds(remark.duration))
            if state?.remark?.id == remark.id { state?.remark = nil }
        }
    }

    /// `YUMI_TRACE_LINK=1` (Debug): what the link does, in the console.
    private static func trace(_ text: @autoclosure () -> String) {
        #if DEBUG
        if ProcessInfo.processInfo.environment["YUMI_TRACE_LINK"] == "1" { FileHandle.standardError.write(Data("[link] \(text())\n".utf8)) }
        #endif
    }

    private static func snapshot() -> LinkSnapshot {
        let state = AppState.shared
        let sessions = state.tasks.filter { !$0.isIntegration || $0.state != .idle }.map { task in
            LinkSession(id: task.id, agent: task.agentName, project: task.name,
                        status: status(of: task.state), updatedAt: Date())
        }
        let github = state.modules.first { $0.id == "github" }.map { [$0.title, $0.subtitle].filter { !$0.isEmpty } } ?? []
        return LinkSnapshot(deviceName: Host.current().localizedName ?? "Mac", sentAt: Date(),
                            sessions: sessions, approvals: HookServer.shared.linkWaiting(), github: github,
                            thinks: thinker == nil ? [] : ["claude-code"])
    }

    private static func status(of state: BotState) -> String {
        switch state {
        case .working, .thinking, .searching: loc("travaille")
        case .approval: loc("attend ton accord")
        case .question: loc("te pose une question")
        case .error, .ratelimit: loc("bloqué")
        case .finished: loc("terminé")
        case .idle, .sleeping, .dizzy: loc("au repos")
        }
    }
}
