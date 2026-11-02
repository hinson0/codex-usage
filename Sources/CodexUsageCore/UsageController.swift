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
    func readRateLimits(forceDetails: Bool) async throws -> UsageSnapshot
}

public extension UsageService {
    func readRateLimits(forceDetails: Bool) async throws -> UsageSnapshot {
        try await readRateLimits()
    }
}

enum UsageRefreshPolicy {
    static let normalInterval: TimeInterval = 600
    static let lowInterval: TimeInterval = 120

    static func interval(for bucket: RateLimitBucket?) -> TimeInterval {
        guard bucket?.limitId == "codex" else { return normalInterval }
        let windows = UsageFormatting.windows(in: bucket)
        let low = [windows.fiveHour, windows.longer].contains { window in
            guard let used = window?.usedPercent, used.isFinite else { return false }
            return 100 - used < 10
        }
        return low ? lowInterval : normalInterval
    }
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
    private let now: () -> Date
    private var operationInProgress = false
    private var monitoring = false
    private var monitorSleep: Task<Void, Error>?
    private var manualRefreshRevision = 0
    private var lastUsageAttempt: Date?

    public init(
        service: any UsageService,
        preferences: PreferencesStore = PreferencesStore(),
        newsService: (any ResetNewsService)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.newsService = newsService
        self.service = service
        self.preferences = preferences
        self.now = now
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
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        guard !monitoring else { return }
        monitoring = true
        defer {
            monitorSleep?.cancel()
            monitorSleep = nil
            monitoring = false
        }
        if snapshot == nil { await refresh() }
        var delay = nextRefreshDelay()
        while !Task.isCancelled {
            let revision = manualRefreshRevision
            let scheduledDelay = delay
            let sleeper = Task { @MainActor in try await sleep(.seconds(scheduledDelay)) }
            monitorSleep = sleeper
            do {
                try await withTaskCancellationHandler {
                    try await sleeper.value
                } onCancel: {
                    sleeper.cancel()
                }
            } catch {
                guard !Task.isCancelled, revision != manualRefreshRevision else { return }
            }
            monitorSleep = nil
            guard !Task.isCancelled else { return }
            if sleeper.isCancelled && revision == manualRefreshRevision { return }
            if revision != manualRefreshRevision {
                delay = nextRefreshDelay()
                if delay > 0 { continue }
            }
            await refresh()
            delay = nextRefreshDelay()
        }
    }

    private func nextRefreshDelay() -> TimeInterval {
        let interval = UsageRefreshPolicy.interval(for: snapshot?.primaryBucket)
        let date = now()
        let attempts = [lastUsageAttempt, newsService == nil ? nil : lastNewsAttempt].compactMap { $0 }
        guard let oldest = attempts.min() else { return interval }
        return max(0, interval - max(0, date.timeIntervalSince(oldest))).rounded(.up)
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
        await performRead(forceDetails: forceNews)
        lastUsageAttempt = now()
        await newsRead
        // A fresh quota may shorten the news lifetime in this same cycle.
        await refreshNews(force: false)
        if forceNews {
            manualRefreshRevision += 1
            monitorSleep?.cancel()
        }
    }

    private func refreshNews(force: Bool) async {
        guard let newsService else { return }
        let interval = UsageRefreshPolicy.interval(for: snapshot?.primaryBucket)
        if !force, let lastNewsAttempt {
            let age = now().timeIntervalSince(lastNewsAttempt)
            if age >= 0 && age < interval { return }
        }
        newsLoading = true
        defer {
            lastNewsAttempt = now()
            newsLoading = false
        }
        do {
            resetNews = try await newsService.readNews()
            newsFailed = false
        } catch {
            newsFailed = true
        }
    }

    private func performRead(forceDetails: Bool) async {
        do {
            snapshot = try await service.readRateLimits(forceDetails: forceDetails)
            displayError = nil
        } catch {
            displayError = UsageDisplayError(error)
            if displayError == .authenticationRequired {
                snapshot = nil
            }
        }
    }

}
