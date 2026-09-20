import Combine
import Foundation

public enum UsageServiceError: Error, Equatable, Sendable, LocalizedError {
    case transport(String)
    case timeout
    case protocolError(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .transport(let message), .protocolError(let message), .unavailable(let message):
            return message
        case .timeout:
            return "Request timed out"
        }
    }

    var isRetryableTransportFailure: Bool {
        switch self {
        case .transport, .timeout: true
        case .protocolError, .unavailable: false
        }
    }
}

public protocol UsageService: Sendable {
    func readRateLimits() async throws -> UsageSnapshot
    func consumeReset(idempotencyKey: String, creditId: String?) async throws -> ResetOutcome
}

@MainActor
public final class UsageController: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var isRedeeming = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var lastReset: LastResetRecord?
    @Published public private(set) var appearance: AppAppearance
    @Published public private(set) var language: AppLanguage

    private let service: any UsageService
    private let preferences: PreferencesStore
    private let uuid: @Sendable () -> UUID
    private let now: @Sendable () -> Date
    private var operationInProgress = false

    public init(
        service: any UsageService,
        preferences: PreferencesStore = PreferencesStore(),
        uuid: @escaping @Sendable () -> UUID = UUID.init,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.service = service
        self.preferences = preferences
        self.uuid = uuid
        self.now = now
        appearance = preferences.appearance
        language = preferences.language
        lastReset = preferences.lastReset
    }

    public var statusTitle: String {
        UsageFormatting.statusTitle(
            remainingPercent: UsageFormatting.remainingPercent(
                usedPercent: snapshot?.primaryBucket?.primary?.usedPercent
            ),
            availableResets: snapshot?.availableResetCount ?? 0,
            language: language
        )
    }

    public func setAppearance(_ value: AppAppearance) {
        appearance = value
        preferences.appearance = value
    }

    public func setLanguage(_ value: AppLanguage) {
        language = value
        preferences.language = value
    }

    public func notifySystemLocaleChanged() {
        guard language == .system else { return }
        objectWillChange.send()
    }

    public func refresh() async {
        guard !operationInProgress else { return }
        operationInProgress = true
        isRefreshing = true
        defer {
            isRefreshing = false
            operationInProgress = false
        }
        await performRead()
    }

    @discardableResult
    public func redeemReset() async -> ResetOutcome? {
        guard !operationInProgress, let snapshot, snapshot.availableResetCount > 0 else { return nil }
        operationInProgress = true
        isRedeeming = true
        defer {
            isRedeeming = false
            operationInProgress = false
        }

        let idempotencyKey = uuid().uuidString
        let creditId = snapshot.firstAvailableResetCreditId
        do {
            let outcome = try await consumeWithOneRetry(
                idempotencyKey: idempotencyKey,
                creditId: creditId
            )
            persistLastReset(LastResetRecord(attemptedAt: now(), result: .outcome(outcome)))
            await performRead()
            return outcome
        } catch {
            persistLastReset(LastResetRecord(
                attemptedAt: now(),
                result: .failure(error.localizedDescription)
            ))
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func consumeWithOneRetry(
        idempotencyKey: String,
        creditId: String?
    ) async throws -> ResetOutcome {
        do {
            return try await service.consumeReset(
                idempotencyKey: idempotencyKey,
                creditId: creditId
            )
        } catch let error as UsageServiceError where error.isRetryableTransportFailure {
            return try await service.consumeReset(
                idempotencyKey: idempotencyKey,
                creditId: creditId
            )
        }
    }

    private func performRead() async {
        do {
            snapshot = try await service.readRateLimits()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persistLastReset(_ record: LastResetRecord) {
        lastReset = record
        do {
            try preferences.saveLastReset(record)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
