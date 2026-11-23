import Foundation
import Security

// MARK: - Keychain helpers

enum Keychain {
    static let service = AppIdentity.keychainService

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        // Delete existing item first (update pattern)
        let lookup: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(lookup as CFDictionary)
        // Add with strictest access control:
        // WhenUnlockedThisDeviceOnly = accessible only while Mac is unlocked,
        // never synced to iCloud, never migrated to another device.
        let item: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      key,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
        ]
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Keychain cache (reads each key ONCE at launch; all subsequent access via dict)

final class KeychainStore: @unchecked Sendable {
    static let shared = KeychainStore()
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private static let allKeys = [
        "anthropic-api-key",
        "openai-api-key",
        "gemini-api-key",
        "github-token",
        // The GitHub App's user access token and refresh token, as JSON (Modules/GitHub/GitHubApp.swift).
        "github-app-token",
        // Not "notion-api-key": that old name is erased once at launch.
        "notion-integration-key",
        "gmail-app-password",
    ]

    /// Keys of the old integrations, removed from Yumi: erased once.
    static let retiredKeys = ["resend-api-key", "resend-from", "n8n-url", "n8n-api-key",
                              "vercel-token", "stripe-api-key", "calcom-api-key", "notion-api-key"]

    private init() {
        // Called once, on main thread (AppDelegate triggers shared at launch).
        // While filming, nothing is read: every secret is simply absent.
        guard LaunchPlan.current.keychain else { return }
        for key in Self.allKeys {
            if let v = Keychain.load(key: key) { cache[key] = v }
        }
    }

    /// Thread-safe read — never touches the Keychain.
    func get(_ key: String) -> String? {
        lock.withLock { cache[key] }
    }

    /// Updates cache + persists to Keychain.
    func set(_ key: String, value: String) {
        lock.withLock { cache[key] = value }
        // While filming the value only lives for the run: the Keychain is not touched.
        guard LaunchPlan.current.keychain else { return }
        Keychain.save(key: key, value: value)
    }

    /// Erases the retired keys from the Keychain, once (a flag in the defaults remembers it).
    func eraseRetiredKeys(defaults: UserDefaults = .standard) {
        let done = "retiredKeysErased"
        guard LaunchPlan.current.keychain, !defaults.bool(forKey: done) else { return }
        for key in Self.retiredKeys { Keychain.delete(key: key) }
        for key in ["vercelProjectFilter", "n8nWorkflowFilter", "activeIntegrations"] { defaults.removeObject(forKey: key) }
        defaults.set(true, forKey: done)
    }

    /// Removes from cache + Keychain only if the key was previously set.
    func remove(_ key: String) {
        let had = lock.withLock { () -> Bool in
            let exists = cache[key] != nil
            cache[key] = nil
            return exists
        }
        if had, LaunchPlan.current.keychain { Keychain.delete(key: key) }
    }
}

// MARK: - Chat
// The chat drives the Claude Code installed on the Mac (see Core/Chat): the user's subscription
// instead of a key billed by use, and the ability to act. The API remains the fallback when
// Claude Code is not installed, and the only path of the App Store build, which may not launch
// other programs.

@MainActor
final class ClaudeService {
    static let shared = ClaudeService()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"
    /// The Anthropic model of the settings (section Moteurs).
    private var model: String { EngineSettings.load().model(.anthropic) ?? "claude-sonnet-4-6" }

    var apiKey: String? { KeychainStore.shared.get("anthropic-api-key") }

    /// What Yumi remembers. Every conversation is told the first name and the memories, and
    /// what it learns goes back there. Set once by the core.
    var memory: MemoryStore?

    // Multi-turn conversation messages (for API)
    private var conversationMessages: [[String: Any]] = []
    /// Messages the agent runtime answered that Claude Code has not seen yet: given with the next
    /// message, so the chat keeps its thread.
    private var unseenTurns: [(person: String, yumi: String)] = []

    #if !APPSTORE
    // Claude Code conversation: the session to resume, and the folder it belongs to
    private var session: (id: String, folder: String)?
    /// What was attached to the last message, so the same attachment is not repeated at every message.
    private var sentContext: ChatContext?
    /// Folders outside the chat folder that Claude Code may read: where attached files are.
    private var readableFolders: [String] = []
    private var turn: ClaudeCodeTurn?
    /// Messages answered in the current conversation.
    private var answeredTurns = 0
    /// Memories written during the current conversation.
    private var notedThisConversation: Set<String> = []
    #endif

