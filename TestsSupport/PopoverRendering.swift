import AppKit
import CodexUsageCore
import SwiftUI
import Vision

@main
struct PopoverRendering {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared
        var failures: [String] = []
        let output = CommandLine.arguments[1]
        // A real 1.1.5 MenuBarExtra has 10-point native padding above/below
        // the SwiftUI surface. The old zero-inset host could not catch the bug.
        for (appearance, language, inset, creditState) in [
            (AppAppearance.light, AppLanguage.zhHans, 0, 0),
            (.dark, .english, 0, 0),
            (.light, .zhHans, 10, 0),
            (.dark, .english, 10, 0),
            (.light, .zhHans, 0, 1),
            (.dark, .english, 0, 1),
            (.light, .zhHans, 10, 1),
            (.dark, .english, 10, 1),
            (.light, .zhHans, 0, 2),
            (.dark, .english, 0, 2),
            (.light, .zhHans, 10, 2),
            (.dark, .english, 10, 2),
            (.light, .zhHans, 0, 3),
            (.dark, .english, 0, 3),
            (.light, .zhHans, 0, 4),
            (.dark, .english, 0, 4),
            (.light, .zhHans, 0, -1),
            (.dark, .english, 0, -1),
        ] {
            let suite = "PopoverRendering.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let newsService = RenderNewsService()
            let controller = UsageController(
                service: RenderUsageService(requiresLogin: creditState == -1, usedPercent: 4,
                    resetCount: creditState == 0 ? 0 : 2,
                    creditExpiresAt: creditState == 2 || creditState == 4
                        ? Int64(Date().timeIntervalSince1970) + (creditState == 4 ? 400 : 5) * 86_400 : nil,
                    resetsAt: creditState == 3 ? nil : Int64(Date().timeIntervalSince1970)
                        + (creditState == 4 ? 400 : 6) * 86_400 + 22 * 3_600 + 300),
                preferences: PreferencesStore(defaults: defaults), newsService: newsService
            )
            controller.setAppearance(appearance)
            controller.setLanguage(language)
            await controller.refresh()
            let updater = UpdateCoordinator()
            if creditState == 1 {
                await newsService.setFailure(true)
                await controller.refresh(forceNews: true)
            }
            let host = NSHostingView(rootView: UsagePopoverView(
                controller: controller, updater: updater
            ).padding(.vertical, CGFloat(inset)))
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
            let label = "\(appearance.rawValue)-\(language.rawValue)-inset\(inset)-credits\(creditState)"
            try bitmap.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(output)/\(label).png"))
            if language == .english && creditState == 2 && inset == 0 {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["en-US"]
                try VNImageRequestHandler(cgImage: bitmap.cgImage!).perform([request])
                let lines = request.results ?? []
                let recognized = lines.compactMap { $0.topCandidates(1).first?.string }
                print("Summary OCR: \(recognized)")
                for required in ["Allowance resets", "Reset credits", "Time left:", "Next credit expires"] {
                    if !recognized.contains(where: { $0.contains(required) }) {
                        failures.append("\(label): missing required visible information: \(required)")
                    }
                }
                if !recognized.contains("2") {
                    failures.append("\(label): positive reset-credit count must remain visible")
                }
                for removedRow in ["Last global reset", "Latest forecast"] {
                    if recognized.contains(where: { $0.contains(removedRow) }) {
                        failures.append("\(label): news must show one record instead of separate history/forecast rows")
                    }
                }
                let expiry = lines.first { $0.topCandidates(1).first?.string.contains("Next credit expires") == true }
                if expiry.map({ $0.boundingBox.minX > 0.45 }) != true {
                    failures.append("\(label): expiry must stay in the right-hand reset-credit group")
                }
                let datedLines = lines.filter {
                    $0.topCandidates(1).first?.string.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil
                }
                if !datedLines.contains(where: { $0.boundingBox.minX < 0.4 })
                    || !datedLines.contains(where: { $0.boundingBox.minX > 0.45 }) {
                    failures.append("\(label): both recovery and next-credit dates must be visible in their own columns")
                }
            }
            if creditState == 0 && inset == 0 {
                for available in [true, false] {
                    updater.hasAvailableUpdate = available
                    try await Task.sleep(for: .milliseconds(100))
                    host.layoutSubtreeIfNeeded()
                    let updateBitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: updateBitmap)
                    let state = available ? "available" : "cleared"
                    try updateBitmap.representation(using: .png, properties: [:])!
                        .write(to: URL(fileURLWithPath: "\(output)/\(appearance.rawValue)-update-\(state).png"))
                    // Check only the settings icon, not the blue allowance or news text.
                    let scale = Double(updateBitmap.pixelsWide) / size.width
                    var greenPixels = 0
                    for x in Int((size.width - 50) * scale)..<Int((size.width - 10) * scale) {
                        for y in Int(15 * scale)..<Int(55 * scale) {
                            let color = updateBitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                            if color.greenComponent > color.redComponent + 0.12
                                && color.greenComponent > color.blueComponent + 0.07 {
                                greenPixels += 1
                            }
                        }
                    }
                    if available && greenPixels < 10 {
                        failures.append("\(appearance.rawValue): available update must render a green settings icon")
                    }
                    if !available && greenPixels != 0 {
                        failures.append("\(appearance.rawValue): settings icon must return to neutral after update clears")
                    }
                }
            }
            // cacheDisplay can include the native mask after SwiftUI layout.
            // Check opacity inside the rounded surface; its exterior corners
            // are checked for transparency in the complete-frame render below.
            let bitmapScale = CGFloat(bitmap.pixelsWide) / size.width
            let insetPixels = Int(CGFloat(inset) * bitmapScale)
            let innerPixels = Int(16 * bitmapScale)
            for (x, y) in [(innerPixels, insetPixels + innerPixels),
                           (bitmap.pixelsWide - innerPixels - 1, insetPixels + innerPixels),
                           (innerPixels, bitmap.pixelsHigh - insetPixels - innerPixels - 1),
                           (bitmap.pixelsWide - innerPixels - 1, bitmap.pixelsHigh - insetPixels - innerPixels - 1)] {
                if bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.99 {
                    failures.append("\(label): visible content near a rounded corner must remain opaque")
                }
            }
            if bitmap.colorAt(x: bitmap.pixelsWide / 2, y: insetPixels + Int(8 * bitmapScale))!.alphaComponent < 0.99 {
                failures.append("\(label): interior background must remain opaque")
            }
            // The selected summary reserves space for both dates and the countdown.
            let heightBudget: CGFloat = creditState > 0 ? 560 : 510
            if size.height - CGFloat(inset * 2) > heightBudget {
                failures.append("\(label): excessive empty space, height \(size.height) > \(heightBudget)")
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
                for (x, y) in [(2, inset + 2), (frameBitmap.pixelsWide - 3, inset + 2),
                               (2, frameBitmap.pixelsHigh - inset - 3),
                               (frameBitmap.pixelsWide - 3, frameBitmap.pixelsHigh - inset - 3)] {
                    if frameBitmap.colorAt(x: x, y: y)!.alphaComponent > 0.1 {
                        failures.append("\(label): native backing leaks outside the rounded outline")
                    }
                }
                if frameBitmap.colorAt(x: frameBitmap.pixelsWide / 2, y: inset + 8)!.alphaComponent < 0.99 {
                    failures.append("\(label): composited frame interior must remain opaque")
                }
                if inset > 0 {
                    for y in [inset / 2, frameBitmap.pixelsHigh - inset / 2 - 1] {
                        if frameBitmap.colorAt(x: frameBitmap.pixelsWide / 2, y: y)!.alphaComponent > 0.1 {
                            failures.append("\(label): native padding remains visible beyond the content")
                        }
                    }
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
            let expandedBottom = CGPoint(x: size.width / 2, y: size.height + 36 - CGFloat(inset))
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
