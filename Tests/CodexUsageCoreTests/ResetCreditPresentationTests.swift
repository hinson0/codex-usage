import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct ResetCreditPresentationTests {
    @Test
    func showsEarliestAvailableCodexCreditExpiry() throws {
        let presentation = try makePresentation(details: """
        [
          {"status":"available","resetType":"codexRateLimits","expiresAt":1793275200},
          {"status":"redeemed","resetType":"codexRateLimits","expiresAt":1793000000},
          {"status":"available","resetType":"unknown","expiresAt":1793000000},
          {"status":"available","resetType":"codexRateLimits","expiresAt":1793188800},
          {"status":"available","resetType":"codexRateLimits","expiresAt":null}
        ]
        """)
        #expect(presentation.resetCreditsText(at: Date(timeIntervalSince1970: 1792627200)) ==
            "重置券 3 张 · 最近到期 10月28日 12:00")
    }

    @Test(arguments: ["null", "[]", "[{}]",
        "[{\"status\":\"available\",\"resetType\":\"codexRateLimits\",\"expiresAt\":null}]"])
    func missingExpiryShowsCountOnly(details: String) throws {
        let presentation = try makePresentation(details: details)
        #expect(presentation.resetCreditsText(at: .now) == "重置券 3 张")
    }

    @Test
    func expiryDisappearsAtDeadlineAndZeroCreditsStayHidden() throws {
        let details = "[{\"status\":\"available\",\"resetType\":\"codexRateLimits\",\"expiresAt\":1793188800}]"
        let presentation = try makePresentation(details: details, count: 1, language: .english)
        #expect(presentation.resetCreditsText(at: Date(timeIntervalSince1970: 1792627200)) ==
            "1 reset credit · Expires Oct 28, 12:00")
        #expect(presentation.resetCreditsText(at: Date(timeIntervalSince1970: 1793188800)) == "1 reset credit")
        for count in [0, -1] {
            #expect(try makePresentation(details: details, count: count).resetCreditsText(at: .distantPast) == nil)
        }
        #expect(try makePresentation(details: "null", language: .english).resetCreditsText(at: .now) ==
            "3 reset credits")
    }

    @Test
    func crossYearExpiryIncludesYearAndUsesLocalTimeZone() throws {
        let original = try makePresentation(details:
            "[{\"status\":\"available\",\"resetType\":\"codexRateLimits\",\"expiresAt\":1793188800}]")
        let presentation = MenuPresentation(snapshot: original.snapshot, isRefreshing: false, error: nil,
            appearance: .light, language: .zhHans, timeZone: TimeZone(secondsFromGMT: 28800)!)
        #expect(presentation.resetCreditsText(at: Date(timeIntervalSince1970: 1704067200)) ==
            "重置券 3 张 · 最近到期 2026年10月28日 20:00")
    }

    private func makePresentation(details: String, count: Int = 3,
                                  language: AppLanguage = .zhHans) throws -> MenuPresentation {
        let data = Data("""
        {"rateLimitResetCredits":{"availableCount":\(count),"credits":\(details)}}
        """.utf8)
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        return MenuPresentation(snapshot: UsageSnapshot(response: response, refreshedAt: .distantPast),
                                isRefreshing: false, error: nil, appearance: .light,
                                language: language, timeZone: TimeZone(secondsFromGMT: 0)!)
    }
}
