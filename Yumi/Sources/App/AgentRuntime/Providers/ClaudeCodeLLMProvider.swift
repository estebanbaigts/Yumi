import Foundation

/// `LLMProvider` over the Claude Code installed on the Mac, used as a model only: it reads the
/// runtime's request and answers text, nothing else. It uses the person's own Claude Code login
/// (their subscription or whatever billing it is set up with), never a key of Yumi's.
///
/// What makes it a model and not an agent (`arguments`):
/// - `--tools ""`: no built-in tool at all (no shell, no file, no web);
/// - `--strict-mcp-config` without a config: no MCP server;
/// - `--setting-sources ""`: none of the person's settings, so no hooks, no allow rules, no plugins;
/// - `--disable-slash-commands`: no skill;
/// - `--system-prompt`: the runtime's rules replace Claude Code's own agent prompt;
/// - `--no-session-persistence`: nothing is kept after the answer;
/// - it runs in an empty folder, so no CLAUDE.md is read.
/// Its answer goes through `PlanValidator` like any other model's.
struct ClaudeCodeLLMProvider: LLMProvider {
    /// Runs the binary with these arguments, the request on standard input, and returns standard output.
    typealias Runner = @Sendable (_ binary: String, _ arguments: [String], _ input: Data, _ folder: String) async throws -> Data

    /// Where `claude` is, or nil when it is not installed.
    var binary: @Sendable () -> String?
    /// An empty folder the process runs in.
    var folder: String
    var model: String?
    var runner: Runner = ClaudeCodeLLMProvider.runProcess
    /// Picture questions go to the session kept open (`ClaudeCodeLive`). Off in the tests.
    var live = true
    /// A planner that does not answer in this time is stopped: a request never waits forever.
    var timeout: Duration = .seconds(120)

    var name: String { "claude-code" }

