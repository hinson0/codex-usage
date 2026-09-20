import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct UsageDomainTests {
    @Test
    func selectsCodexBucketAndSortsAdditionalBuckets() {
        let response = RateLimitsResponse(
            rateLimits: makeBucket(id: "legacy", used: 90),
            rateLimitsByLimitId: [
                "zeta": makeBucket(id: "zeta", used: 25),
                "codex": makeBucket(id: "codex", used: 27),
                "alpha": makeBucket(id: "alpha", used: 50),
            ],
            rateLimitResetCredits: ResetCreditsSummary(availableCount: 2, credits: [])
        )

        let snapshot = UsageSnapshot(response: response, refreshedAt: Date(timeIntervalSince1970: 100))

        #expect(snapshot.primaryBucket?.limitId == "codex")
        #expect(snapshot.additionalBuckets.map(\.limitId) == ["alpha", "zeta"])
        #expect(snapshot.availableResetCount == 2)
    }

    @Test
    func fallsBackToLegacyBucketAndMissingResetSummaryMeansZero() {
        let response = RateLimitsResponse(
            rateLimits: makeBucket(id: "legacy", used: 5),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: nil
        )

        let snapshot = UsageSnapshot(response: response, refreshedAt: .distantPast)

        #expect(snapshot.primaryBucket?.limitId == "legacy")
        #expect(snapshot.additionalBuckets.isEmpty)
        #expect(snapshot.availableResetCount == 0)
    }

    @Test
    func remainingPercentageIsRoundedAndClamped() {
        let cases: [(used: Double, expected: Int)] = [
            (-5, 100),
            (26.6, 73),
            (99.6, 0),
            (140, 0),
        ]

        for item in cases {
            #expect(UsageFormatting.remainingPercent(usedPercent: item.used) == item.expected)
        }
    }

    @Test
    func missingPercentageHasPlaceholderTitleWithoutResetSuffix() {
        #expect(UsageFormatting.statusTitle(remainingPercent: nil, availableResets: 2, language: .english) == "Codex --%")
    }

    @Test
    func zeroResetsHideSuffixInBothLanguages() {
        #expect(UsageFormatting.statusTitle(remainingPercent: 100, availableResets: 0, language: .zhHans) == "Codex 100%")
        #expect(UsageFormatting.statusTitle(remainingPercent: 100, availableResets: 0, language: .english) == "Codex 100%")
    }

    @Test
    func positiveResetsUseLocalizedSuffix() {
        #expect(UsageFormatting.statusTitle(remainingPercent: 73, availableResets: 2, language: .zhHans) == "Codex 73%(2 次)")
        #expect(UsageFormatting.statusTitle(remainingPercent: 73, availableResets: 1, language: .english) == "Codex 73% (1 reset)")
        #expect(UsageFormatting.statusTitle(remainingPercent: 73, availableResets: 2, language: .english) == "Codex 73% (2 resets)")
    }

    @Test
    func decodesPartialResponseAndIgnoresUnknownFields() throws {
        let json = Data(#"""
        {
          "rateLimits": {
            "limitId": "codex",
            "primary": { "usedPercent": 12, "unknown": true },
            "futureField": "ignored"
          },
          "anotherFutureField": 42
        }
        """#.utf8)

        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: json)
        let snapshot = UsageSnapshot(response: response, refreshedAt: .distantPast)

        #expect(snapshot.primaryBucket?.primary?.usedPercent == 12)
        #expect(snapshot.availableResetCount == 0)
    }

    @Test
    func decodesEveryResetOutcomeIncludingUnknownValues() throws {
        let cases: [(raw: String, expected: ResetOutcome)] = [
            ("reset", .reset),
            ("alreadyRedeemed", .alreadyRedeemed),
            ("nothingToReset", .nothingToReset),
            ("noCredit", .noCredit),
            ("futureOutcome", .unknown("futureOutcome")),
        ]

        for item in cases {
            let data = Data("{\"outcome\":\"\(item.raw)\"}".utf8)
            let response = try JSONDecoder().decode(ConsumeResetResponse.self, from: data)
            #expect(response.outcome == item.expected)
        }
    }
}

private func makeBucket(id: String, used: Double) -> RateLimitBucket {
    RateLimitBucket(
        limitId: id,
        limitName: nil,
        normalModelSlug: nil,
        primary: RateLimitWindow(usedPercent: used, windowDurationMins: 60, resetsAt: 200),
        secondary: nil
    )
}