    /// Ends the conversation. Unless `remember` is false (the app is closing), a conversation of
    /// some length leaves a short summary in the thread of the memory.
    func clearConversation(remember: Bool = true) {
        guard LaunchPlan.current.chat else { return }
        conversationMessages = []
        providerConversation = []
        unseenTurns = []
        #if !APPSTORE
        if remember, answeredTurns >= 1, turn == nil, let session, let binary = ClaudeCLI.find() {
            summarize(session: session.id, folder: session.folder, binary: binary, noted: notedThisConversation)
        }
        answeredTurns = 0
        notedThisConversation = []
        turn?.cancel()
        turn = nil
        session = nil
        sentContext = nil
        readableFolders = []
        #endif
    }

    /// The API path speaks with the same voice, without a folder to work in.
    private var systemPrompt: String {
        ChatPhrases.systemPrompt(characterName: AppIdentity.characterName, folder: "aucun (tu ne peux pas agir sur le Mac ici, seulement chercher sur le web)")
    }

    private let webSearchTools: [[String: Any]] = [
        ["type": "web_search_20250305", "name": "web_search", "max_uses": 5]
    ]

    // MARK: - Chat (multi-turn)

    func chat(query: String, context: PromptContext?, state: AppState) async {
        // While filming the chat is the island's to stage: nothing is launched, nothing is sent.
        guard LaunchPlan.current.chat else { return }
        // "Montre-moi…", "Où est…": he looks at the screen once and points (App/ShowMeController).
        if ShowMe.wants(query) {
            await ShowMeController.shared.answer(query, state: state)
            return
        }
        if await runAsAgent(query: query, state: state) { return }
        // The engine of the settings, or the first available in their order (EngineSettings).
        // Whichever answers, the chat has no tool that changes the Mac.
        let settings = EngineSettings.load()
        for engine in settings.sequence {
            switch engine {
            case .claudeCode:
                #if !APPSTORE
                if let binary = ClaudeCLI.find() {
                    await chatWithClaudeCode(binary: binary, query: query, context: context, state: state)
                    return
                }
                #endif
            case .anthropic:
                if let key = apiKey, !key.isEmpty {
                    await chatWithAPI(query: query, context: context, state: state)
                    return
                }
            case .simple:
                await answerSimply(state: state)
                return
            case .openai, .gemini, .ollama, .apple:
                if let provider = EngineFactory.provider(engine, settings),
                   await chatWithProvider(provider, engine: engine, query: query, context: context, state: state) {
                    return
                }
            }
        }
        if settings.choice == .apple, let message = AppleModelAvailability.current.message {
            await showError(message, state: state)
            return
        }
        await showError(settings.choice == nil ? ChatPhrases.noEngine : ChatPhrases.chosenEngineMissing(settings.choice!.label), state: state)
    }

    // MARK: - Chat without a model

    /// The simple mode did not understand a message, and no model can talk: Yumi says so kindly
    /// and offers what he can do, as buttons.
    private func answerSimply(state: AppState) async {
        state.chatHistory.append(ChatMessage(role: .assistant, content: SimpleReply.notUnderstood + "\n" + SimpleReply.plugLater,
                                             engine: Engine.simple.shortLabel, suggestions: SimpleReply.suggestions))
        state.stateOverride = nil
        state.view = .prompt
    }

    // MARK: - Chat through another engine

    /// The conversation with OpenAI, Gemini or Ollama: text only, no tool of any kind.
    private var providerConversation: [LLMMessage] = []

    /// One turn with a provider. False when it is not configured (the next engine is tried);
    /// any other failure is said to the person.
    private func chatWithProvider(_ provider: any LLMProvider, engine: Engine, query: String,
                                  context: PromptContext?, state: AppState) async -> Bool {
        let attached = providerConversation.isEmpty ? Self.chatContext(from: context) : nil
        let message = LLMMessage(role: .user, content: ChatPhrases.message(query: query, context: attached))
        let system = ChatPhrases.engineSystemPrompt(characterName: AppIdentity.characterName)
            + (memory.map { "\n\n" + MemoryPrompt.knowledge($0.book) + "\n\n" + MemoryNotes.instructions } ?? "")
        let request = LLMRequest(system: system, messages: providerConversation + [message], expectsJSON: false, maxOutputTokens: 1500)
        do {
            let answer = try await provider.complete(request)
            let (visible, learnt) = MemoryNotes.extract(from: answer.text)
            if !learnt.isEmpty { memory?.change { MemoryNotes.apply(learnt, to: &$0) } }
            guard !visible.isEmpty else {
                await showError(ChatPhrases.noAnswer, state: state)
                return true
            }
            providerConversation += [message, LLMMessage(role: .assistant, content: visible)]
            state.chatHistory.append(ChatMessage(role: .assistant, content: visible, engine: engine.shortLabel))
            state.stateOverride = nil
            state.view = .prompt
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            return true
        } catch LLMProviderError.unavailable {
            return false
        } catch LLMProviderError.failed(let reason) {
            await showError(ChatPhrases.engineFailed(engine.label, reason: reason), state: state)
            return true
        } catch {
            await showError(ChatPhrases.network, state: state)
            return true
        }
    }

