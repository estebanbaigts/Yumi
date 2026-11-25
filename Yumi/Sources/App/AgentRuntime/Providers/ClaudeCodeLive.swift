import Foundation

/// One `claude` kept open for picture questions (`--input-format stream-json`): started once,
/// then each question is one more line on its standard input and its answer the next `result`
/// line. Starting `claude` costs seconds; a question in an open session only costs the model.
/// It starts again after each question or a quiet while, so a question never carries the last.
final class ClaudeCodeLive: @unchecked Sendable {
    static let shared = ClaudeCodeLive()
    /// One question per session: a second one would send the first again, with its picture, and
    /// every question would cost more than the last. The next session opens as soon as the key
    /// is pressed (`warm`), so starting it again costs no waiting.
    static let maxTurns = 1
    static let idleLimit: TimeInterval = 600

    private let lock = NSLock()
    private var process: Process?
    private var stdin: FileHandle?
    private var key: [String] = []
    private var buffer = Data()
    private var turns = 0
    private var lastUse = Date.distantPast
    private var waiting: CheckedContinuation<Data, Error>?
    private var searching = false
    /// Called when the model starts a web search, to say so.
    var onSearch: (@Sendable () -> Void)?
    /// One question at a time.
    private let queue = AsyncSemaphore()

    struct Ended: Error, CustomStringConvertible {
        /// The last words of Claude Code on its error output, when it stopped on its own.
        var reason = ""
        var description: String { reason.isEmpty ? "the session ended" : reason }
    }
    /// What Claude Code last wrote on its error output: said when the session ends by itself.
    private var lastError = ""

    /// Starts the session ahead of a question, if none is open for these arguments.
    func warm(binary: String, arguments: [String], folder: String) {
        lock.lock(); defer { lock.unlock() }
        _ = try? openLocked(binary: binary, arguments: arguments, folder: folder)
    }

    /// Sends one turn (a JSON line) and waits for its `result` line.
    func ask(_ line: Data, binary: String, arguments: [String], folder: String) async throws -> Data {
        await queue.wait()
        defer { queue.signal() }
        let handle: FileHandle = try {
            lock.lock(); defer { lock.unlock() }
            return try openLocked(binary: binary, arguments: arguments, folder: folder)
        }()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                waiting = continuation
                turns += 1
                lastUse = Date()
                lock.unlock()
                do { try handle.write(contentsOf: line) } catch { self.finish(with: .failure(Ended())) }
            }
        } onCancel: {
            self.stop()
        }
    }

    func stop() {
        lock.lock()
        let process = self.process
        self.process = nil
        stdin = nil
        key = []
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
        finish(with: .failure(Ended()))
    }

    // MARK: Inside

    private func openLocked(binary: String, arguments: [String], folder: String) throws -> FileHandle {
        let wanted = [binary, folder] + arguments
        if let process, process.isRunning, let stdin, key == wanted, turns < Self.maxTurns,
           Date().timeIntervalSince(lastUse) < Self.idleLimit {
            return stdin
        }
        let replaced = process
        self.process = nil
        if replaced?.isRunning == true { replaced?.terminate() }
        lastError = ""
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: folder)
        var environment = ProcessInfo.processInfo.environment
        for name in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SSE_PORT"] {
            environment[name] = nil
        }
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        let errors = Pipe()
        process.standardError = errors
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self.lock.lock(); self.lastError = String((self.lastError + text).suffix(400)); self.lock.unlock()
        }
        // A session replaced by a newer one ends later: only the current one may end a question,
        // or the old one's ending would fail the question just sent to the new one
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard let self, let process, self.isCurrent(process) else { handle.readabilityHandler = nil; return }
            if data.isEmpty { handle.readabilityHandler = nil; self.finish(with: .failure(Ended(reason: self.lastErrorText))); return }
            self.received(data)
        }
        process.terminationHandler = { [weak self] ended in
            guard let self, self.isCurrent(ended) else { return }
            self.finish(with: .failure(Ended(reason: self.lastErrorText)))
        }
        try process.run()
        self.process = process
        stdin = input.fileHandleForWriting
        key = wanted
        buffer = Data()
        turns = 0
        lastUse = Date()
        return input.fileHandleForWriting
    }

    private func isCurrent(_ candidate: Process) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return process === candidate
    }

    private var lastErrorText: String {
        lock.lock(); defer { lock.unlock() }
        return lastError.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func received(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var results: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if object["type"] as? String == "result" {
                results.append(Data(line))
            } else if Self.usesWebSearch(object) {
                searching = true
            }
        }
        let onSearch = searching ? self.onSearch : nil
        searching = false
        lock.unlock()
        onSearch?()
        for result in results { finish(with: .success(result)) }
    }

    /// An assistant message that calls the web search tool.
    static func usesWebSearch(_ object: [String: Any]) -> Bool {
        guard object["type"] as? String == "assistant",
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "tool_use" && ($0["name"] as? String) == "WebSearch" }
    }

    private func finish(with result: Result<Data, Error>) {
        lock.lock()
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

/// A tiny async semaphore with one place.
final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var busy = false
    private var queue: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if busy { queue.append(continuation); lock.unlock(); return }
            busy = true
            lock.unlock()
            continuation.resume()
        }
    }

    func signal() {
        lock.lock()
        if queue.isEmpty { busy = false; lock.unlock(); return }
        let next = queue.removeFirst()
        lock.unlock()
        next.resume()
    }
}
