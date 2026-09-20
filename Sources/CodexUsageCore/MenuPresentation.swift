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
    public let errorMessage: String?
    public let appearance: AppAppearance
    public let language: AppLanguage
    public let timeZone: TimeZone

    public init(
        snapshot: UsageSnapshot?,
        lastReset: LastResetRecord?,
        isRefreshing: Bool,
        isRedeeming: Bool,
        errorMessage: String?,
        appearance: AppAppearance,
        language: AppLanguage,
        timeZone: TimeZone = .current
    ) {
        self.snapshot = snapshot
        self.lastReset = lastReset
        self.isRefreshing = isRefreshing
        self.isRedeeming = isRedeeming
        self.errorMessage = errorMessage
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
        case .failure(let message):
            result = LocalizationCatalog.format(.resetFailed, language: language, message)
        }
        let date = LocalizationCatalog.dateTime(
            lastReset.attemptedAt,
            language: language,
            timeZone: timeZone
        )
        return LocalizationCatalog.format(.lastReset, language: language, "\(date) · \(result)")
    }

    public var errorText: String? {
        errorMessage.map { LocalizationCatalog.format(.errorPrefix, language: language, $0) }
    }

    public var appearanceOptions: [MenuOption<AppAppearance>] {
        [
            option(.system, key: .followSystem),
            option(.light, key: .light),
            option(.dark, key: .dark),
        ]
    }

    public var languageOptions: [MenuOption<AppLanguage>] {
        [
            languageOption(.system, key: .followSystem),
            languageOption(.zhHans, key: .simplifiedChinese),
            languageOption(.english, key: .english),
        ]
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
}