    // MARK: - Chat through the agent runtime

    /// A message that asks Yumi to change something on the Mac is planned, approved, run and
    /// verified by the runtime; the chat only shows it. A clear action no tool can do is refused
    /// here. Anything else (no key, a question, an unclear request, a plan that only reads)
    /// returns false and goes to the conversation, which cannot change the Mac (ChatTools). What is on screen
    /// stays on the Mac: the planner does not see it.
    private func runAsAgent(query: String, state: AppState) async -> Bool {
        guard let agent = state.agent else { return false }
        let request = AgentRequest(userIntent: query, context: state.context.isEnabled ? state.context : nil,
                                   conversation: Self.turns(before: query, in: state.chatHistory))
        // Busy: no plan now, but a question about the agenda still never goes to the chat.
        let planned: Result<AgentPlan, AgentError>? = agent.isRunning ? .failure(.busy) : await agent.plan(for: request)
        let plan: AgentPlan
        switch ChatRoute.route(planned, message: query) {
        case .chat:
            return false
        case .agendaKeptFromChat(let error):
            let text = error == .busy ? AgentLook.busy : AgentLook.agendaKeptFromChat(error)
            state.chatHistory.append(ChatMessage(role: .assistant, content: text))
            remember(query, answeredWith: text)
            state.stateOverride = nil
            state.view = .prompt
            return true
        case .blocked(let reason):
            let result = AgentResult(runID: request.id, status: .failed, goal: nil, steps: [],
                                     error: .unsupportedAction(reason), finishedAt: Date())
            let text = AgentLook.remark(for: result)?.text ?? ""
            state.chatHistory.append(ChatMessage(role: .assistant, content: text))
            remember(query, answeredWith: text)
            state.stateOverride = nil
            state.view = .prompt
            return true
        case .agent(let accepted):
            plan = accepted
        }
        if plan.steps.contains(where: \.requiresApproval) {
            state.chatHistory.append(ChatMessage(role: .assistant, content: loc("Je m'en occupe : \(plan.goal). Je te demande avant de toucher à quoi que ce soit.")))
            state.view = .prompt
        }
        let result = await agent.execute(plan, for: request)
        let text = AgentLook.remark(for: result)?.text ?? loc("C'est annulé, je n'ai rien fait.")
        state.chatHistory.append(ChatMessage(role: .assistant, content: text, engine: Engine.named(plan.plannedBy)?.shortLabel))
        remember(query, answeredWith: text)
        state.view = .prompt
        return true
    }

    /// The chat before this message, for the planner: the words only.
    static func turns(before query: String, in history: [ChatMessage]) -> [ConversationTurn] {
        var earlier = history
        if let last = earlier.last, last.role == .user, last.content == query { earlier.removeLast() }
        return earlier.map { ConversationTurn(role: $0.role == .user ? .person : .yumi, text: $0.content) }
    }

    /// An exchange the runtime answered joins the conversation the chat model keeps.
    private func remember(_ query: String, answeredWith text: String) {
        unseenTurns.append((query, text))
        providerConversation += [LLMMessage(role: .user, content: query), LLMMessage(role: .assistant, content: text)]
        // The API conversation alternates user and assistant: the pair goes in whole.
        if (conversationMessages.last?["role"] as? String) != "user" {
            conversationMessages.append(["role": "user", "content": [["type": "text", "text": query]]])
            conversationMessages.append(["role": "assistant", "content": [["type": "text", "text": text]]])
        }
    }

    // MARK: - Chat through Claude Code

