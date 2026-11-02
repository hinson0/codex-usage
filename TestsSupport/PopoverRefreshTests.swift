import AppKit
import CodexUsageCore
import SwiftUI

private actor CountingUsage: UsageService {
    private(set) var reads = 0
    func readRateLimits() async throws -> UsageSnapshot {
        reads += 1
        return try await RenderUsageService().readRateLimits()
    }
}

@MainActor
private final class AppearanceProbe {
    var count = 0
}

@main
@MainActor
struct PopoverRefreshTests {
    static func main() async throws {
        _ = NSApplication.shared
        let usage = CountingUsage()
        let suite = "PopoverRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = UsageController(service: usage, preferences: PreferencesStore(defaults: defaults))
        let updater = UpdateCoordinator()
        let probe = AppearanceProbe()
        await controller.refresh()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: UsagePopoverView(
            controller: controller, updater: updater
        ).onAppear { probe.count += 1 })
        for _ in 0..<3 {
            window.orderFrontRegardless()
            try await Task.sleep(for: .milliseconds(150))
            window.orderOut(nil)
            try await Task.sleep(for: .milliseconds(150))
        }
        guard await usage.reads == 1 else {
            throw UsageServiceError.unavailable("Opening the popover triggered an additional usage read")
        }
        guard probe.count > 0, updater.informationChecks == 0 else {
            throw UsageServiceError.unavailable("Popover did not appear or triggered an update check")
        }
        print("Popover opening did not trigger an additional usage read")
    }
}
