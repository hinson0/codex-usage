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
    func authenticationLossClearsUsageAndRefreshRecoversAfterLogin() async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 2))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        await controller.refresh()
        #expect(controller.snapshot != nil)

        await service.setError(.timeout)
        await controller.refresh()
        #expect(controller.snapshot != nil)
        #expect(controller.displayError == .timeout)

        await service.setError(.authenticationRequired)
        await controller.refresh()
        #expect(controller.snapshot == nil)
        #expect(controller.displayError == .authenticationRequired)
        #expect(!controller.isRefreshing)

        await service.setError(nil)
        await controller.refresh()
        #expect(controller.snapshot != nil)
        #expect(controller.displayError == nil)
    }

    @Test(arguments: [20, 90, 89.9, nil, .nan, .infinity, -.infinity] as [Double?])
    @MainActor
    func automaticRefreshReadsImmediatelyThenWaitsFiveMinutesWhenAllowanceIsNotLow(
        usedPercent: Double?
    ) async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0, usedPercent: usedPercent))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        var waits: [Duration] = []

        await controller.monitorUsage { duration in
            #expect(await service.readCallCount == waits.count + 1)
            waits.append(duration)
            if waits.count == 2 { throw CancellationError() }
        }

        #expect(waits == [.seconds(300), .seconds(300)])
        #expect(await service.readCallCount == 2)
        #expect(!controller.isRefreshing)
    }

    @Test(arguments: [90.1, 100, 120])
    @MainActor
    func automaticRefreshUsesTwoMinutesWhenLongerWindowHasLessThanTenPercentRemaining(
        usedPercent: Double
    ) async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0, usedPercent: usedPercent))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        var waits: [Duration] = []

        await controller.monitorUsage { duration in
            waits.append(duration)
            throw CancellationError()
        }

        #expect(waits == [.seconds(120)])
        #expect(await service.readCallCount == 1)
    }

    @Test
    @MainActor
    func automaticRefreshUsesTwoMinutesWhenFiveHourWindowIsLow() async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0, fiveHourUsedPercent: 95))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        var waits: [Duration] = []

        await controller.monitorUsage { duration in
            waits.append(duration)
            throw CancellationError()
        }

        #expect(waits == [.seconds(120)])
        #expect(await service.readCallCount == 1)
    }

    @Test
    @MainActor
    func automaticRefreshReevaluatesIntervalWhenAllowanceFallsAndRecovers() async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        var waits: [Duration] = []

        await controller.monitorUsage { duration in
            waits.append(duration)
            switch waits.count {
            case 1:
                await service.setSnapshot(makeSnapshot(resetCount: 0, usedPercent: 95))
            case 2:
                await service.setSnapshot(makeSnapshot(resetCount: 0, usedPercent: 90))
            default:
                throw CancellationError()
            }
        }

        #expect(waits == [.seconds(300), .seconds(120), .seconds(300)])
        #expect(await service.readCallCount == 3)
    }

    @Test
    @MainActor
    func automaticRefreshIgnoresLowAuxiliaryAllowance() async {
        let auxiliary = RateLimitBucket(
            limitId: "gpt-reserve", limitName: nil, normalModelSlug: nil,
            primary: RateLimitWindow(usedPercent: 100, windowDurationMins: 10_080, resetsAt: 999),
            secondary: nil
        )
        let snapshot = UsageSnapshot(response: RateLimitsResponse(
            rateLimits: auxiliary,
            rateLimitsByLimitId: ["codex": makeSnapshot(resetCount: 0).primaryBucket!, "gpt-reserve": auxiliary],
            rateLimitResetCredits: nil
        ), refreshedAt: .distantPast)
        let service = FakeUsageService(snapshot: snapshot)
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)
        var waits: [Duration] = []

        await controller.monitorUsage { duration in
            waits.append(duration)
            throw CancellationError()
        }

        #expect(waits == [.seconds(300)])
    }

    @Test
    @MainActor
    func automaticRefreshStopsWhenCancelledDuringWait() async {
        let service = FakeUsageService(snapshot: makeSnapshot(resetCount: 0))
        let context = makeStore()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let controller = UsageController(service: service, preferences: context.store)

        let monitoring = Task {
            await controller.monitorUsage { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await monitoring.value

        #expect(await service.readCallCount == 1)
        #expect(!controller.isRefreshing)
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
        #expect(controller.statusTitle == "80%")
    }
}

private actor FakeUsageService: UsageService {
    private var snapshot: UsageSnapshot
    private let readDelay: Duration
    private(set) var readCallCount = 0
    private var error: UsageServiceError?

    func setError(_ value: UsageServiceError?) { error = value }
    func setSnapshot(_ value: UsageSnapshot) { snapshot = value }

    init(snapshot: UsageSnapshot, readDelay: Duration = .zero) {
        self.snapshot = snapshot
        self.readDelay = readDelay
    }

    func readRateLimits() async throws -> UsageSnapshot {
        readCallCount += 1
        if let error { throw error }
        if readDelay > .zero {
            try await Task.sleep(for: readDelay)
        }
        return snapshot
    }
}

private func makeSnapshot(
    resetCount: Int,
    usedPercent: Double? = 20,
    fiveHourUsedPercent: Double? = nil
) -> UsageSnapshot {
    let response = RateLimitsResponse(
        rateLimits: RateLimitBucket(
            limitId: "codex",
            limitName: nil,
            normalModelSlug: nil,
            primary: RateLimitWindow(usedPercent: usedPercent, windowDurationMins: 10_080, resetsAt: 999),
            secondary: fiveHourUsedPercent.map {
                RateLimitWindow(usedPercent: $0, windowDurationMins: 300, resetsAt: 999)
            }
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
