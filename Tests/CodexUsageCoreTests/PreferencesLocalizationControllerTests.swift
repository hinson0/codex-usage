import Foundation
import Testing
@testable import CodexUsageCore

@Suite(.serialized)
struct PreferencesLocalizationControllerTests {
    @Test
    func systemLanguageMapsEveryChineseLocaleToSimplifiedChinese() {
        #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hans-CN"]) == .zhHans)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["zh-Hant-TW"]) == .zhHans)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguage.system.resolved(preferredLanguages: ["ja-JP"]) == .english)
        #expect(AppLanguage.system.resolved(preferredLanguages: []) == .english)
    }

    @Test
    func localizationCatalogHasMatchingEnglishAndChineseKeys() {
        #expect(LocalizationCatalog.keys(for: .zhHans) == LocalizationCatalog.keys(for: .english))
        #expect(LocalizationCatalog.string(.fiveHourRemaining, language: .zhHans) == "5 小时剩余")
        #expect(LocalizationCatalog.string(.unlimited, language: .english) == "Unlimited")
        #expect(LocalizationCatalog.string(.checkForUpdates, language: .zhHans) == "检查更新…")
        #expect(LocalizationCatalog.string(.checkForUpdates, language: .english) == "Check for Updates…")
    }

    @Test
    func localizationCatalogFormatsDatesForTheSelectedLanguage() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let zone = TimeZone(secondsFromGMT: 8 * 3_600)!

        let chinese = LocalizationCatalog.dateTime(date, language: .zhHans, timeZone: zone)
        let english = LocalizationCatalog.dateTime(date, language: .english, timeZone: zone)

        #expect(chinese != english)
    }

    @Test
    func preferencesPersistAppearanceAndLanguageOnly() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        store.appearance = .dark
        store.language = .english

        let reloaded = PreferencesStore(defaults: context.defaults, keyPrefix: "test")
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.language == .english)
    }

    @Test
    func preferencesRemoveLegacyResetHistoryOnInitialization() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        context.defaults.set(Data("legacy-reset-history".utf8), forKey: "test.lastReset")

        _ = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(context.defaults.object(forKey: "test.lastReset") == nil)
    }

    @Test
    func preferencesFallBackSafelyFromInvalidStoredSelections() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        context.defaults.set("neon", forKey: "test.appearance")
        context.defaults.set("klingon", forKey: "test.language")

        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(store.appearance == .light)
        #expect(store.language == .english)
    }

    @Test
    func legacySystemSelectionsMigrateToLightAndEnglish() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        context.defaults.set(AppAppearance.system.rawValue, forKey: "test.appearance")
        context.defaults.set(AppLanguage.system.rawValue, forKey: "test.language")

        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(store.appearance == .light)
        #expect(store.language == .english)
    }

    @Test
    func freshPreferencesDefaultToLightAndEnglish() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }

        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(store.appearance == .light)
        #expect(store.language == .english)
    }

    @Test
    @MainActor
    func controllerSerializesOverlappingRefreshes() async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0), readDelay: .milliseconds(80))
        let controller = UsageController(service: service, preferences: makeStore().store)

        let first = Task { await controller.refresh() }
        await Task.yield()
        await controller.refresh()
        await first.value

        #expect(await service.readCallCount == 1)
        #expect(controller.snapshot?.availableResetCount == 0)
        #expect(controller.statusTitle == "Codex 80%")
    }
}

private actor FakeUsageService: UsageService {
    private let snapshot: UsageSnapshot
    private let readDelay: Duration
    private(set) var readCallCount = 0

    init(snapshot: UsageSnapshot, readDelay: Duration = .zero) {
        self.snapshot = snapshot
        self.readDelay = readDelay
    }

    func readRateLimits() async throws -> UsageSnapshot {
        readCallCount += 1
        if readDelay > .zero {
            try await Task.sleep(for: readDelay)
        }
        return snapshot
    }
}

private func makeSnapshot(resetCount: Int) -> UsageSnapshot {
    let response = RateLimitsResponse(
        rateLimits: RateLimitBucket(
            limitId: "codex",
            limitName: nil,
            normalModelSlug: nil,
            primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 10_080, resetsAt: 999),
            secondary: nil
        ),
        rateLimitsByLimitId: nil,
        rateLimitResetCredits: ResetCreditsSummary(availableCount: resetCount)
    )
    return UsageSnapshot(response: response, refreshedAt: Date(timeIntervalSince1970: 1))
}

private func makeDefaults() -> (defaults: UserDefaults, name: String) {
    let name = "CodexUsageTests.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

private func makeStore() -> (store: PreferencesStore, defaults: UserDefaults, name: String) {
    let context = makeDefaults()
    return (
        PreferencesStore(defaults: context.defaults, keyPrefix: "test"),
        context.defaults,
        context.name
    )
}
