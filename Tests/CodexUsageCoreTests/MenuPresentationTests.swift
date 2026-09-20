import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct MenuPresentationTests {
    @Test
    func zeroResetChinesePresentationUsesDisabledCopyAndNoSuffix() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 0, resetCount: 0),
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            errorMessage: nil,
            appearance: .system,
            language: .zhHans
        )

        #expect(presentation.statusTitle == "Codex 100%")
        #expect(presentation.remainingPercent == 100)
        #expect(presentation.resetActionTitle == "当前没有可用 reset")
        #expect(!presentation.isResetEnabled)
        #expect(presentation.lastResetText == "尚未使用过 reset")
    }

    @Test
    func positiveResetEnglishPresentationEnablesActionAndLocalizesTitle() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 27, resetCount: 2),
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            errorMessage: nil,
            appearance: .dark,
            language: .english
        )

        #expect(presentation.statusTitle == "Codex 73% (2 resets)")
        #expect(presentation.resetActionTitle == "Use 1 reset…")
        #expect(presentation.isResetEnabled)
        #expect(presentation.availableResetsText == "Available resets: 2")
    }

    @Test
    func redeemingDisablesResetAction() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 27, resetCount: 1),
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: true,
            errorMessage: nil,
            appearance: .system,
            language: .english
        )

        #expect(!presentation.isResetEnabled)
        #expect(presentation.resetActionTitle == "Using reset…")
    }

    @Test
    func selectedAppearanceAndLanguageHaveExactlyOneCheckmark() {
        let presentation = MenuPresentation(
            snapshot: nil,
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            errorMessage: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.appearanceOptions.filter(\.isSelected).map(\.value) == [.light])
        #expect(presentation.languageOptions.filter(\.isSelected).map(\.value) == [.english])
        #expect(presentation.appearanceOptions.map(\.title) == ["Follow System", "Light", "Dark"])
        #expect(presentation.languageOptions.map(\.title) == ["Follow System", "简体中文", "English"])
    }

    @Test
    func latestResetResultAndErrorAreLocalized() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 50, resetCount: 0),
            lastReset: LastResetRecord(
                attemptedAt: Date(timeIntervalSince1970: 1_795_000_000),
                result: .outcome(.alreadyRedeemed)
            ),
            isRefreshing: false,
            isRedeeming: false,
            errorMessage: "offline",
            appearance: .system,
            language: .english,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.lastResetText.contains("Already redeemed"))
        #expect(presentation.errorText == "Error: offline")
        #expect(presentation.nextResetText?.hasPrefix("Next reset: ") == true)
    }
}

private func makePresentationSnapshot(usedPercent: Double, resetCount: Int) -> UsageSnapshot {
    UsageSnapshot(
        response: RateLimitsResponse(
            rateLimits: RateLimitBucket(
                limitId: "codex",
                limitName: nil,
                normalModelSlug: nil,
                primary: RateLimitWindow(
                    usedPercent: usedPercent,
                    windowDurationMins: 10_080,
                    resetsAt: 1_800_000_000
                ),
                secondary: nil
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(
                availableCount: resetCount,
                credits: resetCount > 0 ? [ResetCredit(id: "credit", status: "available")] : []
            )
        ),
        refreshedAt: Date(timeIntervalSince1970: 1_795_000_000)
    )
}
