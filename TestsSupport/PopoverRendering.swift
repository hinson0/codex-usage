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
                if bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.99 {
                    failures.append("\(label): content must remain opaque underneath the window mask")
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
            // The system frame can paint material outside the SwiftUI surface.
            // Checking just host pixels misses that second background entirely.
            if let frameView = window.contentView?.superview {
                // A contrasting backing makes leaked native material visible.
                let backing = NSView(frame: frameView.bounds)
                backing.wantsLayer = true
                backing.layer?.backgroundColor = NSColor.systemRed.cgColor
                frameView.addSubview(backing, positioned: .below, relativeTo: host)
                frameView.layoutSubtreeIfNeeded()
                frameView.displayIfNeeded()
                CATransaction.flush()
                let frameBitmap = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(frameView.bounds.width),
                    pixelsHigh: Int(frameView.bounds.height),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0
                )!
                let context = NSGraphicsContext(bitmapImageRep: frameBitmap)!.cgContext
                frameView.layer?.render(in: context)
                try frameBitmap.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "\(output)/\(label)-frame.png"))
                for (x, y) in [(2, 2), (frameBitmap.pixelsWide - 3, 2),
                               (2, frameBitmap.pixelsHigh - 3),
                               (frameBitmap.pixelsWide - 3, frameBitmap.pixelsHigh - 3)] {
                    if frameBitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 {
                        failures.append("\(label): native backing leaks outside the rounded outline")
                    }
                }
                if frameBitmap.colorAt(x: frameBitmap.pixelsWide / 2, y: 8)!.alphaComponent < 0.99 {
                    failures.append("\(label): composited frame interior must remain opaque")
                }
                var leakedBacking = false
                for dx in 0..<16 {
                    for dy in 0..<16 {
                        for (x, y) in [(dx, dy), (frameBitmap.pixelsWide - 1 - dx, dy),
                                       (dx, frameBitmap.pixelsHigh - 1 - dy),
                                       (frameBitmap.pixelsWide - 1 - dx, frameBitmap.pixelsHigh - 1 - dy)] {
                            let color = frameBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            // Ignore fractional edge coverage from rasterization.
                            if color.alphaComponent > 0.95
                                && color.redComponent - color.greenComponent > 0.05
                                && color.redComponent - color.blueComponent > 0.05 {
                                leakedBacking = true
                            }
                        }
                    }
                }
                if leakedBacking {
                    failures.append("\(label): contrasting native backing is visible around a corner")
                }
            } else {
                failures.append("\(label): native window frame is unavailable")
            }
            // Loading/errors change the popover's height after it first opens.
            // The new bottom edge must remain inside the resized window mask.
            window.setContentSize(NSSize(width: size.width, height: size.height + 40))
            let expandedBottom = CGPoint(x: size.width / 2, y: size.height + 36)
            let expandedPath = (window.contentView?.superview?.layer?.mask as? CAShapeLayer)?.path
            if expandedPath?.contains(expandedBottom) != true {
                failures.append("\(label): resizing clips newly added content")
            }
            window.setContentSize(size)
            let restoredPath = (window.contentView?.superview?.layer?.mask as? CAShapeLayer)?.path
            if restoredPath?.contains(expandedBottom) != false {
                failures.append("\(label): shrinking leaves a stale oversized mask")
            }
            print("Rendered \(label): \(size)")
        }
        for failure in failures { print("FAIL: \(failure)") }
        if !failures.isEmpty { exit(1) }
        print("Popover rendering checks passed")
    }
}
