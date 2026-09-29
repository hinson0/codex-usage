import AppKit
import CodexUsageCore
import SwiftUI

private actor MenuBarRenderService: UsageService {
    var fails = false

    func setFailure(_ value: Bool) { fails = value }

    func readRateLimits() async throws -> UsageSnapshot {
        try await Task.sleep(for: .milliseconds(CommandLine.arguments.contains("--slow") ? 1_500 : 400))
        if fails { throw UsageServiceError.unavailable("Fixture error that changes the popover height.") }
        return try await RenderUsageService(usedPercent: 6, resetCount: 1).readRateLimits()
    }
}

@MainActor
private final class SurfaceObservation: ObservableObject {
    weak var view: NSView?
}

// Independent measurement of the visible SwiftUI surface for screenshot checks.
private struct SurfaceProbe: NSViewRepresentable {
    let observation: SurfaceObservation

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        observation.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// This separate test executable never starts Sparkle or accesses a live account.
// It clicks only its own status button and exits after compositor captures.
@main
@MainActor
struct MenuBarPopoverRendering: App {
    @StateObject private var controller: UsageController
    @StateObject private var updater = UpdateCoordinator()
    @StateObject private var surface = SurfaceObservation()
    private let service = MenuBarRenderService()
    private let suite = "MenuBarPopoverRendering.\(UUID().uuidString)"
    private let inset = CGFloat(Int(CommandLine.arguments[1])!)
    private let output = CommandLine.arguments[2]

