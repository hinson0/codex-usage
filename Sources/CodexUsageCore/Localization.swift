import Foundation

public enum LocalizationKey: String, CaseIterable, Sendable {
    case codexRemaining
    case nextReset
    case additionalLimits
    case lastRefresh
    case noResetsAvailable
    case availableResets
    case useOneReset
    case lastReset
    case noResetHistory
    case appearance
    case light
    case dark
    case language
    case simplifiedChinese
    case english
    case refreshNow
    case checkForUpdates
    case quit
    case confirmResetTitle
    case confirmResetMessage
    case confirm
    case cancel
    case resetInProgress
    case loading
    case loginRequired
    case binaryMissing
    case requestTimedOut
    case errorPrefix
    case resetSucceeded
    case resetAlreadyRedeemed
    case resetNothingToReset
    case resetNoCredit
    case resetUnknown
    case resetFailed
}

public enum LocalizationCatalog {
    private static let strings: [AppLanguage: [LocalizationKey: String]] = [
        .zhHans: [
            .codexRemaining: "Codex 剩余",
            .nextReset: "下次重置：%@",
            .additionalLimits: "其他配额",
            .lastRefresh: "最近刷新：%@",
            .noResetsAvailable: "当前没有可用 reset",
            .availableResets: "可用 reset：%d 次",
            .useOneReset: "使用 1 次 reset…",
            .lastReset: "最近一次 reset：%@",
            .noResetHistory: "尚未使用过 reset",
            .appearance: "外观",
            .light: "浅色",
            .dark: "深色",
            .language: "语言",
            .simplifiedChinese: "简体中文",
            .english: "English",
            .refreshNow: "立即刷新",
            .checkForUpdates: "检查更新…",
            .quit: "退出",
            .confirmResetTitle: "使用 Codex reset？",
            .confirmResetMessage: "这会立即消耗 1 次可用 reset，且无法撤销。",
            .confirm: "确认使用",
            .cancel: "取消",
            .resetInProgress: "正在使用 reset…",
            .loading: "正在读取 Codex 用量…",
            .loginRequired: "请先在 Codex 中登录",
            .binaryMissing: "找不到 Codex 命令行程序",
            .requestTimedOut: "请求超时，请重试",
            .errorPrefix: "错误：%@",
            .resetSucceeded: "成功",
            .resetAlreadyRedeemed: "已完成（重复请求）",
            .resetNothingToReset: "当前没有可重置的配额窗口",
            .resetNoCredit: "账户没有可用 reset",
            .resetUnknown: "未知结果：%@",
            .resetFailed: "失败：%@",
        ],
        .english: [
            .codexRemaining: "Codex remaining",
            .nextReset: "Next reset: %@",
            .additionalLimits: "Other allowances",
            .lastRefresh: "Last refreshed: %@",
            .noResetsAvailable: "No resets available",
            .availableResets: "Available resets: %d",
            .useOneReset: "Use 1 reset…",
            .lastReset: "Last reset: %@",
            .noResetHistory: "No reset has been used yet",
            .appearance: "Appearance",
            .light: "Light",
            .dark: "Dark",
            .language: "Language",
            .simplifiedChinese: "简体中文",
            .english: "English",
            .refreshNow: "Refresh Now",
            .checkForUpdates: "Check for Updates…",
            .quit: "Quit",
            .confirmResetTitle: "Use a Codex reset?",
            .confirmResetMessage: "This immediately consumes 1 available reset and cannot be undone.",
            .confirm: "Use Reset",
            .cancel: "Cancel",
            .resetInProgress: "Using reset…",
            .loading: "Loading Codex usage…",
            .loginRequired: "Sign in to Codex first",
            .binaryMissing: "Codex command-line tool not found",
            .requestTimedOut: "Request timed out. Try again.",
            .errorPrefix: "Error: %@",
            .resetSucceeded: "Successful",
            .resetAlreadyRedeemed: "Already redeemed",
            .resetNothingToReset: "Nothing to reset",
            .resetNoCredit: "No reset credit available",
            .resetUnknown: "Unknown result: %@",
            .resetFailed: "Failed: %@",
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

    public static func resetOutcome(_ outcome: ResetOutcome, language: AppLanguage) -> String {
        switch outcome {
        case .reset:
            return string(.resetSucceeded, language: language)
        case .alreadyRedeemed:
            return string(.resetAlreadyRedeemed, language: language)
        case .nothingToReset:
            return string(.resetNothingToReset, language: language)
        case .noCredit:
            return string(.resetNoCredit, language: language)
        case .unknown(let raw):
            return format(.resetUnknown, language: language, raw)
        }
    }
}
