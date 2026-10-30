import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct AppServerClientTests {
    @Test
    func binaryLocatorFindsBundledCLIWithoutStandaloneInstallation() {
        let bundledPath = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex"
        let locator = CodexBinaryLocator(
            environment: ["PATH": "/usr/bin:/bin"],
            homeDirectory: URL(fileURLWithPath: "/home"),
            isExecutable: { $0 == bundledPath }
        )

        #expect(locator.locate()?.path == bundledPath)
    }

    @Test(arguments: [
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
        "/Applications/ChatGPT.app/Contents/Resources/codex",
    ])
    func binaryLocatorPrefersChatGPTOverStandaloneCLI(bundledPath: String) {
        let executablePaths: Set<String> = [
            bundledPath, "/home/.local/bin/codex", "/opt/homebrew/bin/codex", "/path-bin/codex",
        ]
        let locator = CodexBinaryLocator(
            environment: ["PATH": "/path-bin"],
            homeDirectory: URL(fileURLWithPath: "/home"),
            isExecutable: { executablePaths.contains($0) }
        )
        #expect(locator.locate()?.path == bundledPath)
    }

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
    func resetCreditDetailsAreCachedWhileUsageAndCountStayLive() async throws {
        let credits = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: credits)),
            .line(rateLimitsResponse(id: 2, usedPercent: 40, resetCount: 1, credits: nil)),
        ])
        let client = makeClient(transports: [transport])

        let initial = try await client.readRateLimits()
        let refreshed = try await client.readRateLimits()
        let reads = await transport.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(initial.resetCredits == credits)
        #expect(refreshed.resetCredits == credits)
        #expect(refreshed.primaryBucket?.primary?.usedPercent == 40)
        #expect(refreshed.availableResetCount == 1)
        #expect(reads.map(\.excludesResetCreditDetails) == [false, true])
    }

    @Test
    func resetCreditDetailsSurviveRestartWithoutExtendingTheirLifetime() async throws {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let clock = TestClock(Date(timeIntervalSince1970: 10))
        let original = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let updated = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000)]
        let initial = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: original)),
        ])
        _ = try await makeClient(
            transports: [initial], now: { clock.now }, cacheURL: cacheURL
        ).readRateLimits()
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        clock.advance(by: 86_399)
        let restarted = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 40, resetCount: 1, credits: nil)),
        ])
        let cached = try await makeClient(
            transports: [restarted], now: { clock.now }, cacheURL: cacheURL
        ).readRateLimits()
        #expect(cached.resetCredits == original)
        #expect(cached.primaryBucket?.primary?.usedPercent == 40)
        #expect(await restarted.sentMessages().last?.excludesResetCreditDetails == true)

        clock.advance(by: 1)
        let expired = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 41, resetCount: 1, credits: updated)),
        ])
        let refreshed = try await makeClient(
            transports: [expired], now: { clock.now }, cacheURL: cacheURL
        ).readRateLimits()
        #expect(refreshed.resetCredits == updated)
        #expect(await expired.sentMessages().last?.excludesResetCreditDetails == false)
    }

    @Test(arguments: [0, 1, 3])
    func changedResetCreditCountRefreshesTheDiskCacheAfterRestart(count: Int) async throws {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let original = Array(repeating: ResetCredit(
            status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000
        ), count: 2)
        let updated = Array(repeating: ResetCredit(
            status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000
        ), count: count)
        let initial = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 80, resetCount: 2, credits: original)),
        ])
        _ = try await makeClient(transports: [initial], cacheURL: cacheURL).readRateLimits()

        let restarted = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 0, resetCount: count, credits: nil)),
        ] + (count > 0 ? [
            .line(rateLimitsResponse(id: 2, usedPercent: 1, resetCount: count, credits: updated)),
        ] : []))
        let refreshed = try await makeClient(transports: [restarted], cacheURL: cacheURL).readRateLimits()
        let reads = await restarted.sentMessages().filter { $0.method == "account/rateLimits/read" }
        #expect(refreshed.availableResetCount == count)
        #expect(refreshed.resetCredits == updated)
        #expect(reads.map(\.excludesResetCreditDetails) == (count > 0 ? [true, false] : [true]))

        let nextRestart = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 2, resetCount: count, credits: nil)),
        ])
        let cached = try await makeClient(transports: [nextRestart], cacheURL: cacheURL).readRateLimits()
        #expect(cached.availableResetCount == count)
        #expect(cached.resetCredits == updated)
        #expect(await nextRestart.sentMessages().last?.excludesResetCreditDetails == true)
    }

    @Test
    func temporaryConnectionFailurePreservesTheDiskCacheForRestart() async throws {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let credits = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let failed = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: credits)),
            .failure(.transport("connection lost")),
        ])
        let client = makeClient(transports: [failed], cacheURL: cacheURL)
        _ = try await client.readRateLimits()
        await #expect(throws: UsageServiceError.transport("connection lost")) {
            try await client.readRateLimits()
        }
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))

        let restarted = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 28, resetCount: 1, credits: nil)),
        ])
        let refreshed = try await makeClient(transports: [restarted], cacheURL: cacheURL).readRateLimits()
        #expect(refreshed.resetCredits == credits)
        #expect(await restarted.sentMessages().last?.excludesResetCreditDetails == true)
    }

    @Test(arguments: [1, 3])
    func changedResetCreditCountImmediatelyFetchesNewDetails(count: Int) async throws {
        let original = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let updated = Array(repeating: ResetCredit(
            status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000
        ), count: count)
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 80, resetCount: 2, credits: original)),
            .line(rateLimitsResponse(id: 2, usedPercent: 0, resetCount: count, credits: nil)),
            .line(rateLimitsResponse(id: 3, usedPercent: 1, resetCount: count, credits: updated)),
        ])
        let client = makeClient(transports: [transport])

        _ = try await client.readRateLimits()
        let refreshed = try await client.readRateLimits()
        let reads = await transport.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(refreshed.availableResetCount == count)
        #expect(refreshed.resetCredits == updated)
        #expect(reads.map(\.excludesResetCreditDetails) == [false, true, false])
    }

    @Test(arguments: [86_400, 20])
    func resetCreditCacheExpiresAfterOneDayOrWhenACreditExpires(lifetime: Int) async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 10))
        let original = [ResetCredit(
            status: "available", resetType: "codexRateLimits",
            expiresAt: lifetime == 20 ? 30 : 2_000_000
        )]
        let updated = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000)]
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: original)),
            .line(rateLimitsResponse(id: 2, usedPercent: 28, resetCount: 1, credits: nil)),
            .line(rateLimitsResponse(id: 3, usedPercent: 29, resetCount: 1, credits: updated)),
        ])
        let client = makeClient(transports: [transport], now: { clock.now })

        _ = try await client.readRateLimits()
        clock.advance(by: TimeInterval(lifetime - 1))
        let cached = try await client.readRateLimits()
        clock.advance(by: 1)
        let refreshed = try await client.readRateLimits()
        let reads = await transport.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(cached.resetCredits == original)
        #expect(refreshed.resetCredits == updated)
        #expect(reads.map(\.excludesResetCreditDetails) == [false, true, false])
    }

    @Test
    func usingTheLastResetCreditClearsCachedDetailsWithoutAnotherLookup() async throws {
        let credits = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 80, resetCount: 1, credits: credits)),
            .line(rateLimitsResponse(id: 2, usedPercent: 0, resetCount: 0, credits: nil)),
            .line(rateLimitsResponse(id: 3, usedPercent: 1, resetCount: 0, credits: nil)),
        ])
        let client = makeClient(transports: [transport])

        _ = try await client.readRateLimits()
        let used = try await client.readRateLimits()
        let refreshed = try await client.readRateLimits()
        let reads = await transport.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(used.availableResetCount == 0)
        #expect(used.resetCredits.isEmpty)
        #expect(refreshed.availableResetCount == 0)
        #expect(refreshed.resetCredits.isEmpty)
        #expect(reads.map(\.excludesResetCreditDetails) == [false, true, true])
    }

    @Test
    func unavailableResetCreditDetailsAreRetriedOnTheNextRead() async throws {
        let credits = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: nil)),
            .line(rateLimitsResponse(id: 2, usedPercent: 28, resetCount: 1, credits: credits)),
        ])
        let client = makeClient(transports: [transport])

        let unknown = try await client.readRateLimits()
        let refreshed = try await client.readRateLimits()
        let reads = await transport.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(unknown.availableResetCount == 1)
        #expect(unknown.resetCredits.isEmpty)
        #expect(refreshed.resetCredits == credits)
        #expect(reads.map(\.excludesResetCreditDetails) == [false, false])
    }

    @Test
    func accountChangeDiscardsCachedDetailsEvenWhenTheCountMatches() async throws {
        let original = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let updated = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000)]
        let transport = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: original)),
            .line(notification(method: "account/updated")),
            .line(rateLimitsResponse(id: 2, usedPercent: 28, resetCount: 1, credits: nil)),
            .line(rateLimitsResponse(id: 3, usedPercent: 28, resetCount: 1, credits: updated)),
        ])
        let client = makeClient(transports: [transport])

        _ = try await client.readRateLimits()
        let refreshed = try await client.readRateLimits()

        #expect(refreshed.resetCredits == updated)
    }

    @Test
    func failedConnectionDiscardsCachedDetailsBeforeRestarting() async throws {
        let cacheURL = temporaryCacheURL()
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let original = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 2_000_000)]
        let updated = [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: 3_000_000)]
        let failed = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 27, resetCount: 1, credits: original)),
            .failure(.authenticationRequired),
        ])
        let recovered = ScriptedTransport(events: [
            .line(response(id: 0, result: [:])),
            .line(rateLimitsResponse(id: 1, usedPercent: 28, resetCount: 1, credits: updated)),
        ])
        let client = makeClient(transports: [failed, recovered], cacheURL: cacheURL)

        _ = try await client.readRateLimits()
        await #expect(throws: UsageServiceError.authenticationRequired) {
            try await client.readRateLimits()
        }
        #expect(!FileManager.default.fileExists(atPath: cacheURL.path))
        let refreshed = try await client.readRateLimits()
        let reads = await recovered.sentMessages().filter { $0.method == "account/rateLimits/read" }

        #expect(refreshed.resetCredits == updated)
        #expect(reads.map(\.excludesResetCreditDetails) == [false])
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
            now: { Date(timeIntervalSince1970: 20) },
            resetCreditCacheURL: temporaryCacheURL()
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
        let refreshed = try await client.readRateLimits()
        #expect(refreshed.primaryBucket != nil)
        #expect(refreshed.availableResetCount >= 0)
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
        let excludesResetCreditDetails: Bool
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
                params: object["params"] as? [String: String] ?? [:],
                excludesResetCreditDetails: (object["params"] as? [String: Any])?["excludeResetCreditDetails"] as? Bool ?? false
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

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        date.addTimeInterval(interval)
    }
}

private func makeClient(
    transports: [any AppServerTransport],
    now: @escaping @Sendable () -> Date = { Date(timeIntervalSince1970: 10) },
    cacheURL: URL = temporaryCacheURL()
) -> CodexAppServerClient {
    let sequence = TransportSequence(transports)
    return CodexAppServerClient(
        locator: FixedBinaryLocator(),
        transportFactory: { sequence.next() },
        requestTimeout: .seconds(1),
        now: now,
        resetCreditCacheURL: cacheURL
    )
}

private func temporaryCacheURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-usage-reset-cache-tests", isDirectory: true)
        .appendingPathComponent("\(UUID().uuidString).json")
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

private func rateLimitsResponse(
    id: Int,
    usedPercent: Double,
    resetCount: Int,
    credits: [ResetCredit]? = []
) -> Data {
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
            "credits": credits.map { try! JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull(),
        ],
    ])
}

private func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}
