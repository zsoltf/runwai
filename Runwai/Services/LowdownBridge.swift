import Foundation
import Darwin

struct LowdownMessage: Decodable, Identifiable, Sendable {
    let id: String
    let kind: String
    let timestamp: String
    let originalText: String?
    let textBytes: Int
    let textComplete: Bool
    let sourceRef: SourceRef

    struct SourceRef: Decodable, Sendable {
        let sessionPath: String
        let byteOffset: UInt64
    }
}

struct LowdownItem: Decodable, Sendable {
    let id: String?
    let root: String?
    let name: String?
    let path: String?
    let cwd: String?
    let lastActivity: String?
    let messageId: String?
    let text: String?
}

struct LowdownEvent: Decodable, Sendable {
    let v: Int
    let event: String
    let seq: UInt64
    let requestId: String?
    let generation: UInt64?
    let sessionId: String?
    let sessionRevision: String?
    let payload: Payload

    struct Payload: Decodable, Sendable {
        let helperVersion: String?
        let sourceRevision: String?
        let source: String?
        let capabilities: [String]?
        let items: [LowdownItem]?
        let projectId: String?
        let partial: Bool?
        let messages: [LowdownMessage]?
        let latestAnswer: LowdownMessage?
        let answerStatus: String?
        let beforeCursor: String?
        let hasMore: Bool?
        let readCoverage: ReadCoverage?
        let loading: Bool?
        let paused: Bool?
        let summaryStatus: String?
        let pending: Int?
        let code: String?
        let message: String?
        let recoverable: Bool?
        let messageId: String?
        let byteOffset: Int?
        let totalBytes: Int?
        let text: String?
        let done: Bool?
    }

    struct ReadCoverage: Decodable, Sendable {
        let oversizedRecordsSkipped: Bool?
        let scanLimited: Bool?
    }
}

struct LowdownCommand: Encodable, Sendable {
    let v = 1
    let id = UUID().uuidString
    var command: String
    var generation: UInt64?
    var projectRoots: [String]?
    var projectRoot: String?
    var sessionId: String?
    var beforeCursor: String?
    var messageId: String?
    var messageIds: [String]?
    var limit: Int?
}

enum LowdownBridgeError: LocalizedError {
    case unavailable, protocolMismatch, invalidOutput, overflow, exited(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable: "Lowdown helper is not installed in this build."
        case .protocolMismatch: "Lowdown needs a compatible update."
        case .invalidOutput: "Lowdown returned an unreadable update."
        case .overflow: "Lowdown sent updates faster than they could be displayed. Reconnect to reload."
        case .exited(let status): "Lowdown disconnected (\(status))."
        }
    }
}

