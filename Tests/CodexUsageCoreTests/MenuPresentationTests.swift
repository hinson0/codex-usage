import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct MenuPresentationTests {
    @Test
    func weeklyOnlyPresentationUsesOnePercentageAndHidesZeroResetCount() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 0, resetCount: 0),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .zhHans
        )

        #expect(presentation.statusTitle == "Codex 100%")
        #expect(presentation.usagePercentText == "100%")
        #expect(presentation.remainingPercent == 100)
        #expect(presentation.availableResetsText == nil)
        #expect(presentation.fiveHourStatusText == "无限制")
    }

    @Test
    func positiveResetCountIsReadOnlyCompactTextAndStatusSuffix() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 27, resetCount: 2),
            isRefreshing: false,
            error: nil,
            appearance: .dark,
            language: .english
        )

        #expect(presentation.statusTitle == "Codex 73% (2 resets)")
        #expect(presentation.availableResetsText == "2 resets")
    }

    @Test
    func oneEnglishResetUsesSingularReadOnlyCopy() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 27, resetCount: 1),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.availableResetsText == "1 reset")
    }

    @Test
    func dualWindowsShowFiveHourThenLongerRemainingWhileProgressTracksLongerWindow() {
        let presentation = MenuPresentation(
            snapshot: makeDualWindowSnapshot(
                fiveHourUsedPercent: 20,
                longerUsedPercent: 6,
                resetCount: 2
            ),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(presentation.statusTitle == "Codex 80%-94% (2 resets)")
        #expect(presentation.usagePercentText == "80% - 94%")
        #expect(presentation.remainingPercent == 94)
        #expect(presentation.fiveHourStatusText == nil)
        #expect(presentation.nextResetText == "Next reset: Jan 15, 2027 at 8:00 AM")
    }

    @Test
    func missingLongerWindowPercentageDoesNotReuseFiveHourForProgress() {
        let presentation = MenuPresentation(
            snapshot: makeDualWindowSnapshot(
                fiveHourUsedPercent: 20,
                longerUsedPercent: nil,
                resetCount: 0
            ),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.remainingPercent == nil)
        #expect(presentation.statusTitle == "Codex 80%")
    }

    @Test
    func twoFiveHourWindowsNeverInventALongerWindow() {
        let snapshot = makeSnapshot(
            primary: RateLimitWindow(
                usedPercent: 20,
                windowDurationMins: 300,
                resetsAt: 1_790_000_000
            ),
            secondary: RateLimitWindow(
                usedPercent: 6,
                windowDurationMins: 300,
                resetsAt: 1_800_000_000
            )
        )
        let presentation = MenuPresentation(
            snapshot: snapshot,
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.statusTitle == "Codex 80%")
        #expect(presentation.usagePercentText == "80%")
        #expect(presentation.remainingPercent == 80)
    }

    @Test
    func windowOrderingUsesDurationInsteadOfPrimarySecondarySlot() {
        let snapshot = makeSnapshot(
            primary: RateLimitWindow(
                usedPercent: 6,
                windowDurationMins: 10_080,
                resetsAt: 1_800_000_000
            ),
            secondary: RateLimitWindow(
                usedPercent: 20,
                windowDurationMins: 300,
                resetsAt: 1_790_000_000
            )
        )
        let presentation = MenuPresentation(
            snapshot: snapshot,
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english
        )

        #expect(presentation.statusTitle == "Codex 80%-94%")
        #expect(presentation.usagePercentText == "80% - 94%")
        #expect(presentation.remainingPercent == 94)
    }

    @Test
    func selectedAppearanceAndLanguageHaveExactlyOneCheckmark() {
        let presentation = MenuPresentation(
            snapshot: nil,
            isRefreshing: false,
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
    func typedOperationalErrorsRelocalizeWithTheSelectedLanguage() {
        let chinese = MenuPresentation(
            snapshot: nil,
            isRefreshing: false,
            error: .authenticationRequired,
            appearance: .light,
            language: .zhHans
        )
        let english = MenuPresentation(
            snapshot: nil,
            isRefreshing: false,
            error: .binaryMissing,
            appearance: .dark,
            language: .english
        )

        #expect(chinese.errorText == "请先在 Codex 中登录")
        #expect(english.errorText == "Codex command-line tool not found")
    }

    @Test
    func integratedPreferencesFooterHidesAuxiliaryQuotasAndBuildsSummaries() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(
                usedPercent: 1,
                resetCount: 0,
                includeAuxiliaryBucket: true
            ),
            isRefreshing: false,
            error: nil,
            appearance: .system,
            language: .zhHans
        )

        #expect(presentation.displayedAdditionalBuckets.isEmpty)
        #expect(presentation.appearanceSummary == "外观 · 浅色")
        #expect(presentation.languageSummary == "语言 · 简体中文")
    }

    @Test
    func appearanceSelectionIsScopedToPopoverInsteadOfWholeApplication() {
        #expect(AppAppearance.light.nativeAppearancePolicy.applicationName == nil)
        #expect(AppAppearance.light.nativeAppearancePolicy.popoverName == "NSAppearanceNameAqua")
        #expect(AppAppearance.light.nativeAppearancePolicy.backgroundStyle == .opaqueWhite)
        #expect(AppAppearance.dark.nativeAppearancePolicy.applicationName == nil)
        #expect(AppAppearance.dark.nativeAppearancePolicy.popoverName == "NSAppearanceNameDarkAqua")
        #expect(AppAppearance.dark.nativeAppearancePolicy.backgroundStyle == .opaqueWindow)
    }

    @Test
    func availableUpdateChangesTitleIndependentlyOfUsageAndCheckAvailability() {
        for language in [AppLanguage.english, .zhHans] {
            for canCheck in [false, true] {
                let presentation = MenuPresentation(
                    snapshot: nil,
                    isRefreshing: true,
                    error: .authenticationRequired,
                    appearance: .dark,
                    language: language,
                    canCheckForUpdates: canCheck,
                    hasAvailableUpdate: true
                )
                #expect(presentation.checkForUpdatesTitle == (
                    language == .zhHans ? "有新版本" : "Update Available"
                ))
                #expect(presentation.isUpdateEnabled == canCheck)
            }
        }
    }

    @Test
    func updateActionRelocalizesAndFollowsInjectedAvailability() {
        let english = MenuPresentation(
            snapshot: nil,
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .english,
            canCheckForUpdates: true
        )
        let chinese = MenuPresentation(
            snapshot: nil,
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .zhHans,
            canCheckForUpdates: false
        )

        #expect(english.checkForUpdatesTitle == "Check for Updates…")
        #expect(english.isUpdateEnabled)
        #expect(chinese.checkForUpdatesTitle == "检查更新…")
        #expect(!chinese.isUpdateEnabled)
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
            rateLimitResetCredits: ResetCreditsSummary(availableCount: resetCount)
        ),
        refreshedAt: Date(timeIntervalSince1970: 1_795_000_000)
    )
}

