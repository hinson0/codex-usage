import Foundation

public protocol AppServerTransport: Sendable {
    func start(executableURL: URL) async throws
    func send(_ line: Data) async throws
    func nextLine() async throws -> Data?
    func stop() async
}

private actor LineQueue {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Data?, Error>
    }

    private var lines: [Data] = []
    private var waiters: [Waiter] = []
    private var completion: Result<Void, Error>?

    func push(_ line: Data) {
        guard completion == nil else { return }
        if waiters.isEmpty {
            lines.append(line)
        } else {
            waiters.removeFirst().continuation.resume(returning: line)
        }
    }

    func finish(error: Error?) {
        guard completion == nil else { return }
        completion = error.map(Result.failure) ?? .success(())
        let current = waiters
        waiters.removeAll()
        for waiter in current {
            if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume(returning: nil)
            }
        }
    }

    func next() async throws -> Data? {
        if !lines.isEmpty {
            return lines.removeFirst()
        }
        if let completion {
            try completion.get()
            return nil
        }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}

public final class ProcessAppServerTransport: AppServerTransport, @unchecked Sendable {
    private let stateLock = NSLock()
    private let queue = LineQueue()
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var bufferedOutput = Data()

    public init() {}

    public func start(executableURL: URL) async throws {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.standardError

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                Task { await self?.queue.finish(error: nil) }
            } else {
                self?.ingest(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let error: Error? = process.terminationStatus == 0
                ? nil
                : UsageServiceError.transport("Codex app-server exited with status \(process.terminationStatus)")
            Task { await self?.queue.finish(error: error) }
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw UsageServiceError.transport(error.localizedDescription)
        }

        stateLock.withLock {
            self.process = process
            self.input = input
            self.output = output
        }
    }

    public func send(_ line: Data) async throws {
        let handle = stateLock.withLock { input?.fileHandleForWriting }
        guard let handle else {
            throw UsageServiceError.transport("Codex app-server is not running")
        }
        do {
            try handle.write(contentsOf: line + Data([0x0A]))
        } catch {
            throw UsageServiceError.transport(error.localizedDescription)
        }
    }

    public func nextLine() async throws -> Data? {
        try await queue.next()
    }

    public func stop() async {
        let (currentProcess, currentInput, currentOutput) = stateLock.withLock {
            let values = (process, input, output)
            process = nil
            input = nil
            output = nil
            return values
        }

        currentOutput?.fileHandleForReading.readabilityHandler = nil
        try? currentInput?.fileHandleForWriting.close()
        try? currentOutput?.fileHandleForReading.close()
        if currentProcess?.isRunning == true {
            currentProcess?.terminate()
        }
        await queue.finish(error: nil)
    }

    private func ingest(_ data: Data) {
        stateLock.lock()
        bufferedOutput.append(data)
        var completeLines: [Data] = []
        while let newline = bufferedOutput.firstIndex(of: 0x0A) {
            var line = Data(bufferedOutput[..<newline])
            bufferedOutput.removeSubrange(...newline)
            if line.last == 0x0D { line.removeLast() }
            if !line.isEmpty { completeLines.append(line) }
        }
        stateLock.unlock()

        for line in completeLines {
            Task { await queue.push(line) }
        }
    }
}