    #if !APPSTORE
    private func chatWithClaudeCode(binary: String, query: String, context: PromptContext?, state: AppState) async {
        // A message sent while the previous one is still being answered replaces it.
        turn?.cancel()

        let folder = ChatFolder.path(stored: UserDefaults.standard.string(forKey: ChatFolder.key))
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        } catch {
            await showError(ChatPhrases.noFolder, state: state)
            return
        }
        // A session belongs to the folder it was started in: another folder is another conversation.
        if let session, session.folder != folder {
            self.session = nil
            sentContext = nil
        }

        let attached = Self.chatContext(from: context)
        // A dropped file is copied to Yumi's inbox: that folder, and only that one, is opened for
        // reading. A file anywhere else is read through an ordinary permission request.
        let inbox = AppIdentity.inboxDirectory.path
        if case .file(_, let path?) = attached, ChatFolder.contains(path, in: inbox), !readableFolders.contains(inbox) {
            readableFolders.append(inbox)
        }
        let message = ChatPhrases.earlierTurns(unseenTurns, before: ChatPhrases.message(query: query, context: attached == sentContext ? nil : attached))

        var outcome = await runTurn(binary: binary, message: message, folder: folder, state: state)
        if outcome == .unknownSession {
            // The session to resume is gone (its history was removed): start again, attachment included.
            session = nil
            outcome = await runTurn(binary: binary, message: ChatPhrases.earlierTurns(unseenTurns, before: ChatPhrases.message(query: query, context: attached)),
                                    folder: folder, state: state)
        }
        if outcome == .answered {
            sentContext = attached
            unseenTurns = []
        }
    }

    /// Asks the conversation that just ended for a few lines about itself, and keeps them in the
    /// thread. It runs on its own after the conversation was cleared; the plain non-interactive
    /// mode refuses every tool that needs a permission, so nothing can be done behind the person's back.
    private func summarize(session: String, folder: String, binary: String, noted: Set<String>) {
        // The system prompt is not kept with a session: without it the summary would lose the voice and the rules.
        var arguments = ["-p", MemoryNotes.summaryRequest, "--resume", session, "--output-format", "json", "--permission-mode", "default",
                         "--append-system-prompt", ChatPhrases.systemPrompt(characterName: AppIdentity.characterName, folder: folder, memory: memory?.book)]
            + ChatTools.arguments
        #if DEBUG
        arguments += (ProcessInfo.processInfo.environment["YUMI_CHAT_ARGS"] ?? "").split(separator: " ").map(String.init)
        #endif
        let environment = ClaudeCLI.environment(from: ProcessInfo.processInfo.environment, binary: binary)
        Task.detached(priority: .utility) { [weak self] in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: binary)
            process.arguments = arguments
            process.environment = environment
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return }
            // A summary that takes too long is not worth waiting for.
            let limit = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 60, execute: limit)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            limit.cancel()
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["is_error"] as? Bool != true, let text = object["result"] as? String else { return }
            let changes = MemoryNotes.extract(from: text, unknownKindAs: .thread).changes
            guard !changes.isEmpty else { return }
            await MainActor.run {
                self?.memory?.change { MemoryNotes.applySummary(changes, to: &$0, noted: noted) }
            }
        }
    }

    private enum TurnOutcome { case answered, failed, cancelled, unknownSession }

    /// Sends one message to Claude Code and follows the answer until the turn ends.
    private func runTurn(binary: String, message: String, folder: String, state: AppState) async -> TurnOutcome {
        let target: ClaudeCLI.Session = session.map { .resume($0.id) } ?? .new(UUID().uuidString.lowercased())
        // From now on the hooks of this session are left to the chat (see HookServer).
        ChatSessionRegistry.shared.insert(target.id)

        var extra: [String] = []
        #if DEBUG
        // Development only: extra arguments, e.g. to keep the user's own settings out of a test run.
        extra = (ProcessInfo.processInfo.environment["YUMI_CHAT_ARGS"] ?? "").split(separator: " ").map(String.init)
        #endif
        let turn = ClaudeCodeTurn(
            binary: binary,
            arguments: ClaudeCLI.arguments(
                session: target,
                systemPrompt: ChatPhrases.systemPrompt(characterName: AppIdentity.characterName, folder: folder,
                                                       memory: memory?.book),
                readableFolders: readableFolders, extra: extra),
            environment: ClaudeCLI.environment(from: ProcessInfo.processInfo.environment, binary: binary),
            folder: folder)
        self.turn = turn
        defer { if self.turn === turn { self.turn = nil } }

        guard let lines = turn.start(message: message) else {
            await showError(ChatPhrases.stopped, state: state)
            return .failed
        }

        var transcript = ChatTranscript()
        var waiting: Set<String> = []
        /// The requests still waiting, to write in the history how they ended.
        var asked: [String: ChatPermissionRequest] = [:]
        // Every request of the chat goes in the same history as the agent's own decisions.
        func record(_ request: ChatPermissionRequest, _ outcome: ChatPermissionAudit.Outcome) {
            state.permissions?.audit.record(ChatPermissionAudit.entry(tool: request.toolName, input: request.inputJSON,
                                                                      outcome: outcome, date: Date()))
        }
        var result: ChatTurnResult?

        // The answer in progress, for the island (Contracts/ChatLive.swift). Words arrive by the
        // dozen per second: the island is told at most ten times a second, and always gets the last state.
        var tracker = ChatLiveTracker()
        var throttle = PublishThrottle()
        var pending: Task<Void, Never>?
        func publishLive() {
            let delay = throttle.delay(now: Date())
            if delay == 0 {
                pending?.cancel()
                pending = nil
                throttle.published(at: Date())
                if state.chatLive != tracker.live { state.chatLive = tracker.live }
            } else if pending == nil {
                pending = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    pending = nil
                    publishLive()
                }
            }
        }
        state.chatLive = tracker.live
        defer {
            pending?.cancel()
            // Unless another message took over, the answer is no longer in progress.
            if self.turn === turn || self.turn == nil { state.chatLive = nil }
        }

        var learnt: [MemoryChange] = []
        reading: for await line in lines {
            // A cancelled turn only waits for its process to end: what it still says changes nothing.
            if turn.isCancelled { continue }
            for rawEvent in ClaudeStream.events(fromLine: line) {
                // What the conversation decided to remember is taken out of what the person reads.
                var event = rawEvent
                if case .text(let text) = rawEvent {
                    let (visible, changes) = MemoryNotes.extract(from: text)
                    learnt += changes
                    if visible.isEmpty { continue }
                    event = .text(visible)
                } else if case .finished(var turnResult) = rawEvent {
                    let (visible, changes) = MemoryNotes.extract(from: turnResult.text)
                    learnt += changes
                    turnResult.text = visible
                    event = .finished(turnResult)
                }
                tracker.apply(event)
                // Text followed by an action goes to the history before the line of that action,
                // so nothing written along the way is lost when the answer is complete.
                let lines = transcript.apply(event)
                if !lines.isEmpty {
                    state.chatHistory.append(contentsOf: lines.map { ChatMessage(role: .assistant, content: $0) })
                    tracker.textCommitted()
                }
                publishLive()
                switch event {
                case .started(let id):
                    session = (id, folder)

                case .messageStarted, .textDelta, .toolAnnounced, .text:
                    break

                case .toolStarted:
                    state.stateOverride = .working

                case .toolFinished:
                    if state.stateOverride == .working { state.stateOverride = .thinking }

                case .permissionRequested(let request) where !ChatTools.mayUse(request.toolName):
                    // A tool that changes the Mac has nothing to do in the chat: refused without
                    // asking, so a click can never let it through the permission manager's back.
                    turn.send(ClaudeStream.answerLine(to: request, .deny(message: ChatPhrases.actionsGoThroughYumi)))
                    record(request, .blocked)
                    tracker.permissionAnswered(toolUseID: request.toolUseID, allowed: false)
                    transcript.refuse(toolUseID: request.toolUseID)

                case .permissionRequested(let request):
                    // The request is shown in the island like the ones of any Claude Code session;
                    // the answer goes back to the process, which waits for it.
                    waiting.insert(request.requestID)
                    asked[request.requestID] = request
                    HookServer.shared.presentChatApproval(
                        id: request.requestID, session: target.id, tool: request.toolName, command: request.summary
                    ) { [weak turn] decision in
                        let answer = ChatPermissionDecision(islandAnswer: decision)
                        turn?.send(ClaudeStream.answerLine(to: request, answer))
                        if asked.removeValue(forKey: request.requestID) != nil {
                            record(request, ChatPermissionAudit.outcome(islandAnswer: decision))
                        }
                        var allowed = true
                        if case .deny = answer { allowed = false }
                        tracker.permissionAnswered(toolUseID: request.toolUseID, allowed: allowed)
                        if turn != nil { publishLive() }
                        if case .deny = answer {
                            transcript.refuse(toolUseID: request.toolUseID)
                            state.stateOverride = .thinking
                        } else {
                            state.stateOverride = .working
                        }
                        waiting.remove(request.requestID)
                    }

                case .permissionCancelled(let requestID):
                    waiting.remove(requestID)
                    if let request = asked.removeValue(forKey: requestID) { record(request, .cancelled) }
                    HookServer.shared.cancelChatApproval(id: requestID)

                case .finished(let turnResult):
                    result = turnResult
                    // The answer is complete. Closing the input ends the process; there is no need
                    // to wait for it before showing the answer.
                    turn.finish()
                    break reading
                }
            }
        }

        // Nothing can answer the requests still on screen. A cancelled turn leaves the view alone.
        let wasCancelled = turn.isCancelled && result == nil
        for requestID in waiting { HookServer.shared.cancelChatApproval(id: requestID, backToChat: !wasCancelled) }
        for request in asked.values { record(request, .cancelled) }

        if wasCancelled {
            // Unless another message took over, the character stops looking busy.
            if self.turn === turn || self.turn == nil,
               [.thinking, .working, .approval].contains(state.stateOverride) {
                state.stateOverride = nil
            }
            return .cancelled
        }
        guard let result else {
            let problem = turn.errorOutput
            await showError(ChatPhrases.isLoginProblem(problem) ? ChatPhrases.notLoggedIn : ChatPhrases.stopped, state: state)
            return .failed
        }
        if let id = result.sessionID, !result.isError { session = (id, folder) }
        if ChatPhrases.isUnknownSession(result), case .resume = target { return .unknownSession }
        if result.isError {
            await showError(ChatPhrases.failure(result), state: state)
            return .failed
        }
        if !learnt.isEmpty, let memory {
            let before = Set(memory.book.entries.map(\.id))
            memory.change { MemoryNotes.apply(learnt, to: &$0) }
            // What this conversation noted: its closing summary must not say it again.
            notedThisConversation.formUnion(Set(memory.book.entries.map(\.id)).subtracting(before))
        }
        answeredTurns += 1
        let last = transcript.finish(result)
        state.chatHistory.append(contentsOf: last.map { ChatMessage(role: .assistant, content: $0, engine: Engine.claudeCode.shortLabel) })
        guard transcript.hasText || !last.isEmpty else {
            await showError(ChatPhrases.noAnswer, state: state)
            return .failed
        }
        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        return .answered
    }

    #endif

    private static func chatContext(from context: PromptContext?) -> ChatContext? {
        switch context {
        case .window(let app, let title, let url): return .window(app: app, title: title, url: url)
        case .file(let name, let fileURL):         return .file(name: name, path: fileURL?.path)
        case nil:                                  return nil
        }
    }

    // MARK: - Chat through the API (natural text + web search)

    private func chatWithAPI(query: String, context: PromptContext?, state: AppState) async {
        guard let key = apiKey, !key.isEmpty else {
            await showError(ChatPhrases.noKey, state: state)
            return
        }

        // Build user content for this turn
        var userContent: [[String: Any]] = []

        // Add file/window context on first message only
        if conversationMessages.isEmpty, let context = context {
            switch context {
            case .window(let app, let title, let url):
                var text = "Context — App: \(app), Window: \(title)"
                if let url = url { text += ", URL: \(url)" }
                userContent.append(["type": "text", "text": text])
            case .file(let name, let fileURL):
                if let fileURL = fileURL, let block = readFileAsBlock(url: fileURL) {
                    userContent.append(block)
                }
                userContent.append(["type": "text", "text": "File: \(name)"])
            }
        }
        userContent.append(["type": "text", "text": query])

        conversationMessages.append(["role": "user", "content": userContent])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "tools": webSearchTools,
            "system": systemPrompt + (memory.map { "\n\n" + MemoryPrompt.knowledge($0.book) + "\n\n" + MemoryNotes.instructions } ?? ""),
            "messages": conversationMessages,
        ]

        do {
            let data = try await callAPI(body: body, key: key, beta: "web-search-2025-03-05")
            await handleChatResult(data, state: state)
        } catch {
            conversationMessages.removeLast()
            await showError(ChatPhrases.network, state: state)
        }
    }

    // MARK: - API call

    private func callAPI(body: [String: Any], key: String, beta: String? = nil) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let beta { request.setValue(beta, forHTTPHeaderField: "anthropic-beta") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 45

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "Claude", code: 0, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return data
    }

    // MARK: - Chat result handler

    private func handleChatResult(_ data: Data, state: AppState) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            await showError(ChatPhrases.unreadable, state: state)
            return
        }

        // Store full content (includes tool_use/tool_result blocks) for correct multi-turn context
        conversationMessages.append(["role": "assistant", "content": content])

        guard let textBlock = content.first(where: { $0["type"] as? String == "text" }),
              let text = textBlock["text"] as? String, !text.isEmpty else {
            await showError(ChatPhrases.noAnswer, state: state)
            return
        }

        // What the conversation decided to remember is taken out of what the person reads.
        let (visible, learnt) = MemoryNotes.extract(from: text)
        if !learnt.isEmpty { memory?.change { MemoryNotes.apply(learnt, to: &$0) } }
        guard !visible.isEmpty else {
            await showError(ChatPhrases.noAnswer, state: state)
            return
        }

        // Add to display history
        state.chatHistory.append(ChatMessage(role: .assistant, content: visible, engine: Engine.anthropic.shortLabel))

        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
    }

    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }

    // MARK: - File content block builder

    private func readFileAsBlock(url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let ext = url.pathExtension.lowercased()
        let base64 = data.base64EncodedString()

        if ext == "pdf" {
            return ["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": base64]]
        } else if ["jpg", "jpeg"].contains(ext) {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": base64]]
        } else if ext == "png" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": base64]]
        } else if ext == "gif" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/gif", "data": base64]]
        } else if ext == "webp" {
            return ["type": "image", "source": ["type": "base64", "media_type": "image/webp", "data": base64]]
        } else {
            // Text/code — inline as text if <= 200 KB
            guard data.count <= 200_000,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            return ["type": "text", "text": "File contents:\n\(text)"]
        }
    }
}

