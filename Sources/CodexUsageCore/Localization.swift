import Foundation

public enum LocalizationKey: String, CaseIterable, Sendable {
    case codexRemaining
    case fiveHourRemaining
    case unlimited
    case nextReset
    case additionalLimits
    case lastRefresh
    case availableReset
    case availableResets
    case appearance
    case light
    case dark
    case language
    case simplifiedChinese
    case english
    case refreshNow
    case updateAvailable
    case checkForUpdates
    case quit
    case loading
    case loginRequired
    case binaryMissing
    case requestTimedOut
    case errorPrefix
}

public enum LocalizationCatalog {
    private static let strings: [AppLanguage: [LocalizationKey: String]] = [
        .zhHans: [
            .codexRemaining: "Codex 剩余",
            .fiveHourRemaining: "5 小时剩余",
            .unlimited: "无限制",
            .nextReset: "下次重置：%@",
            .additionalLimits: "其他配额",
            .lastRefresh: "最近刷新：%@",
            .availableReset: "%d 次 reset",
            .availableResets: "%d 次 reset",
            .appearance: "外观",
            .light: "浅色",
            .dark: "深色",
            .language: "语言",
            .simplifiedChinese: "简体中文",
            .english: "English",
            .refreshNow: "立即刷新",
            .checkForUpdates: "检查更新…",
            .updateAvailable: "新版本",
            .quit: "退出",
            .loading: "正在读取 Codex 用量…",
            .loginRequired: "请先在 Codex 中登录",
            .binaryMissing: "找不到 Codex 命令行程序",
            .requestTimedOut: "请求超时，请重试",
            .errorPrefix: "错误：%@",
        ],
        .english: [
            .codexRemaining: "Codex remaining",
            .fiveHourRemaining: "5-hour remaining",
            .unlimited: "Unlimited",
            .nextReset: "Next reset: %@",
            .additionalLimits: "Other allowances",
            .lastRefresh: "Last refreshed: %@",
            .availableReset: "%d reset",
            .availableResets: "%d resets",
            .appearance: "Appearance",
            .light: "Light",
            .dark: "Dark",
            .language: "Language",
            .simplifiedChinese: "简体中文",
            .english: "English",
            .refreshNow: "Refresh Now",
            .checkForUpdates: "Check for Updates…",
            .updateAvailable: "New Version",
            .quit: "Quit",
            .loading: "Loading Codex usage…",
            .loginRequired: "Sign in to Codex first",
            .binaryMissing: "Codex command-line tool not found",
            .requestTimedOut: "Request timed out. Try again.",
            .errorPrefix: "Error: %@",
        ],
    ]

    public static func keys(for language: AppLanguage) -> Set<LocalizationKey> {
        Set(strings[language.resolved()]?.keys ?? Dictionary<LocalizationKey, String>().keys)
    }

    public static func string(
        _ key: LocalizationKey,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let resolved = language.resolved(preferredLanguages: preferredLanguages)
        return strings[resolved]?[key] ?? strings[.english]?[key] ?? key.rawValue
    }

    public static func format(
        _ key: LocalizationKey,
        language: AppLanguage,
        _ arguments: CVarArg...
    ) -> String {
        String(format: string(key, language: language), arguments: arguments)
    }

    public static func dateTime(
        _ date: Date,
        language: AppLanguage,
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.resolved() == .zhHans ? "zh_Hans_CN" : "en_US")
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

}
