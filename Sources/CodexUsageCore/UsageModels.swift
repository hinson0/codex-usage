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

    public var nativeAppearanceName: String? {
        switch self {
        case .system: nil
        case .light: "NSAppearanceNameAqua"
        case .dark: "NSAppearanceNameDarkAqua"
        }
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

public struct ResetCredit: Codable, Equatable, Sendable {
    public let id: String
    public let resetType: String?
    public let status: String?
    public let grantedAt: Int64?
    public let expiresAt: Int64?
    public let title: String?
    public let description: String?

    public init(
        id: String,
        resetType: String? = nil,
        status: String? = nil,
        grantedAt: Int64? = nil,
        expiresAt: Int64? = nil,
        title: String? = nil,
        description: String? = nil
    ) {
        self.id = id
        self.resetType = resetType
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
        self.description = description
    }
}

public struct ResetCreditsSummary: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let credits: [ResetCredit]?

    public init(availableCount: Int, credits: [ResetCredit]?) {
        self.availableCount = availableCount
        self.credits = credits
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
    public let resetCredits: [ResetCredit]
    public let refreshedAt: Date

    public init(response: RateLimitsResponse, refreshedAt: Date) {
        let buckets = response.rateLimitsByLimitId ?? [:]
        primaryBucket = buckets["codex"] ?? response.rateLimits
        additionalBuckets = buckets
            .filter { $0.key != "codex" }
            .map(\.value)
            .sorted { $0.limitId < $1.limitId }
        availableResetCount = max(0, response.rateLimitResetCredits?.availableCount ?? 0)
        resetCredits = response.rateLimitResetCredits?.credits ?? []
        self.refreshedAt = refreshedAt
    }

    public var firstAvailableResetCreditId: String? {
        resetCredits.first(where: { $0.status == nil || $0.status == "available" })?.id
    }
}

public enum ResetOutcome: Equatable, Sendable, Codable {
    case reset
    case alreadyRedeemed
    case nothingToReset
    case noCredit
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "reset": self = .reset
        case "alreadyRedeemed": self = .alreadyRedeemed
        case "nothingToReset": self = .nothingToReset
        case "noCredit": self = .noCredit
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .reset: try container.encode("reset")
        case .alreadyRedeemed: try container.encode("alreadyRedeemed")
        case .nothingToReset: try container.encode("nothingToReset")
        case .noCredit: try container.encode("noCredit")
        case .unknown(let raw): try container.encode(raw)
        }
    }
}

public struct ConsumeResetResponse: Codable, Equatable, Sendable {
    public let outcome: ResetOutcome

    public init(outcome: ResetOutcome) {
        self.outcome = outcome
    }
}
