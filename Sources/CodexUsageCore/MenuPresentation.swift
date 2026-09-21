import Foundation

public struct MenuOption<Value: Equatable & Sendable>: Equatable, Sendable {
    public let value: Value
    public let title: String
    public let isSelected: Bool

    public init(value: Value, title: String, isSelected: Bool) {
        self.value = value
        self.title = title
        self.isSelected = isSelected
    }
}

public struct MenuPresentation: Sendable {
    public let snapshot: UsageSnapshot?
    public let lastReset: LastResetRecord?
    public let isRefreshing: Bool
    public let isRedeeming: Bool
    public let error: UsageDisplayError?
    public let appearance: AppAppearance
    public let language: AppLanguage
    public let timeZone: TimeZone

    public init(
        snapshot: UsageSnapshot?,
        lastReset: LastResetRecord?,
        isRefreshing: Bool,
        isRedeeming: Bool,
        error: UsageDisplayError?,
        appearance: AppAppearance,
        language: AppLanguage,
        timeZone: TimeZone = .current
    ) {
        self.snapshot = snapshot
        self.lastReset = lastReset
        self.isRefreshing = isRefreshing
        self.isRedeeming = isRedeeming
        self.error = error
        self.appearance = appearance
        self.language = language
        self.timeZone = timeZone
    }

    public var remainingPercent: Int? {
        UsageFormatting.remainingPercent(usedPercent: snapshot?.primaryBucket?.primary?.usedPercent)
    }

    public var statusTitle: String {
        UsageFormatting.statusTitle(
            remainingPercent: remainingPercent,
            availableResets: snapshot?.availableResetCount ?? 0,
            language: language
        )
    }

    public var resetActionTitle: String {
        if isRedeeming {
            return text(.resetInProgress)
        }
        return snapshot?.availableResetCount ?? 0 > 0
            ? text(.useOneReset)
            : text(.noResetsAvailable)
    }

    public var isResetEnabled: Bool {
        (snapshot?.availableResetCount ?? 0) > 0 && !isRedeeming
    }

    public var availableResetsText: String? {
        guard let count = snapshot?.availableResetCount, count > 0 else { return nil }
        return LocalizationCatalog.format(.availableResets, language: language, count)
    }

    public var nextResetText: String? {
        guard let timestamp = snapshot?.primaryBucket?.primary?.resetsAt else { return nil }
        let date = LocalizationCatalog.dateTime(
            Date(timeIntervalSince1970: TimeInterval(timestamp)),
            language: language,
            timeZone: timeZone
        )
        return LocalizationCatalog.format(.nextReset, language: language, date)
    }

    public var lastRefreshText: String? {
        guard let refreshedAt = snapshot?.refreshedAt else { return nil }
        let date = LocalizationCatalog.dateTime(refreshedAt, language: language, timeZone: timeZone)
        return LocalizationCatalog.format(.lastRefresh, language: language, date)
    }

    public var lastResetText: String {
        guard let lastReset else { return text(.noResetHistory) }
        let result: String
        switch lastReset.result {
        case .outcome(let outcome):
            result = LocalizationCatalog.resetOutcome(outcome, language: language)
        case .failure(let error):
            result = LocalizationCatalog.format(
                .resetFailed,
                language: language,
                localizedError(error)
            )
        }
        let date = LocalizationCatalog.dateTime(
            lastReset.attemptedAt,
            language: language,
            timeZone: timeZone
        )
        return LocalizationCatalog.format(.lastReset, language: language, "\(date) · \(result)")
    }

    public var errorText: String? {
        error.map(localizedError)
    }

    public var appearanceOptions: [MenuOption<AppAppearance>] {
        [
            option(.light, key: .light),
            option(.dark, key: .dark),
        ]
    }

    public var languageOptions: [MenuOption<AppLanguage>] {
        [
            languageOption(.zhHans, key: .simplifiedChinese),
            languageOption(.english, key: .english),
        ]
    }

    public var displayedAdditionalBuckets: [RateLimitBucket] {
        []
    }

    public var appearanceSummary: String {
        let selected = appearanceOptions.first(where: \.isSelected)?.title ?? text(.light)
        return "\(text(.appearance)) · \(selected)"
    }

    public var languageSummary: String {
        let selected = languageOptions.first(where: \.isSelected)?.title ?? text(.english)
        return "\(text(.language)) · \(selected)"
    }

    public func text(_ key: LocalizationKey) -> String {
        LocalizationCatalog.string(key, language: language)
    }

    private func option(_ value: AppAppearance, key: LocalizationKey) -> MenuOption<AppAppearance> {
        MenuOption(value: value, title: text(key), isSelected: appearance == value)
    }

    private func languageOption(_ value: AppLanguage, key: LocalizationKey) -> MenuOption<AppLanguage> {
        MenuOption(value: value, title: text(key), isSelected: language == value)
    }

    private func localizedError(_ error: UsageDisplayError) -> String {
        switch error {
        case .authenticationRequired: text(.loginRequired)
        case .binaryMissing: text(.binaryMissing)
        case .timeout: text(.requestTimedOut)
        case .message(let message): LocalizationCatalog.format(.errorPrefix, language: language, message)
        }
    }
}