private func makeDualWindowSnapshot(
    fiveHourUsedPercent: Double,
    longerUsedPercent: Double?,
    resetCount: Int
) -> UsageSnapshot {
    let codex = RateLimitBucket(
        limitId: "codex",
        limitName: nil,
        normalModelSlug: nil,
        primary: RateLimitWindow(
            usedPercent: fiveHourUsedPercent,
            windowDurationMins: 300,
            resetsAt: 1_790_000_000
        ),
        secondary: RateLimitWindow(
            usedPercent: longerUsedPercent,
            windowDurationMins: 10_080,
            resetsAt: 1_800_000_000
        )
    )
    return UsageSnapshot(
        response: RateLimitsResponse(
            rateLimits: codex,
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(availableCount: resetCount)
        ),
        refreshedAt: Date(timeIntervalSince1970: 1_795_000_000)
    )
}

private func makeSnapshot(
    primary: RateLimitWindow?,
    secondary: RateLimitWindow?
) -> UsageSnapshot {
    UsageSnapshot(
        response: RateLimitsResponse(
            rateLimits: RateLimitBucket(
                limitId: "codex",
                limitName: nil,
                normalModelSlug: nil,
                primary: primary,
                secondary: secondary
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(availableCount: 0)
        ),
        refreshedAt: Date(timeIntervalSince1970: 1_795_000_000)
    )
}
