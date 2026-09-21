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
            error: nil,
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
            error: nil,
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
            error: nil,
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
            error: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.appearanceOptions.filter(\.isSelected).map(\.value) == [.light])
        #expect(presentation.languageOptions.filter(\.isSelected).map(\.value) == [.english])
        #expect(presentation.appearanceOptions.map(\.title) == ["Light", "Dark"])
        #expect(presentation.languageOptions.map(\.title) == ["简体中文", "English"])
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
            error: .message("offline"),
            appearance: .system,
            language: .english,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.lastResetText.contains("Already redeemed"))
        #expect(presentation.errorText == "Error: offline")
        #expect(presentation.nextResetText?.hasPrefix("Next reset: ") == true)
    }

    @Test
    func typedOperationalErrorsRelocalizeWithTheSelectedLanguage() {
        let chinese = MenuPresentation(
            snapshot: nil,
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            error: .authenticationRequired,
            appearance: .light,
            language: .zhHans
        )
        let english = MenuPresentation(
            snapshot: nil,
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            error: .binaryMissing,
            appearance: .system,
            language: .english
        )

        #expect(chinese.errorText == "请先在 Codex 中登录")
        #expect(english.errorText == "Codex command-line tool not found")
    }

    @Test
    func persistedResetFailureRelocalizesInsteadOfKeepingDeadCopy() {
        let presentation = MenuPresentation(
            snapshot: nil,
            lastReset: LastResetRecord(
                attemptedAt: Date(timeIntervalSince1970: 1_795_000_000),
                result: .failure(.timeout)
            ),
            isRefreshing: false,
            isRedeeming: false,
            error: nil,
            appearance: .system,
            language: .zhHans,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.lastResetText.contains("请求超时"))
        #expect(!presentation.lastResetText.contains("Request timed out"))
    }

    @Test
    func integratedPreferencesFooterHidesAuxiliaryQuotasAndBuildsSummaries() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(
                usedPercent: 1,
                resetCount: 0,
                includeAuxiliaryBucket: true
            ),
            lastReset: nil,
            isRefreshing: false,
            isRedeeming: false,
            error: nil,
            appearance: .system,
            language: .zhHans
        )

        #expect(presentation.displayedAdditionalBuckets.isEmpty)
        #expect(presentation.appearanceSummary == "外观 · 浅色")
        #expect(presentation.languageSummary == "语言 · 简体中文")
    }

    @Test
    func appearanceSelectionMapsToNativeMacOSAppearanceNames() {
        #expect(AppAppearance.system.nativeAppearanceName == nil)
        #expect(AppAppearance.light.nativeAppearanceName == "NSAppearanceNameAqua")
        #expect(AppAppearance.dark.nativeAppearanceName == "NSAppearanceNameDarkAqua")
    }
}

private func makePresentationSnapshot(
    usedPercent: Double,
    resetCount: Int,
    includeAuxiliaryBucket: Bool = false
) -> UsageSnapshot {
    let codex = RateLimitBucket(
        limitId: "codex",
        limitName: nil,
        normalModelSlug: nil,
        primary: RateLimitWindow(
            usedPercent: usedPercent,
            windowDurationMins: 10_080,
            resetsAt: 1_800_000_000
        ),
        secondary: nil
    )
    let auxiliary = RateLimitBucket(
        limitId: "base_model_inference",
        limitName: "gpt-reserve",
        normalModelSlug: "gpt-5.6-luna",
        primary: RateLimitWindow(
            usedPercent: 0,
            windowDurationMins: 10_080,
            resetsAt: 1_800_000_000
        ),
        secondary: nil
    )
    return UsageSnapshot(
        response: RateLimitsResponse(
            rateLimits: codex,
            rateLimitsByLimitId: includeAuxiliaryBucket
                ? ["codex": codex, "base_model_inference": auxiliary]
                : nil,
            rateLimitResetCredits: ResetCreditsSummary(
                availableCount: resetCount,
                credits: resetCount > 0 ? [ResetCredit(id: "credit", status: "available")] : []
            )
        ),
        refreshedAt: Date(timeIntervalSince1970: 1_795_000_000)
    )
}
