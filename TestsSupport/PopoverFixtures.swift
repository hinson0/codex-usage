import AppKit
import CodexUsageCore
import SwiftUI

// Rendering never starts Sparkle or accesses a live account.
@MainActor
final class UpdateCoordinator: ObservableObject {
    let canCheckForUpdates = true
    @Published var hasAvailableUpdate = false
    var onCheckForUpdates: (() -> Void)?
    func checkForUpdateInformation() {}
    func checkForUpdates() { onCheckForUpdates?() }
}

struct RenderUsageService: UsageService {
    var requiresLogin: Bool = false
    var usedPercent: Double = 24
    var resetCount: Int = 0
    var creditExpiresAt: Int64? = nil
    var resetsAt: Int64? = Int64(Date().timeIntervalSince1970) + 6 * 86_400 + 3 * 3_600 + 300

    func readRateLimits() async throws -> UsageSnapshot {
        if requiresLogin { throw UsageServiceError.authenticationRequired }
        return UsageSnapshot(response: RateLimitsResponse(
            rateLimits: RateLimitBucket(
                limitId: "codex", limitName: nil, normalModelSlug: nil,
                primary: nil,
                secondary: RateLimitWindow(
                    usedPercent: usedPercent, windowDurationMins: 10080, resetsAt: resetsAt
                )
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(availableCount: resetCount, credits: creditExpiresAt.map {
                expiry in (0..<resetCount).map { index in
                    ResetCredit(status: "available", resetType: "codexRateLimits",
                                expiresAt: expiry - Int64(index) * 86_400)
                }
            })
        ), refreshedAt: Date())
    }
}

actor RenderNewsService: ResetNewsService {
    private var fails = false

    func setFailure(_ value: Bool) { fails = value }

    func readNews() async throws -> ResetNews {
        if fails { throw UsageServiceError.unavailable("Fixture news failure") }
        return try ResetNews.decode(Data("""
        {"events":[
          {"tool":"codex","type":"usage_reset","stage":"scheduled",
           "summary":"所有付费用户的 Codex 额度即将重置，预计北京时间 10月24日 01:00前到账。",
           "occasion":"28 天活动第 18 天","announcedAt":"2026-10-23T04:46:19Z",
           "updatedAt":"2026-10-23T04:47:34Z",
           "forecast":{"at":"2026-10-23T17:00:00Z","bound":"before"}},
          {"tool":"codex","type":"usage_reset","stage":"completed",
           "summary":"所有付费用户的 Codex 额度已重置。",
           "announcedAt":"2026-10-20T06:33:48Z","completedAt":"2026-10-20T06:33:48Z"}
        ]}
        """.utf8))
    }
}
