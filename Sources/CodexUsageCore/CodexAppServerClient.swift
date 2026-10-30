import Foundation

public actor CodexAppServerClient: UsageService {
    private struct ResetCreditCache: Codable {
        let summary: ResetCreditsSummary
        let fetchedAt: Date
    }

    private let locator: any CodexBinaryLocating
    private let transportFactory: @Sendable () -> any AppServerTransport
    private let requestTimeout: Duration
    private let now: @Sendable () -> Date
    private let resetCreditCacheURL: URL
    private var transport: (any AppServerTransport)?
    private var isReady = false
    private var nextRequestId = 1
    private var resetCreditCache: ResetCreditCache?

    public init(
        locator: any CodexBinaryLocating = CodexBinaryLocator(),
        transportFactory: @escaping @Sendable () -> any AppServerTransport = {
            ProcessAppServerTransport()
        },
        requestTimeout: Duration = .seconds(10),
        now: @escaping @Sendable () -> Date = Date.init,
        resetCreditCacheURL: URL? = nil
    ) {
        self.locator = locator
        self.transportFactory = transportFactory
        self.requestTimeout = requestTimeout
        self.now = now
        self.resetCreditCacheURL = resetCreditCacheURL ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.codexusage", isDirectory: true)
            .appendingPathComponent("reset-credits.json")
        if let data = try? Data(contentsOf: self.resetCreditCacheURL) {
            resetCreditCache = try? JSONDecoder().decode(ResetCreditCache.self, from: data)
        }
    }

    public func readRateLimits() async throws -> UsageSnapshot {
        let skipsDetails = cachedResetCredits(at: now()) != nil
        var result: RateLimitsResponse = try await request(
            method: "account/rateLimits/read",
            params: skipsDetails ? ["excludeResetCreditDetails": true] : nil
        )
        let summary: ResetCreditsSummary?
        if skipsDetails, let cached = cachedResetCredits(at: now()),
           let current = result.rateLimitResetCredits,
           current.credits == nil, current.availableCount == cached.availableCount {
            summary = cached
        } else {
            if skipsDetails, let current = result.rateLimitResetCredits,
               current.availableCount > 0, current.credits == nil {
                // A changed count may mean a credit was used or granted. Refresh its expiry too.
                clearResetCreditCache()
                result = try await request(method: "account/rateLimits/read", params: nil)
            }
            summary = result.rateLimitResetCredits
            cacheResetCredits(summary, at: now())
        }
        return UsageSnapshot(response: RateLimitsResponse(
            ordinaryUsageAllowed: result.ordinaryUsageAllowed,
            rateLimits: result.rateLimits,
            rateLimitsByLimitId: result.rateLimitsByLimitId,
            rateLimitResetCredits: summary
        ), refreshedAt: now())
    }

    private func cachedResetCredits(at date: Date) -> ResetCreditsSummary? {
        guard let cached = resetCreditCache else { return nil }
        let age = date.timeIntervalSince(cached.fetchedAt)
        let hasExpiredCredit = cached.summary.credits?.contains { credit in
            credit.status == "available" && credit.resetType == "codexRateLimits"
                && credit.expiresAt.map { TimeInterval($0) <= date.timeIntervalSince1970 } == true
        } ?? false
        guard age >= 0, age < 86_400, !hasExpiredCredit,
              cached.summary.availableCount >= 0,
              cached.summary.availableCount == 0 || cached.summary.credits != nil else {
            clearResetCreditCache()
            return nil
        }
        return cached.summary
    }

    private func cacheResetCredits(_ summary: ResetCreditsSummary?, at date: Date) {
        guard let summary, summary.availableCount >= 0,
              summary.availableCount == 0 || summary.credits != nil else {
            clearResetCreditCache()
            return
        }
        // Keep only the read-only model, which excludes account and credit identifiers.
        let entry = ResetCreditCache(summary: summary, fetchedAt: date)
        resetCreditCache = entry
        if let data = try? JSONEncoder().encode(entry) {
            try? FileManager.default.createDirectory(
                at: resetCreditCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: resetCreditCacheURL, options: .atomic)
        }
    }

    private func clearResetCreditCache() {
        resetCreditCache = nil
        try? FileManager.default.removeItem(at: resetCreditCacheURL)
    }

    private func request<Response: Decodable>(
        method: String,
        params: [String: Any]?
    ) async throws -> Response {
        do {
            try await ensureReady()
            guard let transport else {
                throw UsageServiceError.transport("Codex app-server did not start")
            }
            let id = nextRequestId
            nextRequestId += 1
            var object: [String: Any] = ["method": method, "id": id]
            if let params { object["params"] = params }
            try await transport.send(try encode(object))
            let result = try await awaitResult(id: id, transport: transport)
            return try JSONDecoder().decode(Response.self, from: result)
        } catch {
            if error as? UsageServiceError == .authenticationRequired {
                clearResetCreditCache()
            }
            await invalidate()
            if let serviceError = error as? UsageServiceError { throw serviceError }
            if error is CancellationError { throw UsageServiceError.timeout }
            throw UsageServiceError.transport(error.localizedDescription)
        }
    }

    private func ensureReady() async throws {
        if isReady { return }
        guard let executableURL = locator.locate() else {
            throw UsageServiceError.binaryMissing
        }

        let transport = transportFactory()
        try await transport.start(executableURL: executableURL)
        self.transport = transport
        nextRequestId = 1

        let initialize: [String: Any] = [
            "method": "initialize",
            "id": 0,
            "params": [
                "clientInfo": [
                    "name": "codex_usage_menubar",
                    "title": "Codex Usage",
                    "version": "0.1.0",
                ],
            ],
        ]
        try await transport.send(try encode(initialize))
        _ = try await awaitResult(id: 0, transport: transport)
        try await transport.send(try encode(["method": "initialized", "params": [:]]))
        isReady = true
    }

    private func awaitResult(id: Int, transport: any AppServerTransport) async throws -> Data {
        while true {
            let line = try await nextLineWithTimeout(transport: transport)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                continue
            }
            guard let responseId = object["id"] as? Int else {
                if object["method"] as? String == "account/updated" {
                    clearResetCreditCache()
                }
                continue
            }
            guard responseId == id else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown JSON-RPC error"
                let code = error["code"] as? Int
                let normalized = message.lowercased()
                if normalized.contains("not logged")
                    || normalized.contains("unauthorized")
                    || normalized.contains("authentication")
                {
                    throw UsageServiceError.authenticationRequired
                }
                throw UsageServiceError.protocolError(code.map { "\(message) (\($0))" } ?? message)
            }
            guard let result = object["result"] else {
                throw UsageServiceError.protocolError("JSON-RPC response has no result")
            }
            return try encode(result)
        }
    }

    private func nextLineWithTimeout(transport: any AppServerTransport) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                guard let line = try await transport.nextLine() else {
                    throw UsageServiceError.transport("Codex app-server exited")
                }
                return line
            }
            group.addTask {
                try await Task.sleep(for: self.requestTimeout)
                throw UsageServiceError.timeout
            }
            guard let first = try await group.next() else {
                throw UsageServiceError.transport("Codex app-server returned no data")
            }
            group.cancelAll()
            return first
        }
    }

    private func invalidate() async {
        if let transport {
            await transport.stop()
        }
        transport = nil
        isReady = false
        nextRequestId = 1
    }

    private func encode(_ object: Any) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        } catch {
            throw UsageServiceError.protocolError(error.localizedDescription)
        }
    }
}
