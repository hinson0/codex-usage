import AppKit
import CodexUsageCore
import SwiftUI

// Rendering never starts Sparkle or accesses a live account.
@MainActor
final class UpdateCoordinator: ObservableObject {
    let canCheckForUpdates = true
    let hasAvailableUpdate = false
    func checkForUpdateInformation() {}
    func checkForUpdates() {}
}

struct RenderUsageService: UsageService {
    var usedPercent: Double = 24
    var resetCount: Int = 0
    var resetsAt: Int64 = Int64(Date().timeIntervalSince1970) + 6 * 86_400 + 3 * 3_600 + 300

    func readRateLimits() async throws -> UsageSnapshot {
        UsageSnapshot(response: RateLimitsResponse(
            rateLimits: RateLimitBucket(
                limitId: "codex", limitName: nil, normalModelSlug: nil,
                primary: nil,
                secondary: RateLimitWindow(
                    usedPercent: usedPercent, windowDurationMins: 10080, resetsAt: resetsAt
                )
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(availableCount: resetCount)
        ), refreshedAt: Date())
    }
}
