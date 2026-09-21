import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system
    case zhHans
    case english

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard self == .system else { return self }
        guard let first = preferredLanguages.first?.lowercased() else { return .english }
        return first.hasPrefix("zh") ? .zhHans : .english
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var nativeAppearancePolicy: NativeAppearancePolicy {
        switch self {
        case .system, .light:
            NativeAppearancePolicy(
                applicationName: nil,
                popoverName: "NSAppearanceNameAqua",
                backgroundStyle: .opaqueWhite
            )
        case .dark:
            NativeAppearancePolicy(
                applicationName: nil,
                popoverName: "NSAppearanceNameDarkAqua",
                backgroundStyle: .opaqueWindow
            )
        }
    }
}

public enum PopoverBackgroundStyle: Equatable, Sendable {
    case opaqueWhite
    case opaqueWindow
}

public struct NativeAppearancePolicy: Equatable, Sendable {
    public let applicationName: String?
    public let popoverName: String
    public let backgroundStyle: PopoverBackgroundStyle

    public init(
        applicationName: String?,
        popoverName: String,
        backgroundStyle: PopoverBackgroundStyle
    ) {
        self.applicationName = applicationName
        self.popoverName = popoverName
        self.backgroundStyle = backgroundStyle
    }
}

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Int64?

    public init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Int64?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }
}

public struct CreditsSnapshot: Codable, Equatable, Sendable {
    public let hasCredits: Bool?
    public let unlimited: Bool?
    public let balance: String?

    public init(hasCredits: Bool?, unlimited: Bool?, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}

public struct RateLimitBucket: Codable, Equatable, Sendable {
    public let limitId: String
    public let limitName: String?
    public let normalModelSlug: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let credits: CreditsSnapshot?
    public let planType: String?
    public let rateLimitReachedType: String?

    public init(
        limitId: String,
        limitName: String?,
        normalModelSlug: String?,
        primary: RateLimitWindow?,
        secondary: RateLimitWindow?,
        credits: CreditsSnapshot? = nil,
        planType: String? = nil,
        rateLimitReachedType: String? = nil
    ) {
        self.limitId = limitId
        self.limitName = limitName
        self.normalModelSlug = normalModelSlug
        self.primary = primary
        self.secondary = secondary
        self.credits = credits
        self.planType = planType
        self.rateLimitReachedType = rateLimitReachedType
    }
}

public struct ResetCreditsSummary: Codable, Equatable, Sendable {
    public let availableCount: Int

    public init(availableCount: Int) {
        self.availableCount = availableCount
    }
}

public struct RateLimitsResponse: Codable, Equatable, Sendable {
    public let ordinaryUsageAllowed: Bool?
    public let rateLimits: RateLimitBucket?
    public let rateLimitsByLimitId: [String: RateLimitBucket]?
    public let rateLimitResetCredits: ResetCreditsSummary?

    public init(
        ordinaryUsageAllowed: Bool? = nil,
        rateLimits: RateLimitBucket?,
        rateLimitsByLimitId: [String: RateLimitBucket]?,
        rateLimitResetCredits: ResetCreditsSummary?
    ) {
        self.ordinaryUsageAllowed = ordinaryUsageAllowed
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let primaryBucket: RateLimitBucket?
    public let additionalBuckets: [RateLimitBucket]
    public let availableResetCount: Int
    public let refreshedAt: Date

    public init(response: RateLimitsResponse, refreshedAt: Date) {
        let buckets = response.rateLimitsByLimitId ?? [:]
        primaryBucket = buckets["codex"] ?? response.rateLimits
        additionalBuckets = buckets
            .filter { $0.key != "codex" }
            .map(\.value)
            .sorted { $0.limitId < $1.limitId }
        availableResetCount = max(0, response.rateLimitResetCredits?.availableCount ?? 0)
        self.refreshedAt = refreshedAt
    }
}