// MARK: - One turn of Claude Code

#if !APPSTORE
/// One `claude -p` process: started with a message, read line by line, written to when a permission
/// request is answered, ended by closing its input. The process and its pipes are only touched
/// from the main actor; its output is read on a background queue and handed over as lines.
@MainActor
private final class ClaudeCodeTurn {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let errorText = ErrorText()
    private var inputClosed = false

    private(set) var isCancelled = false

    /// What the process wrote on its error output (start-up failures are only reported there).
    var errorOutput: String { errorText.value }

    init(binary: String, arguments: [String], environment: [String: String], folder: String) {
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    /// Launches the process and sends the message. Returns the lines of its output, or nil if it could not start.
    func start(message: String) -> AsyncStream<String>? {
        let (lines, continuation) = AsyncStream.makeStream(of: String.self, bufferingPolicy: .unbounded)
        let buffer = LineBox()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                // End of output: the process closed it, or exited.
                handle.readabilityHandler = nil
                if let rest = buffer.flush() { continuation.yield(rest) }
                continuation.finish()
            } else {
                for line in buffer.append(chunk) { continuation.yield(line) }
            }
        }
        let errorText = errorText
        errors.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil } else { errorText.append(chunk) }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            continuation.finish()
            return nil
        }
        send(ClaudeStream.userLine(message))
        return lines
    }

    /// Writes one line on the input of the process. Does nothing once the input is closed.
    func send(_ line: String) {
        guard !inputClosed else { return }
        try? input.fileHandleForWriting.write(contentsOf: Data(line.utf8))
    }

    /// Closes the input: Claude Code exits once the turn is over. If it lingers, it is stopped.
    func finish() {
        guard !inputClosed else { return }
        inputClosed = true
        try? input.fileHandleForWriting.close()
        let process = process
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) {
            if process.isRunning { process.terminate() }
        }
    }

    /// Stops the process. The conversation can still be resumed afterwards.
    func cancel() {
        isCancelled = true
        finish()
        if process.isRunning { process.terminate() }
    }
}

/// A `LineBuffer` shared with the queue that reads the pipe.
private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = LineBuffer()

    func append(_ chunk: Data) -> [String] { lock.withLock { buffer.append(chunk) } }
    func flush() -> String? { lock.withLock { buffer.flush() } }
}

/// The first few kilobytes of an error output, collected off the main actor.
private final class ErrorText: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.withLock { if data.count < 8_192 { data.append(chunk) } }
    }

    var value: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
}
#endif