// Lifecycle, decoding, and writes have independent serial queues. Bounded
// delivery applies pipe backpressure without blocking UI or cancellation.
final class LowdownBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.runwai.lowdown.events", qos: .userInitiated)
    private let writer = DispatchQueue(label: "app.runwai.lowdown.commands", qos: .userInitiated)
    private let decoding = DispatchQueue(label: "app.runwai.lowdown.decode", qos: .userInitiated)
    private let cancellationLock = NSLock()
    private var cancelled = false
    private let executable: URL
    private let environment: [String: String]
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var diagnostic: FileHandle?
    private var buffer = Data()
    private var sequence: UInt64 = 0
    private var continuation: AsyncThrowingStream<LowdownEvent, Error>.Continuation?
    private var stopping = false
    private var outputEnded = false
    private var exitStatus: Int32?

    init(executable: URL, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.executable = executable
        self.environment = environment
    }

    static var bundledExecutable: URL? {
        guard let root = Bundle.main.resourceURL else { return nil }
        let path = root.appendingPathComponent("Lowdown/lowdown")
        return FileManager.default.isExecutableFile(atPath: path.path) ? path : nil
    }

    func events() -> AsyncThrowingStream<LowdownEvent, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(16)) { continuation in
            continuation.onTermination = { [weak self] _ in self?.stop() }
            queue.async {
                self.continuation = continuation
                self.launch()
            }
        }
    }

    func send(_ command: LowdownCommand) {
        queue.async {
            guard let input = self.input, !self.stopping else { return }
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            guard var data = try? encoder.encode(command), data.count < 65_536 else { return }
            data.append(10)
            let bytes = data
            self.writer.async { [weak self] in
                do { try input.write(contentsOf: bytes) }
                catch { self?.queue.async { [weak self] in self?.fail(error) } }
            }
        }
    }

    func stop() {
        queue.async { self.shutdown() }
    }

    private func launch() {
        guard process == nil else { return }
        guard let continuation else { return }
        let child = Process()
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        child.executableURL = executable
        child.arguments = ["bridge", "--protocol-version", "1"]
        child.environment = environment
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = stderr
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        diagnostic = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            // Bound ingress by applying pipe backpressure on this reader only.
            // Commands and cancellation remain on separate queues.
            self?.decoding.sync { self?.consume(data, continuation: continuation) }
            if data.isEmpty {
                self?.queue.async { [weak self] in
                    self?.outputEnded = true
                    self?.finishIfExited()
                }
            }
        }
        diagnostic?.readabilityHandler = { handle in
            // Drain, but do not persist transcript fragments or local paths in app logs.
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        child.terminationHandler = { [weak self] child in
            self?.queue.async { [weak self] in
                guard let self else { return }
                self.exitStatus = child.terminationStatus
                self.finishIfExited()
            }
        }
        process = child
        do { try child.run() }
        catch { fail(error); cleanup() }
    }

    private var isCancelled: Bool { cancellationLock.withLock { cancelled } }

    private func consume(_ data: Data, continuation: AsyncThrowingStream<LowdownEvent, Error>.Continuation) {
        guard !isCancelled else { return }
        buffer.append(data)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        while let newline = buffer.firstIndex(of: 10) {
            guard !isCancelled else { return }
            let line = buffer.prefix(upTo: newline)
            guard line.count <= 8_388_608 else { reportFailure(LowdownBridgeError.overflow); return }
            do {
                let event = try decoder.decode(LowdownEvent.self, from: line)
                guard event.v == 1, event.seq > sequence else { throw LowdownBridgeError.protocolMismatch }
                sequence = event.seq
                let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
                delivery: while !isCancelled {
                    switch continuation.yield(event) {
                    case .enqueued: break delivery
                    case .terminated: return
                    case .dropped:
                        guard DispatchTime.now().uptimeNanoseconds < deadline else {
                            reportFailure(LowdownBridgeError.overflow); return
                        }
                        Thread.sleep(forTimeInterval: 0.001)
                    @unknown default: return
                    }
                }
            } catch { reportFailure(error); return }
            buffer.removeSubrange(...newline)
        }
        if buffer.count > 8_388_608 { reportFailure(LowdownBridgeError.overflow) }
    }

    private func reportFailure(_ error: Error) { queue.async { self.fail(error) } }

    private func finishIfExited() {
        guard let exitStatus, stopping || outputEnded else { return }
        if stopping { continuation?.finish() }
        else { continuation?.finish(throwing: LowdownBridgeError.exited(exitStatus)) }
        cleanup()
    }

    private func fail(_ error: Error) {
        continuation?.finish(throwing: error)
        shutdown()
    }

    private func shutdown() {
        guard !stopping else { return }
        stopping = true
        cancellationLock.withLock { cancelled = true }
        if let input { writer.async { try? input.close() } }
        guard let child = process else { cleanup(); return }
        queue.asyncAfter(deadline: .now() + 5) {
            guard child.isRunning else { return }
            child.terminate()
            self.queue.asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }

    private func cleanup() {
        output?.readabilityHandler = nil
        diagnostic?.readabilityHandler = nil
        try? output?.close()
        try? diagnostic?.close()
        try? input?.close()
        process = nil
        continuation = nil
    }
}
