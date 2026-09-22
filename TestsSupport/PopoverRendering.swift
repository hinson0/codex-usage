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

@main
struct PopoverRendering {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        var failures: [String] = []
        let output = CommandLine.arguments[1]
        for (appearance, language) in [
            (AppAppearance.light, AppLanguage.zhHans),
            (.dark, .english),
        ] {
            let suite = "PopoverRendering.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let controller = UsageController(
                service: RenderUsageService(), preferences: PreferencesStore(defaults: defaults)
            )
            controller.setAppearance(appearance)
            controller.setLanguage(language)
            await controller.refresh()
            let host = NSHostingView(rootView: UsagePopoverView(
                controller: controller, updater: UpdateCoordinator()
            ))
            let size = host.fittingSize
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            window.contentView = host
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let label = "\(appearance.rawValue)-\(language.rawValue)"
            try bitmap.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(output)/\(label).png"))
            for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0),
                           (0, bitmap.pixelsHigh - 1),
                           (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
                if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 {
                    failures.append("\(label): corner (\(x), \(y)) must be transparent")
                }
            }
            if bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 8)!.alphaComponent < 0.99 {
                failures.append("\(label): interior background must remain opaque")
            }
            if size.height > 315 {
                failures.append("\(label): excessive empty space, height \(size.height) > 315")
            }
            if window.isOpaque || window.backgroundColor != .clear {
                failures.append("\(label): window background fills the rounded corners")
            }
            print("Rendered \(label): \(size)")
        }
        for failure in failures { print("FAIL: \(failure)") }
        if !failures.isEmpty { exit(1) }
        print("Popover rendering checks passed")
    }
}
