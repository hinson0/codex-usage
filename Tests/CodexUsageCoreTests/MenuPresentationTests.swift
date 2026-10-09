import Foundation
import Testing
@testable import CodexUsageCore

@Suite
struct MenuPresentationTests {
    @Test(arguments: [AppLanguage.english, .zhHans])
    func feedbackEntryHasLocalizedCopy(language: AppLanguage) {
        let presentation = MenuPresentation(
            snapshot: nil, isRefreshing: true, error: .authenticationRequired,
            appearance: .dark, language: language
        )

        #expect(presentation.text(.feedback) == (language == .zhHans ? "反馈" : "Feedback"))
        #expect(presentation.text(.feedbackHint) == (
            language == .zhHans ? "在浏览器中打开 GitHub Issues" : "Open GitHub Issues in your browser"
        ))
    }

    @Test(arguments: [AppLanguage.english, .zhHans])
    func feedbackEntryOpensProjectIssuesRegardlessOfUsageState(language: AppLanguage) {
        for snapshot in [nil, makePresentationSnapshot(usedPercent: 27, resetCount: 0)] {
            for error: UsageDisplayError? in [nil, .authenticationRequired, .timeout] {
                let presentation = MenuPresentation(
                    snapshot: snapshot, isRefreshing: true, error: error,
                    appearance: .light, language: language, canCheckForUpdates: false
                )

                #expect(presentation.feedbackURL.absoluteString == "https://github.com/hinson0/codex-usage/issues")
                #expect(presentation.feedbackURL.query == nil)
                #expect(presentation.feedbackURL.fragment == nil)
            }
        }
    }

    @Test
    func weeklyOnlyPresentationUsesOnePercentageAndHidesZeroResetCount() {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 0, resetCount: 0),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: .zhHans
        )

        #expect(presentation.statusTitle == "100%")
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

        #expect(presentation.statusTitle == "73% (2)")
        #expect(presentation.availableResetsText == "(2)")
    }

    @Test(arguments: [AppLanguage.english, .zhHans, .system])
    func oneResetUsesBareParenthesizedCount(language: AppLanguage) {
        let presentation = MenuPresentation(
            snapshot: makePresentationSnapshot(usedPercent: 27, resetCount: 1),
            isRefreshing: false,
            error: nil,
            appearance: .light,
            language: language
        )

        #expect(presentation.availableResetsText == "(1)")
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

        #expect(presentation.statusTitle == "80%-94% (2)")
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
        #expect(presentation.statusTitle == "80%")
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

        #expect(presentation.statusTitle == "80%")
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

        #expect(presentation.statusTitle == "80%-94%")
        #expect(presentation.usagePercentText == "80% - 94%")
        #expect(presentation.remainingPercent == 94)
    }

    @Test
    func resetCountdownUsesTheDisplayedWindowAndCurrentTime() {
        let reset: Int64 = 1_800_000_000
        let snapshot = makeSnapshot(
            primary: RateLimitWindow(usedPercent: 6, windowDurationMins: 10_080, resetsAt: reset),
            secondary: RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: reset - 100_000)
        )
        let presentation = MenuPresentation(
            snapshot: snapshot, isRefreshing: false, error: nil,
            appearance: .light, language: .zhHans
        )
        let now = Date(timeIntervalSince1970: TimeInterval(reset - 6 * 86_400 - 3 * 3_600))

        #expect(presentation.resetCountdownText(at: now) == "剩余 6天 3小时")
        #expect(presentation.resetCountdownText(at: now.addingTimeInterval(3_600)) == "剩余 6天 2小时")
    }

    @Test(arguments: [AppLanguage.english, .zhHans])
    func resetCountdownFormatsShortDurationsAndNeverGoesNegative(language: AppLanguage) {
        let reset: Int64 = 1_800_000_000
        let presentation = MenuPresentation(
            snapshot: makeSnapshot(
                primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 300, resetsAt: reset),
                secondary: nil
            ),
            isRefreshing: false, error: nil, appearance: .light, language: language
        )
        let cases: [(TimeInterval, String, String)] = [
            (86_400, "Time left: 1d 0h", "剩余 1天 0小时"),
            (7_500, "Time left: 2h 5m", "剩余 2小时 5分钟"),
            (3_600, "Time left: 1h 0m", "剩余 1小时 0分钟"),
            (120, "Time left: 2m", "剩余 2分钟"),
            (60, "Time left: 1m", "剩余 1分钟"),
            (59, "Time left: <1m", "剩余不到1分钟"),
            (0, "Reset pending", "等待重置"),
            (-60, "Reset pending", "等待重置"),
        ]
        for (seconds, english, chinese) in cases {
            let now = Date(timeIntervalSince1970: TimeInterval(reset) - seconds)
            #expect(presentation.resetCountdownText(at: now) == (language == .zhHans ? chinese : english))
        }
    }

    @Test
    func resetCountdownHidesMissingResetTimesAndIgnoresRefreshTimeAndTimeZone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000 - 120)
        for snapshot in [nil, makeSnapshot(
            primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: nil),
            secondary: RateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: 1_800_000_000)
        )] {
            let presentation = MenuPresentation(
                snapshot: snapshot, isRefreshing: false, error: nil,
                appearance: .light, language: .english
            )
            #expect(presentation.resetCountdownText(at: now) == nil)
        }
        for offset in [0, 8 * 3_600, -7 * 3_600] {
            let presentation = MenuPresentation(
                snapshot: makePresentationSnapshot(usedPercent: 0, resetCount: 3),
                isRefreshing: true, error: .timeout, appearance: .dark, language: .english,
                timeZone: TimeZone(secondsFromGMT: offset)!
            )
            #expect(presentation.resetCountdownText(at: now) == "Time left: 2m")
            #expect(presentation.availableResetsText == "(3)")
        }
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
                    language == .zhHans ? "新版本" : "New Version"
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
