import Foundation
import Testing
@testable import CodexUsageCore

private func reviewPreferences() -> PreferencesStore {
    PreferencesStore(defaults: UserDefaults(suiteName: "CodexReview.\(UUID())")!)
}

private func reviewSnapshot() -> UsageSnapshot {
    UsageSnapshot(response: RateLimitsResponse(
        rateLimits: RateLimitBucket(limitId: "codex", limitName: nil, normalModelSlug: nil,
            primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 10080, resetsAt: 999),
            secondary: nil),
        rateLimitsByLimitId: nil, rateLimitResetCredits: nil
    ), refreshedAt: Date(timeIntervalSince1970: 100))
}

private actor GateUsage: UsageService {
    private var gate: CheckedContinuation<Void, Never>?
    var started: Bool { gate != nil }
    func readRateLimits() async throws -> UsageSnapshot {
        await withCheckedContinuation { gate = $0 }
        return reviewSnapshot()
    }
    func release() { gate?.resume(); gate = nil }
}

private actor ReviewNews: ResetNewsService {
    private(set) var calls = 0
    let advance: @Sendable () async -> Void
    init(advance: @escaping @Sendable () async -> Void = {}) { self.advance = advance }
    func readNews() async throws -> ResetNews {
        calls += 1
        await advance()
        return try ResetNews.decode(Data("{\"events\":[]}".utf8))
    }
}

private struct ImmediateUsage: UsageService {
    func readRateLimits() async throws -> UsageSnapshot { reviewSnapshot() }
}

@MainActor private final class ReviewClock { var date = Date(timeIntervalSince1970: 100) }

@Suite struct ReviewRegressionTests {
    @Test @MainActor func newsCacheAgeStartsWhenReadCompletes() async {
        let clock = ReviewClock()
        let news = ReviewNews(advance: { await MainActor.run { clock.date.addTimeInterval(10) } })
        let controller = UsageController(service: ImmediateUsage(), preferences: reviewPreferences(), newsService: news, now: { clock.date })
        await controller.refresh()
        clock.date.addTimeInterval(599)
        await controller.refresh()
        #expect(await news.calls == 1)
        clock.date.addTimeInterval(1)
        await controller.refresh()
        #expect(await news.calls == 2)
    }

    @Test @MainActor func reviewNewsStartsWhileQuotaIsStillPending() async throws {
        let usage = GateUsage()
        let news = ReviewNews()
        let controller = UsageController(service: usage, preferences: reviewPreferences(), newsService: news)
        let pending = Task { await controller.refresh() }
        for _ in 0..<100 {
            if await usage.started { break }
            try await Task.sleep(for: .milliseconds(2))
        }
        try await Task.sleep(for: .milliseconds(100))
        let beforeQuotaFinishes = await news.calls
        await usage.release()
        await pending.value
        #expect(beforeQuotaFinishes == 1)
    }

    @Test @MainActor func reviewTimerAccountsForTimeSpentLoadingOtherData() async {
        let clock = ReviewClock()
        let news = ReviewNews(advance: { await MainActor.run { clock.date.addTimeInterval(10) } })
        let controller = UsageController(service: ImmediateUsage(), preferences: reviewPreferences(), newsService: news, now: { clock.date })
        var waits: [Duration] = []
        await controller.monitorUsage { duration in
            waits.append(duration)
            throw CancellationError()
        }
        #expect(waits == [.seconds(590)])
    }
}
