import Foundation
import Testing
@testable import CodexUsageCore

@Suite struct ResetNewsTests {
    @Test func acceptsCurrentWebsiteEnvelope() throws {
        let news = try ResetNews.decode(Data("""
        {"events":[{"tool":"codex","type":"usage_reset","stage":"scheduled",
          "summary":"所有付费用户的 Codex 额度即将重置，预计北京时间 10月24日 01:00前到账。",
          "occasion":"28 天活动第 18 天","announcedAt":"2026-10-23T04:46:19Z",
          "updatedAt":"2026-10-23T04:47:34Z",
          "forecast":{"at":"2026-10-23T17:00:00Z","bound":"before"}}]}
        """.utf8))
        #expect(news.latest?.summary == "所有付费用户的 Codex 额度即将重置，预计北京时间 10月24日 01:00前到账。")
        #expect(news.latest?.statusText(language: .zhHans,
            now: ISO8601DateFormatter().date(from: "2026-10-24T02:00:00Z")!) == "待确认")
        #expect(news.latest?.occasion == "28 天活动第 18 天")
        #expect(news.latest?.updatedAt == ISO8601DateFormatter().date(from: "2026-10-23T04:47:34Z"))
    }
    @Test func keepsOnlyTheLatestCodexRecordAndIgnoresPolicyOtherToolsAndFutureAnnouncements() throws {
        let news = try ResetNews.decode(Data("""
        {"events":[
          {"tool":"codex","type":"usage_reset","stage":"completed","summary":"Older reset",
           "announcedAt":"2026-10-20T00:00:00Z","updatedAt":"2026-10-24T01:00:00Z"},
          {"tool":"codex","type":"reset_card","stage":"completed","summary":"Latest credit distribution",
           "announcedAt":"2026-10-22T00:00:00Z","completedAt":"2026-10-23T01:00:00Z"},
          {"tool":"claude-code","type":"usage_reset","stage":"completed","summary":"Other tool",
           "announcedAt":"2026-10-24T00:00:00Z"},
          {"tool":"codex","type":"policy","stage":"completed","summary":"Policy",
           "announcedAt":"2026-10-24T00:00:00Z"},
          {"tool":"codex","type":"usage_reset","stage":"scheduled","summary":"Future",
           "announcedAt":"2026-10-25T00:00:00Z"},
          {"tool":"codex","type":"usage_reset","stage":"completed","summary":"Invalid date",
           "announcedAt":"invalid"}
        ]}
        """.utf8), now: ISO8601DateFormatter().date(from: "2026-10-24T02:00:00Z")!)
        #expect(news.latest?.summary == "Latest credit distribution")
        #expect(news.latest?.statusText(language: .english, now: .distantFuture) == "Completed")
        #expect(news.latest?.updatedAt == nil)
        #expect(try ResetNews.decode(Data(#"{"events":[]}"#.utf8)).latest == nil)
    }

    @Test func matchesWebsiteLatestSignalBeforeFallingBackToCompletedHistory() throws {
        let news = try ResetNews.decode(Data("""
        {"events":[
          {"tool":"codex","type":"usage_reset","stage":"completed","summary":"Completed history",
           "announcedAt":"2026-10-23T05:00:00Z","completedAt":"2026-10-24T00:00:00Z"},
          {"tool":"codex","type":"usage_reset","stage":"scheduled","summary":"Current website signal",
           "announcedAt":"2026-10-23T04:00:00Z"}
        ]}
        """.utf8), now: ISO8601DateFormatter().date(from: "2026-10-24T02:00:00Z")!)
        #expect(news.latest?.summary == "Current website signal")
    }

    @Test func elapsedForecastNeverClaimsCompletionAndAroundHasAnHourOfGrace() throws {
        let news = try ResetNews.decode(Data("""
        {"events":[{"tool":"codex","type":"usage_reset","stage":"rolling_out",
          "summary":"Latest rollout","announcedAt":"2026-10-23T04:46:19.000Z",
          "forecast":{"at":"2026-10-23T17:00:00Z","bound":"around"}}]}
        """.utf8))
        #expect(news.latest?.statusText(language: .english,
            now: ISO8601DateFormatter().date(from: "2026-10-23T17:30:00Z")!) == "Rolling out")
        #expect(news.latest?.statusText(language: .english,
            now: ISO8601DateFormatter().date(from: "2026-10-23T18:00:01Z")!) == "Unconfirmed")
        #expect(news.latest?.stage == .rollingOut)
    }

}

private actor NewsSequence: ResetNewsService {
    var calls = 0
    func readNews() async throws -> ResetNews {
        calls += 1
        if calls > 1 { throw URLError(.notConnectedToInternet) }
        return try ResetNews.decode(Data("""
        {"events":[{"tool":"codex","type":"usage_reset","stage":"completed",
          "summary":"Cached public announcement","announcedAt":"2020-01-01T00:00:00Z"}]}
        """.utf8))
    }
}

private struct UnavailableUsage: UsageService {
    func readRateLimits() async throws -> UsageSnapshot { throw UsageServiceError.authenticationRequired }
}

extension ResetNewsTests {
    @Test @MainActor func newsSurvivesAccountFailureAndRetainsStaleResultOnNetworkFailure() async {
        let service = NewsSequence()
        let controller = UsageController(service: UnavailableUsage(), newsService: service)
        await controller.refresh()
        #expect(controller.resetNews?.latest?.summary == "Cached public announcement")
        #expect(controller.displayError == .authenticationRequired)
        #expect(!controller.newsFailed)
        await controller.refresh()
        #expect(await service.calls == 1)
        await controller.refresh(forceNews: true)
        #expect(controller.resetNews?.latest?.summary == "Cached public announcement")
        #expect(controller.newsFailed)
        #expect(!controller.newsLoading)
        #expect(!controller.isRefreshing)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_USAGE_RUN_NEWS_INTEGRATION"] == "1"))
    func publicFeedReadOnlyIntegration() async throws {
        let news = try await DivinResetNewsService().readNews()
        #expect(news.latest != nil)
    }
}
