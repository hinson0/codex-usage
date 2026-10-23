import AppKit
import CodexUsageCore
import SwiftUI

// Rendering never starts Sparkle or accesses a live account.
@MainActor
final class UpdateCoordinator: ObservableObject {
    let canCheckForUpdates = true
    @Published var hasAvailableUpdate = false
    func checkForUpdateInformation() {}
    func checkForUpdates() {}
}

struct RenderUsageService: UsageService {
    var requiresLogin: Bool = false
    var usedPercent: Double = 24
    var resetCount: Int = 0
    var creditExpiresAt: Int64? = nil
    var resetsAt: Int64 = Int64(Date().timeIntervalSince1970) + 6 * 86_400 + 3 * 3_600 + 300

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
                [ResetCredit(status: "available", resetType: "codexRateLimits", expiresAt: $0)]
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
        [{"tool":"codex","eventType":"额度重置","eventStatus":"completed","sortTime":"2026-10-20T06:33:48Z"},
         {"tool":"codex","eventType":"额度重置","eventStatus":"scheduled","sortTime":"2026-10-22T06:55:54Z",
          "forecast":{"at":"2026-10-22T18:00:00Z","deadline":true}}]
        """.utf8))
    }
}
