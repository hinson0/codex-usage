import Foundation

public actor CodexAppServerClient: UsageService {
    private let locator: any CodexBinaryLocating
    private let transportFactory: @Sendable () -> any AppServerTransport
    private let requestTimeout: Duration
    private let now: @Sendable () -> Date
    private var transport: (any AppServerTransport)?
    private var isReady = false
    private var nextRequestId = 1

    public init(
        locator: any CodexBinaryLocating = CodexBinaryLocator(),
        transportFactory: @escaping @Sendable () -> any AppServerTransport = {
            ProcessAppServerTransport()
        },
        requestTimeout: Duration = .seconds(10),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.locator = locator
        self.transportFactory = transportFactory
        self.requestTimeout = requestTimeout
        self.now = now
    }

    public func readRateLimits() async throws -> UsageSnapshot {
        let result: RateLimitsResponse = try await request(
            method: "account/rateLimits/read",
            params: nil
        )
        return UsageSnapshot(response: result, refreshedAt: now())
    }

    public func consumeReset(idempotencyKey: String, creditId: String?) async throws -> ResetOutcome {
        var params: [String: Any] = ["idempotencyKey": idempotencyKey]
        if let creditId { params["creditId"] = creditId }
        let result: ConsumeResetResponse = try await request(
            method: "account/rateLimitResetCredit/consume",
            params: params
        )
        return result.outcome
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
