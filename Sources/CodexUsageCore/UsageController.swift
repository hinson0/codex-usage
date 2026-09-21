import Combine
import Foundation

public enum UsageServiceError: Error, Equatable, Sendable, LocalizedError {
    case transport(String)
    case timeout
    case authenticationRequired
    case binaryMissing
    case protocolError(String)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .transport(let message), .protocolError(let message), .unavailable(let message):
            return message
        case .timeout:
            return "Request timed out"
        case .authenticationRequired:
            return "Sign in to Codex first"
        case .binaryMissing:
            return "Codex command-line tool not found"
        }
    }
}

public enum UsageDisplayError: Codable, Equatable, Sendable {
    case authenticationRequired
    case binaryMissing
    case timeout
    case message(String)

    init(_ error: Error) {
        switch error as? UsageServiceError {
        case .authenticationRequired?: self = .authenticationRequired
        case .binaryMissing?: self = .binaryMissing
        case .timeout?: self = .timeout
        default: self = .message(error.localizedDescription)
        }
    }
}

public protocol UsageService: Sendable {
    func readRateLimits() async throws -> UsageSnapshot
}

@MainActor
public final class UsageController: ObservableObject {
    @Published public private(set) var snapshot: UsageSnapshot?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var displayError: UsageDisplayError?
    @Published public private(set) var appearance: AppAppearance
    @Published public private(set) var language: AppLanguage

    private let service: any UsageService
    private let preferences: PreferencesStore
    private var operationInProgress = false

    public init(
        service: any UsageService,
        preferences: PreferencesStore = PreferencesStore()
    ) {
        self.service = service
        self.preferences = preferences
        appearance = preferences.appearance
        language = preferences.language
    }

    public var statusTitle: String {
        let windows = UsageFormatting.windows(in: snapshot?.primaryBucket)
        return UsageFormatting.statusTitle(
            fiveHourRemainingPercent: UsageFormatting.remainingPercent(
                usedPercent: windows.fiveHour?.usedPercent
            ),
            longerRemainingPercent: UsageFormatting.remainingPercent(
                usedPercent: windows.longer?.usedPercent
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

    private func performRead() async {
        do {
            snapshot = try await service.readRateLimits()
            displayError = nil
        } catch {
            displayError = UsageDisplayError(error)
        }
    }

}
