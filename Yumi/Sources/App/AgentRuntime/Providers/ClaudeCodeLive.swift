import Foundation

/// One `claude` kept open for picture questions (`--input-format stream-json`): started once,
/// then each question is one more line on its standard input and its answer the next `result`
/// line. Starting `claude` costs seconds; a question in an open session only costs the model.
/// It starts again after a few questions or a quiet while, so the conversation stays light.
final class ClaudeCodeLive: @unchecked Sendable {
    static let shared = ClaudeCodeLive()
    static let maxTurns = 6
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

    struct Ended: Error {}

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
        if process?.isRunning == true { process?.terminate() }
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
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; self?.finish(with: .failure(Ended())); return }
            self?.received(data)
        }
        process.terminationHandler = { [weak self] _ in self?.finish(with: .failure(Ended())) }
        try process.run()
        self.process = process
        stdin = input.fileHandleForWriting
        key = wanted
        buffer = Data()
        turns = 0
        lastUse = Date()
        return input.fileHandleForWriting
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
