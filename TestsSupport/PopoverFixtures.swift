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
    func readRateLimits() async throws -> UsageSnapshot {
        UsageSnapshot(response: RateLimitsResponse(
            rateLimits: RateLimitBucket(
                limitId: "codex", limitName: nil, normalModelSlug: nil,
                primary: nil,
                secondary: RateLimitWindow(
                    usedPercent: 24, windowDurationMins: 10080, resetsAt: 1790502240
                )
            ),
            rateLimitsByLimitId: nil,
            rateLimitResetCredits: ResetCreditsSummary(availableCount: 0)
        ), refreshedAt: Date())
    }
}
