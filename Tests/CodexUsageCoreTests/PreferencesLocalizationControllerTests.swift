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
        #expect(LocalizationCatalog.string(.noResetsAvailable, language: .zhHans) == "当前没有可用 reset")
        #expect(LocalizationCatalog.string(.noResetsAvailable, language: .english) == "No resets available")
    }

    @Test
    func localizationCatalogFormatsDatesAndResetOutcomes() {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let zone = TimeZone(secondsFromGMT: 8 * 3_600)!

        let chinese = LocalizationCatalog.dateTime(date, language: .zhHans, timeZone: zone)
        let english = LocalizationCatalog.dateTime(date, language: .english, timeZone: zone)

        #expect(chinese != english)
        #expect(LocalizationCatalog.resetOutcome(.reset, language: .zhHans) == "成功")
        #expect(LocalizationCatalog.resetOutcome(.alreadyRedeemed, language: .english) == "Already redeemed")
        #expect(LocalizationCatalog.resetOutcome(.unknown("future"), language: .english) == "Unknown result: future")
    }

    @Test
    func preferencesPersistAtMostThreeResetRecordsNewestFirst() throws {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")
        let records = (1...4).map { index in
            LastResetRecord(
                attemptedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                result: .outcome(.reset)
            )
        }

        store.appearance = .dark
        store.language = .english
        for record in records {
            try store.saveLastReset(record)
        }

        let reloaded = PreferencesStore(defaults: context.defaults, keyPrefix: "test")
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.language == .english)
        #expect(reloaded.resetHistory.map(\.attemptedAt) == [
            Date(timeIntervalSince1970: 4),
            Date(timeIntervalSince1970: 3),
            Date(timeIntervalSince1970: 2),
        ])
        #expect(reloaded.lastReset == records[3])
    }

    @Test
    func preferencesMigratesLegacySingleResetRecordIntoHistory() throws {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        let legacyRecord = LastResetRecord(
            attemptedAt: Date(timeIntervalSince1970: 123),
            result: .outcome(.alreadyRedeemed)
        )
        context.defaults.set(
            try JSONEncoder().encode(legacyRecord),
            forKey: "test.lastReset"
        )

        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(store.resetHistory == [legacyRecord])
        #expect(store.lastReset == legacyRecord)
    }

    @Test
    func preferencesFallBackSafelyFromInvalidStoredData() {
        let context = makeDefaults()
        defer { context.defaults.removePersistentDomain(forName: context.name) }
        context.defaults.set("neon", forKey: "test.appearance")
        context.defaults.set("klingon", forKey: "test.language")
        context.defaults.set(Data("invalid".utf8), forKey: "test.lastReset")

        let store = PreferencesStore(defaults: context.defaults, keyPrefix: "test")

        #expect(store.appearance == .light)
        #expect(store.language == .english)
        #expect(store.resetHistory.isEmpty)
        #expect(store.lastReset == nil)
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
    }

    @Test
    @MainActor
    func resetRetryReusesIdempotencyKeyAndPersistsResult() async {
        let context = makeStore()
        let service = FakeUsageService(
            snapshot: makeSnapshot(resetCount: 1),
            consumeSteps: [.failure(.timeout), .outcome(.reset)]
        )
        let controller = UsageController(
            service: service,
            preferences: context.store,
            uuid: { UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")! },
            now: { Date(timeIntervalSince1970: 456) }
        )

        await controller.refresh()
        let outcome = await controller.redeemReset()

        let calls = await service.consumeCalls
        #expect(outcome == .reset)
        #expect(calls.count == 2)
        #expect(calls[0].idempotencyKey == calls[1].idempotencyKey)
        #expect(calls[0].idempotencyKey == "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")
        #expect(controller.lastReset == LastResetRecord(
            attemptedAt: Date(timeIntervalSince1970: 456),
            result: .outcome(.reset)
        ))
        #expect(controller.resetHistory == [LastResetRecord(
            attemptedAt: Date(timeIntervalSince1970: 456),
            result: .outcome(.reset)
        )])
        context.defaults.removePersistentDomain(forName: context.name)
    }

    @Test
    @MainActor
    func resetDoesNotRetryProtocolFailure() async {
        let context = makeStore()
        let service = FakeUsageService(
            snapshot: makeSnapshot(resetCount: 1),
            consumeSteps: [.failure(.protocolError("denied"))]
        )
        let controller = UsageController(service: service, preferences: context.store)

        await controller.refresh()
        let outcome = await controller.redeemReset()

        #expect(outcome == nil)
        #expect(await service.consumeCalls.count == 1)
        if case .failure(.message(let message)) = controller.lastReset?.result {
            #expect(message.contains("denied"))
        } else {
            Issue.record("Expected a persisted failure result")
        }
        context.defaults.removePersistentDomain(forName: context.name)
    }
}

private actor FakeUsageService: UsageService {
    struct ConsumeCall: Sendable {
        let idempotencyKey: String
        let creditId: String?
    }

    enum ConsumeStep: Sendable {
        case outcome(ResetOutcome)
        case failure(UsageServiceError)
    }

    private let snapshot: UsageSnapshot
    private let readDelay: Duration
    private var consumeSteps: [ConsumeStep]
    private(set) var readCallCount = 0
    private(set) var consumeCalls: [ConsumeCall] = []

    init(
        snapshot: UsageSnapshot,
        readDelay: Duration = .zero,
        consumeSteps: [ConsumeStep] = []
    ) {
        self.snapshot = snapshot
        self.readDelay = readDelay
        self.consumeSteps = consumeSteps
    }

    func readRateLimits() async throws -> UsageSnapshot {
        readCallCount += 1
        if readDelay > .zero {
            try await Task.sleep(for: readDelay)
        }
        return snapshot
    }

    func consumeReset(idempotencyKey: String, creditId: String?) async throws -> ResetOutcome {
        consumeCalls.append(ConsumeCall(idempotencyKey: idempotencyKey, creditId: creditId))
        guard !consumeSteps.isEmpty else { return .noCredit }
        switch consumeSteps.removeFirst() {
        case .outcome(let outcome): return outcome
        case .failure(let error): throw error
        }
    }
}

private func makeSnapshot(resetCount: Int) -> UsageSnapshot {
    let credit = ResetCredit(id: "credit-1", status: "available")
    let response = RateLimitsResponse(
        rateLimits: RateLimitBucket(
            limitId: "codex",
            limitName: nil,
            normalModelSlug: nil,
            primary: RateLimitWindow(usedPercent: 20, windowDurationMins: 60, resetsAt: 999),
            secondary: nil
        ),
        rateLimitsByLimitId: nil,
        rateLimitResetCredits: ResetCreditsSummary(
            availableCount: resetCount,
            credits: resetCount > 0 ? [credit] : []
        )
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