    static func arguments(system: String, model: String?, picture: Bool = false) -> [String] {
        // A picture cannot go as plain text: the message is sent as one JSON line, and the
        // answer comes back as JSON lines, the last of which is the result.
        let format = picture ? ["--input-format", "stream-json", "--output-format", "stream-json", "--verbose"]
                             : ["--output-format", "json"]
        var arguments = ["-p"] + format + ["--no-session-persistence",
                         "--tools", "", "--strict-mcp-config", "--disable-slash-commands",
                         "--setting-sources", "", "--permission-mode", "default",
                         "--system-prompt", system]
        if let model { arguments += ["--model", model] }
        return arguments
    }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        guard let binary = binary() else { throw LLMProviderError.unavailable }
        let picture = request.hasImage
        let input = picture ? try Self.pictureInput(request) : Data(Self.text(of: request).utf8)
        let output: Data
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            output = try await withThrowingTaskGroup(of: Data?.self) { group in
                group.addTask { [runner, model, folder, live] in
                    let chosen = Self.model(model, for: request)
                    if picture, live {
                        return try await ClaudeCodeLive.shared.ask(input, binary: binary,
                                                                   arguments: Self.liveArguments(system: request.system, model: chosen),
                                                                   folder: folder)
                    }
                    return try await runner(binary, Self.arguments(system: request.system, model: chosen, picture: picture), input, folder)
                }
                group.addTask { [timeout] in
                    try await Task.sleep(for: timeout)
                    return nil
                }
                defer { group.cancelAll() }
                guard let first = try await group.next(), let data = first else { throw TimedOut() }
                return data
            }
        } catch is TimedOut {
            throw LLMProviderError.failed("Claude Code did not answer in time")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Its own words, so that the island says why (a login, a version, a path)
            throw LLMProviderError.failed("Claude Code did not run: \(error)")
        }
        guard let object = (picture && !live) ? Self.resultLine(in: output) : try? JSONSerialization.jsonObject(with: output) as? [String: Any] else {
            throw LLMProviderError.failed("unreadable answer from Claude Code")
        }
        if object["is_error"] as? Bool == true {
            // Not logged in: as if Claude Code were not there, so the next provider (the API key)
            // can plan, and the chat says how to log in.
            let said = ([object["result"] as? String ?? ""] + (object["errors"] as? [String] ?? [])).joined(separator: " ")
            if ChatPhrases.isLoginProblem(said) { throw LLMProviderError.unavailable }
            // No quota… The text can quote the request: only the kind is kept.
            throw LLMProviderError.failed("Claude Code: \(object["subtype"] as? String ?? "error")")
        }
        guard let result = (object["result"] as? String)?.nonEmptyTrimmed else {
            throw LLMProviderError.failed("empty answer from Claude Code")
        }
        return LLMResponse(text: result)
    }

    /// The fastest model when an answer is awaited right now and none was chosen.
    static let fastModel = "haiku"
    /// A question asked aloud about the screen (a picture, awaited now) always takes the light
    /// model: it is asked often, and Haiku reads a screen well. The model chosen in the settings
    /// stays for the rest.
    static func model(_ chosen: String?, for request: LLMRequest) -> String? {
        if request.fast, request.hasImage { return fastModel }
        return chosen ?? (request.fast ? fastModel : nil)
    }

    // MARK: Picture questions, in a session kept open (ClaudeCodeLive)

    /// Opens the session ahead of a picture question that will come in a moment.
    static func prepare(binary: String, system: String, model: String?, folder: String) {
        ClaudeCodeLive.shared.warm(binary: binary, arguments: liveArguments(system: system, model: fastModel),
                                   folder: folder)
    }

    /// The question did not come: the session stays open for the next one.
    static func discardPrepared() {}

    /// A session kept open answers several turns: `--no-session-persistence` keeps nothing on disk.
    /// Its only tool is the web search, allowed without asking: a question about the world gets
    /// an answer from the web. No file, no shell, no other tool.
    static func liveArguments(system: String, model: String?) -> [String] {
        var arguments = arguments(system: system, model: model, picture: true)
        if let tools = arguments.firstIndex(of: "--tools"), tools + 1 < arguments.count {
            arguments[tools + 1] = "WebSearch"
        }
        return arguments + ["--allowedTools", "WebSearch"]
    }

    /// One turn: the messages become one text, as the runtime only ever sends one.
    static func text(of request: LLMRequest) -> String {
        request.messages.map(\.content).joined(separator: "\n\n")
    }

    /// The turn as the one JSON line `--input-format stream-json` reads: the pictures, then the text.
    static func pictureInput(_ request: LLMRequest) throws -> Data {
        var content: [[String: Any]] = request.messages.compactMap(\.image).map {
            ["type": "image", "source": ["type": "base64", "media_type": $0.mediaType, "data": $0.base64]]
        }
        content.append(["type": "text", "text": text(of: request)])
        // Without `parent_tool_use_id` and `session_id`, Claude Code drops the line and answers
        // nothing (checked with Claude Code 2.1.185).
        let line: [String: Any] = ["type": "user", "message": ["role": "user", "content": content],
                                   "parent_tool_use_id": NSNull(), "session_id": ""]
        return try JSONSerialization.data(withJSONObject: line) + Data("\n".utf8)
    }

    /// The `result` object among the JSON lines of `--output-format stream-json`.
    static func resultLine(in output: Data) -> [String: Any]? {
        String(decoding: output, as: UTF8.self).split(whereSeparator: \.isNewline).reversed().lazy
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .first { $0["type"] as? String == "result" }
    }

    /// Runs `claude` and waits for it, stopping it if the task is cancelled. The environment loses
    /// API credentials, so the person's Claude Code login is used, as in the chat.
    static let runProcess: Runner = { binary, arguments, input, folder in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        var environment = ProcessInfo.processInfo.environment
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            environment[key] = nil
        }
        process.environment = environment
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        stdin.fileHandleForWriting.write(input)
        try? stdin.fileHandleForWriting.close()
        return try await withTaskCancellationHandler {
            async let errors = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }.value
            let data = await Task.detached { stdout.fileHandleForReading.readDataToEndOfFile() }.value
            let said = await errors
            process.waitUntilExit()
            try Task.checkCancellation()
            if data.isEmpty, process.terminationStatus != 0 {
                throw ClaudeCodeStopped(status: process.terminationStatus, reason: String(decoding: said.suffix(400), as: UTF8.self))
            }
            return data
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

private struct TimedOut: Error {}

/// Claude Code stopped without an answer: its exit status and its last words.
struct ClaudeCodeStopped: Error, CustomStringConvertible {
    var status: Int32
    var reason: String
    var description: String { "exit \(status) \(reason.trimmingCharacters(in: .whitespacesAndNewlines))" }
}

/// Asks each provider in turn: the next one is tried only when the previous one is not
/// configured (`unavailable`). A provider that was reached and failed is not retried
/// elsewhere: the run fails and says so.
struct FallbackLLMProvider: LLMProvider {
    var providers: [any LLMProvider]

    var name: String { providers.map(\.name).joined(separator: " > ") }

    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        for provider in providers {
            do {
                return try await provider.complete(request)
            } catch LLMProviderError.unavailable {
                continue
            }
        }
        throw LLMProviderError.unavailable
    }
}
