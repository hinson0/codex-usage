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
    public let isRefreshing: Bool
    public let error: UsageDisplayError?
    public let appearance: AppAppearance
    public let language: AppLanguage
    public let timeZone: TimeZone
    public let hasAvailableUpdate: Bool
    public let canCheckForUpdates: Bool

    public init(
        snapshot: UsageSnapshot?,
        isRefreshing: Bool,
        error: UsageDisplayError?,
        appearance: AppAppearance,
        language: AppLanguage,
        timeZone: TimeZone = .current,
        canCheckForUpdates: Bool = false,
        hasAvailableUpdate: Bool = false
    ) {
        self.snapshot = snapshot
        self.isRefreshing = isRefreshing
        self.error = error
        self.appearance = appearance
        self.language = language
        self.timeZone = timeZone
        self.hasAvailableUpdate = hasAvailableUpdate
        self.canCheckForUpdates = canCheckForUpdates
    }

    public var remainingPercent: Int? {
        let progressWindow = usageWindows.longer ?? usageWindows.fiveHour
        return UsageFormatting.remainingPercent(usedPercent: progressWindow?.usedPercent)
    }

    public var fiveHourRemainingPercent: Int? {
        UsageFormatting.remainingPercent(usedPercent: usageWindows.fiveHour?.usedPercent)
    }

    public var usagePercentText: String {
        let longerRemainingPercent = UsageFormatting.remainingPercent(
            usedPercent: usageWindows.longer?.usedPercent
        )
        let percentages = [fiveHourRemainingPercent, longerRemainingPercent]
            .compactMap { $0 }
            .map { "\($0)%" }
        return percentages.isEmpty ? "--%" : percentages.joined(separator: " - ")
    }

    public var fiveHourStatusText: String? {
        guard snapshot != nil, usageWindows.fiveHour == nil else { return nil }
        return text(.unlimited)
    }

    public var statusTitle: String {
        UsageFormatting.statusTitle(
            fiveHourRemainingPercent: fiveHourRemainingPercent,
            longerRemainingPercent: UsageFormatting.remainingPercent(
                usedPercent: usageWindows.longer?.usedPercent
            ),
            availableResets: snapshot?.availableResetCount ?? 0,
            language: language
        )
    }

    public var checkForUpdatesTitle: String {
        text(hasAvailableUpdate ? .updateAvailable : .checkForUpdates)
    }

    public var isUpdateEnabled: Bool {
        canCheckForUpdates
    }

    public var availableResetsText: String? {
        guard let count = snapshot?.availableResetCount, count > 0 else { return nil }
        let key: LocalizationKey = count == 1 ? .availableReset : .availableResets
        return LocalizationCatalog.format(key, language: language, count)
    }

    public var nextResetText: String? {
        guard let timestamp = (usageWindows.longer ?? usageWindows.fiveHour)?.resetsAt else {
            return nil
        }
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

    private var usageWindows: UsageWindowSelection {
        UsageFormatting.windows(in: snapshot?.primaryBucket)
    }
}
