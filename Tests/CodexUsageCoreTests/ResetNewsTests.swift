import Foundation
import Testing
@testable import CodexUsageCore

@Suite struct ResetNewsTests {
    @Test func selectsCompletedResetAndLatestForecastWithoutMixingCreditsOrTools() throws {
        let news = try ResetNews.decode(Data("""
        [
          {"tool":"codex","eventType":"额度重置","eventStatus":"scheduled","sortTime":"2026-10-22T06:55:54Z","forecast":{"at":"2026-10-22T18:00:00Z","deadline":true}},
          {"tool":"codex","eventType":"额度重置","eventStatus":"completed","sortTime":"2026-10-20T06:33:48Z"},
          {"tool":"codex","eventType":"重置卡发放","eventStatus":"completed","sortTime":"2026-10-22T08:00:00Z"},
          {"tool":"claude-code","eventType":"额度重置","eventStatus":"completed","sortTime":"2026-10-22T09:00:00Z"},
          {"tool":"codex","eventType":"额度重置","eventStatus":"completed","sortTime":"invalid"}
        ]
        """.utf8))
        #expect(news.completedAt == ISO8601DateFormatter().date(from: "2026-10-20T06:33:48Z"))
        #expect(news.forecast?.date == ISO8601DateFormatter().date(from: "2026-10-22T18:00:00Z"))
        #expect(news.forecast?.isDeadline == true)
        #expect(news.forecastText(language: .zhHans, timeZone: TimeZone(secondsFromGMT: 28800)!) == "预计 2026年10月23日 02:00前")
    }

    @Test func completedEventSupersedesOlderForecastAndUnknownStatusIsIgnored() throws {
        let news = try ResetNews.decode(Data("""
        [{"tool":"codex","eventType":"额度重置","eventStatus":"scheduled","sortTime":"2026-10-19T00:00:00Z"},
         {"tool":"codex","eventType":"额度重置","eventStatus":"completed","sortTime":"2026-10-20T00:00:00Z"},
         {"tool":"codex","eventType":"额度重置","sortTime":"2026-10-22T00:00:00Z"}]
        """.utf8))
        #expect(news.forecast == nil)
        #expect(news.completedAt != nil)
    }

    @Test func unknownForecastDateAndExpiredForecastNeverClaimCompletion() throws {
        let news = try ResetNews.decode(Data("""
        [{"tool":"codex","eventType":"额度重置","eventStatus":"scheduled","sortTime":"2026-10-22T00:00:00.000Z"}]
        """.utf8))
        #expect(news.forecast != nil)
        #expect(news.forecastText(language: .english) == "Time not announced")
        #expect(news.completedAt == nil)
        #expect(try ResetNews.decode(Data("[]".utf8)).completedAt == nil)
        let forecast = ResetForecast(announcedAt: .distantPast, date: .distantPast, isDeadline: true)
        #expect(forecast.statusText(language: .zhHans, now: .now) == "待确认")
    }
}

private actor NewsSequence: ResetNewsService {
    var calls = 0
    func readNews() async throws -> ResetNews {
        calls += 1
        if calls > 1 { throw URLError(.notConnectedToInternet) }
        return try ResetNews.decode(Data("[]".utf8))
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
        #expect(controller.resetNews != nil)
        #expect(controller.displayError == .authenticationRequired)
        #expect(!controller.newsFailed)
        await controller.refresh()
        #expect(await service.calls == 1)
        await controller.refresh(forceNews: true)
        #expect(controller.resetNews != nil)
        #expect(controller.newsFailed)
        #expect(!controller.newsLoading)
        #expect(!controller.isRefreshing)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODEX_USAGE_RUN_NEWS_INTEGRATION"] == "1"))
    func publicFeedReadOnlyIntegration() async throws {
        let news = try await DivinResetNewsService().readNews()
        #expect(news.completedAt != nil)
    }
}
