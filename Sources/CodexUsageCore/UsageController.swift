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
            return "Sign in to ChatGPT first"
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

    @Published public private(set) var resetNews: ResetNews?
    @Published public private(set) var newsFailed = false
    @Published public private(set) var newsLoading = false
    private let newsService: (any ResetNewsService)?
    private var lastNewsAttempt: Date?

    private let service: any UsageService
    private let preferences: PreferencesStore
    private var operationInProgress = false

    public init(
        service: any UsageService,
        preferences: PreferencesStore = PreferencesStore(),
        newsService: (any ResetNewsService)? = nil
    ) {
        self.newsService = newsService
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

    public func monitorUsage(
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        await refresh()
        while !Task.isCancelled {
            let windows = UsageFormatting.windows(in: snapshot?.primaryBucket)
            let hasLowAllowance = [windows.fiveHour, windows.longer].contains { window in
                guard let usedPercent = window?.usedPercent, usedPercent.isFinite else { return false }
                return 100 - usedPercent < 10
            }
            do {
                try await sleep(.seconds(hasLowAllowance ? 120 : 300))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    public func refresh(forceNews: Bool = false) async {
        guard !operationInProgress else { return }
        operationInProgress = true
        isRefreshing = true
        defer {
            isRefreshing = false
            operationInProgress = false
        }
        async let newsRead: Void = refreshNews(force: forceNews)
        await performRead()
        await newsRead
    }

    private func refreshNews(force: Bool) async {
        guard let newsService else { return }
        if !force, let lastNewsAttempt, Date().timeIntervalSince(lastNewsAttempt) < 300 { return }
        lastNewsAttempt = Date()
        newsLoading = true
        defer { newsLoading = false }
        do {
            resetNews = try await newsService.readNews()
            newsFailed = false
        } catch {
            newsFailed = true
        }
    }

    private func performRead() async {
        do {
            snapshot = try await service.readRateLimits()
            displayError = nil
        } catch {
            displayError = UsageDisplayError(error)
            if displayError == .authenticationRequired {
                snapshot = nil
            }
        }
    }

}