    init() {
        let controller = UsageController(
            service: service,
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: suite)!)
        )
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentSizedPopover {
                UsagePopoverView(controller: controller, updater: updater)
                    .background(SurfaceProbe(observation: surface))
            }
            .padding(.vertical, inset)
        } label: {
            StatusItemContent(title: controller.statusTitle)
                .task { await runChecks() }
        }
        .menuBarExtraStyle(.window)
    }

    private func runChecks() async {
        do {
            controller.setLanguage(.zhHans)
            if CommandLine.arguments.contains("--warm") {
                await controller.refresh()
            }
            try await Task.sleep(for: .milliseconds(200))
            guard let button = NSApp.windows.compactMap(\.contentView)
                .compactMap(findStatusButton).first else {
                throw CheckFailure("Test status button unavailable")
            }
            button.performClick(nil)
            try await Task.sleep(for: .milliseconds(100))
            try await capture(CommandLine.arguments.contains("--warm") ? "refreshing" : "loading")
            try await waitForRefresh()
            try await capture("light-zh")
            try captureStatusItem(button)

            controller.setAppearance(.dark)
            try await settle()
            try await capture("dark-zh")
            controller.setLanguage(.english)
            try await settle()
            try await capture("dark-en")

            await service.setFailure(true)
            await controller.refresh()
            try await settle()
            try await capture("error-expanded")
            await service.setFailure(false)
            await controller.refresh()
            try await settle()
            try await capture("error-cleared")

            controller.setLanguage(.zhHans)
            controller.setAppearance(.light)
            try await settle()
            for index in 1...3 {
                button.performClick(nil)
                try await settle()
                button.performClick(nil)
                try await waitForRefresh()
                try await capture("reopen-\(index)")
            }
            print("Native MenuBarExtra checks passed (inset \(Int(inset)))")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            exit(0)
        } catch {
            print("FAIL: \(error)")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            exit(1)
        }
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    private func waitForRefresh() async throws {
        try await settle()
        for _ in 0..<40 {
            if !controller.isRefreshing { try await settle(); return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CheckFailure("Fixture refresh did not finish")
    }

    private func findStatusButton(_ view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.compactMap(findStatusButton).first
    }

    private func captureStatusItem(_ button: NSStatusBarButton) throws {
        guard button.title == "94% (1)", let icon = button.image, icon.isTemplate,
              icon.size == NSSize(width: 18, height: 18), let window = button.window else {
            throw CheckFailure("Status item must show the 18-point template icon and 94% (1); got \(button.title)")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // Status windows cannot be captured by window ID on every macOS release.
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let top = NSScreen.screens[0].frame.maxY - rect.maxY
        let region = "\(Int(rect.minX)),\(Int(top)),\(Int(rect.width)),\(Int(rect.height))"
        process.arguments = ["-x", "-R\(region)", "\(output)/inset\(Int(inset))-status.png"]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CheckFailure("Status item capture failed") }
    }

    private func capture(_ state: String) async throws {
        // Desktop focus changes can dismiss MenuBarExtra while this test is
        // running. Restore only our own test window before taking its snapshot.
        if let window = surface.view?.window, !window.isVisible {
            window.orderFrontRegardless()
            try await settle()
        }
        guard let view = surface.view, let window = view.window,
              let frame = window.contentView?.superview, window.isVisible else {
            throw CheckFailure("\(state): actual MenuBarExtra window is not visible")
        }
        let path = "\(output)/inset\(Int(inset))-\(state).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.windowNumber)", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))) else {
            throw CheckFailure("\(state): screen capture unavailable; requires Screen Recording access")
        }
        let rect = view.convert(view.bounds, to: frame)
        let scale = CGFloat(bitmap.pixelsWide) / frame.bounds.width
        let left = rect.minX - frame.bounds.minX
        let right = rect.maxX - frame.bounds.minX
        let top = frame.bounds.maxY - rect.maxY
        let bottom = frame.bounds.maxY - rect.minY
        let surfaceOnScreen = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard let statusWindow = NSApp.windows.first(where: {
            $0.contentView.flatMap(findStatusButton) != nil
        }) else { throw CheckFailure("\(state): status window unavailable") }
        let menuGap = statusWindow.frame.minY - surfaceOnScreen.maxY
        print("GEOMETRY: \(state), menu gap \(menuGap), window \(window.frame), surface \(surfaceOnScreen)")
        if state == "light-zh", let mainScreen = NSScreen.screens.first {
            // Keep the menu bar in the evidence: an isolated window crop cannot
            // establish its distance from the status item.
            let region = NSRect(
                x: window.frame.minX,
                y: mainScreen.frame.maxY - statusWindow.frame.maxY,
                width: window.frame.width,
                height: statusWindow.frame.maxY - surfaceOnScreen.minY + 12
            )
            let anchorCapture = Process()
            anchorCapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            anchorCapture.arguments = [
                "-x", "-R\(Int(region.minX)),\(Int(region.minY)),\(Int(region.width)),\(Int(region.height))",
                "\(output)/inset\(Int(inset))-menu-anchor.png",
            ]
            try anchorCapture.run()
            anchorCapture.waitUntilExit()
            guard anchorCapture.terminationStatus == 0 else {
                throw CheckFailure("\(state): menu anchor capture failed")
            }
        }
        guard menuGap >= 0, menuGap <= 2 else {
            throw CheckFailure("\(state): empty strip below menu bar is \(menuGap) points; expected 0...2; screenshot: \(path)")
        }
        func alpha(_ x: CGFloat, _ y: CGFloat) throws -> CGFloat {
            let pixelX = Int(x * scale)
            let pixelY = Int(y * scale)
            guard pixelX >= 0, pixelY >= 0,
                  pixelX < bitmap.pixelsWide, pixelY < bitmap.pixelsHigh,
                  let color = bitmap.colorAt(x: pixelX, y: pixelY) else {
                throw CheckFailure("\(state): sample (\(pixelX), \(pixelY)) outside \(bitmap.pixelsWide) × \(bitmap.pixelsHigh); frame \(frame.bounds), surface \(rect)")
            }
            return color.alphaComponent
        }
        for (x, y) in [(left + 2, top + 2), (right - 3, top + 2),
                       (left + 2, bottom - 3), (right - 3, bottom - 3)] {
            guard try alpha(x, y) < 0.1 else {
                throw CheckFailure("\(state): square corner at (\(x), \(y)); screenshot: \(path)")
            }
        }
        if top >= 2, try alpha((left + right) / 2, top - 2) > 0.1 {
            throw CheckFailure("\(state): native backing visible above content")
        }
        if bottom + 2 < frame.bounds.height, try alpha((left + right) / 2, bottom + 2) > 0.1 {
            throw CheckFailure("\(state): native backing visible below content")
        }
        guard try alpha((left + right) / 2, top + 8) > 0.99 else {
            throw CheckFailure("\(state): opaque content clipped")
        }
        try await checkDesktopOutline(state, window: window)
        print("PASS: inset\(Int(inset))-\(state), surface \(rect)")
    }

    private func checkDesktopOutline(_ state: String, window: NSWindow) async throws {
        // A white desktop exposes a transparent gap between the content edge and
        // the native shadow. Black backdrops and shadow-free captures hide it.
        let backing = NSWindow(contentRect: window.frame.insetBy(dx: -20, dy: -20), styleMask: .borderless,
                               backing: .buffered, defer: false)
        backing.backgroundColor = .white
        backing.hasShadow = false
        backing.level = NSWindow.Level(rawValue: window.level.rawValue - 1)
        backing.orderFrontRegardless()
        defer { backing.orderOut(nil) }
        try await settle()
        if !window.isVisible {
            window.orderFrontRegardless()
            try await settle()
        }
        guard let view = self.surface.view else { throw CheckFailure("Surface unavailable") }
        let surface = window.convertToScreen(view.convert(view.bounds, to: nil))
        guard surface.minY >= window.frame.minY - 0.5,
              surface.maxY <= window.frame.maxY + 0.5 else {
            throw CheckFailure("\(state): content extends beyond its window; window \(window.frame), surface \(surface)")
        }
        let region = window.frame.insetBy(dx: -20, dy: -20)
        backing.setFrame(region, display: true)
        let path = "\(output)/inset\(Int(inset))-\(state)-desktop.png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let screenTop = NSScreen.screens[0].frame.maxY
        process.arguments = ["-x", "-R\(Int(region.minX)),\(Int(screenTop - region.maxY)),\(Int(region.width)),\(Int(region.height))", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))) else {
            throw CheckFailure("\(state): desktop capture failed")
        }
        let scale = CGFloat(bitmap.pixelsWide) / region.width
        let x = Int((surface.midX - region.minX) * scale)
        let luminance = try (2..<20).map { offset in
            let y = Int((region.maxY - surface.minY + CGFloat(offset)) * scale)
            guard x >= 0, x < bitmap.pixelsWide, y >= 0, y < bitmap.pixelsHigh,
                  let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                throw CheckFailure("\(state): shadow sample outside desktop capture")
            }
            return color.redComponent
        }
        guard luminance.prefix(3).min()! < 0.98 else {
            throw CheckFailure("\(state): shadow does not meet the content edge; screenshot: \(path)")
        }
        for (near, far) in zip(luminance, luminance.dropFirst()) where far < near - 0.02 {
            throw CheckFailure("\(state): detached shadow below content (\(near) → \(far)); screenshot: \(path)")
        }
    }
}

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
