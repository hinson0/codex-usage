import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct AppServerClientTests {
    @Test
    func binaryLocatorUsesDocumentedPrecedence() {
        let executablePaths: Set<String> = [
            "/override/codex",
            "/home/.local/bin/codex",
            "/path-bin/codex",
        ]
        let locator = CodexBinaryLocator(
            environment: ["CODEX_BIN": "/override/codex", "PATH": "/path-bin:/other"],
            homeDirectory: URL(fileURLWithPath: "/home"),
            isExecutable: { executablePaths.contains($0) }
        )

        #expect(locator.locate()?.path == "/override/codex")

        let fallback = CodexBinaryLocator(
            environment: ["CODEX_BIN": "/missing", "PATH": "/path-bin:/other"],
            homeDirectory: URL(fileURLWithPath: "/home"),
            isExecutable: { executablePaths.contains($0) }
        )
        #expect(fallback.locate()?.path == "/home/.local/bin/codex")
    }

    @Test
    func readPerformsHandshakeSkipsNotificationsAndMismatchedResponses() async throws {
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: ["userAgent": "test"])),
            .line(notification(method: "account/rateLimits/updated")),
            .line(response(id: 999, result: ["ignored": true])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 2)),
        ])
        let client = makeClient(transports: [transport])

        let snapshot = try await client.readRateLimits()
        let messages = await transport.sentMessages()

        #expect(snapshot.primaryBucket?.limitId == "codex")
        #expect(snapshot.availableResetCount == 2)
        #expect(messages.compactMap(\.method) == [
            "initialize",
            "initialized",
            "account/rateLimits/read",
        ])
        #expect(messages[0].id == 0)
        #expect(messages[2].id == 1)
    }

    @Test
    func jsonRPCErrorBecomesProtocolError() async {
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(errorResponse(id: 1, code: -32000, message: "invalid request")),
        ])
        let client = makeClient(transports: [transport])

        do {
            _ = try await client.readRateLimits()
            Issue.record("Expected protocol error")
        } catch let error as UsageServiceError {
            #expect(error == .protocolError("invalid request (-32000)"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func authenticationRPCErrorGetsTypedForLocalization() async {
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(errorResponse(id: 1, code: -32000, message: "not logged in")),
        ])
        let client = makeClient(transports: [transport])

        do {
            _ = try await client.readRateLimits()
            Issue.record("Expected authentication error")
        } catch let error as UsageServiceError {
            #expect(error == .authenticationRequired)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func timeoutInvalidatesTransportAndNextRequestStartsFreshSession() async throws {
        let timedOut = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .wait,
        ])
        let recovered = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 10, resetCount: 0)),
        ])
        let sequence = TransportSequence([timedOut, recovered])
        let client = CodexAppServerClient(
            locator: FixedBinaryLocator(),
            transportFactory: { sequence.next() },
            requestTimeout: .milliseconds(20),
            now: { Date(timeIntervalSince1970: 20) }
        )

        do {
            _ = try await client.readRateLimits()
            Issue.record("Expected timeout")
        } catch let error as UsageServiceError {
            #expect(error == .timeout)
        }

        let snapshot = try await client.readRateLimits()
        #expect(snapshot.primaryBucket?.primary?.usedPercent == 10)
        #expect(await timedOut.stopCount == 1)
        #expect(await recovered.startCount == 1)
    }

    @Test
    func processTerminationFailsRequestAndAllowsRestart() async throws {
        let terminated = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .failure(.transport("process exited")),
        ])
        let recovered = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 40, resetCount: 0)),
        ])
        let client = makeClient(transports: [terminated, recovered])

        do {
            _ = try await client.readRateLimits()
            Issue.record("Expected termination error")
        } catch let error as UsageServiceError {
            #expect(error == .transport("process exited"))
        }

        let snapshot = try await client.readRateLimits()
        #expect(snapshot.primaryBucket?.primary?.usedPercent == 40)
    }

}

@Suite
struct AppServerIntegrationTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["CODEX_USAGE_RUN_INTEGRATION"] == "1",
        "Set CODEX_USAGE_RUN_INTEGRATION=1 to read live usage"
    ))
    func readsLiveUsageWithoutConsumingReset() async throws {
        let client = CodexAppServerClient()
        let snapshot = try await client.readRateLimits()
        #expect(snapshot.primaryBucket != nil)
        #expect(snapshot.availableResetCount >= 0)
    }
}

private struct FixedBinaryLocator: CodexBinaryLocating {
    func locate() -> URL? { URL(fileURLWithPath: "/fake/codex") }
}

private actor ScriptedTransport: AppServerTransport {
    struct SentMessage: Sendable {
        let method: String?
        let id: Int?
        let params: [String: String]
    }

    enum Event: Sendable {
        case line(Data)
        case failure(UsageServiceError)
        case wait
    }

    private var events: [Event]
    private var sent: [Data] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(events: [Event]) {
        self.events = events
    }

    func start(executableURL: URL) async throws {
        startCount += 1
    }

    func send(_ line: Data) async throws {
        sent.append(line)
    }

    func nextLine() async throws -> Data? {
        guard !events.isEmpty else { return nil }
        switch events.removeFirst() {
        case .line(let data): return data
        case .failure(let error): throw error
        case .wait:
            try await Task.sleep(for: .seconds(60))
            return nil
        }
    }

    func stop() async {
        stopCount += 1
    }

    func sentMessages() -> [SentMessage] {
        sent.compactMap { data in
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return SentMessage(
                method: object["method"] as? String,
                id: object["id"] as? Int,
                params: object["params"] as? [String: String] ?? [:]
            )
        }
    }
}

private final class TransportSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [any AppServerTransport]

    init(_ transports: [any AppServerTransport]) {
        self.transports = transports
    }

    func next() -> any AppServerTransport {
        lock.lock()
        defer { lock.unlock() }
        precondition(!transports.isEmpty, "No scripted transport remains")
        return transports.removeFirst()
    }
}

private func makeClient(transports: [any AppServerTransport]) -> CodexAppServerClient {
    let sequence = TransportSequence(transports)
    return CodexAppServerClient(
        locator: FixedBinaryLocator(),
        transportFactory: { sequence.next() },
        requestTimeout: .seconds(1),
        now: { Date(timeIntervalSince1970: 10) }
    )
}

private func response(id: Int, result: [String: Any]) -> Data {
    json(["id": id, "result": result])
}

private func errorResponse(id: Int, code: Int, message: String) -> Data {
    json(["id": id, "error": ["code": code, "message": message]])
}

private func notification(method: String) -> Data {
    json(["method": method, "params": [:]])
}

private func rateLimitsResponse(id: Int, usedPercent: Double, resetCount: Int) -> Data {
    response(id: id, result: [
        "ordinaryUsageAllowed": true,
        "rateLimits": [
            "limitId": "codex",
            "primary": [
                "usedPercent": usedPercent,
                "windowDurationMins": 10_080,
                "resetsAt": 1_800_000_000,
            ],
        ],
        "rateLimitResetCredits": [
            "availableCount": resetCount,
            "credits": [],
        ],
    ])
}

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
