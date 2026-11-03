import AppKit
import ApplicationServices
import CodexUsageCore
import SwiftUI

private actor MenuBarRenderService: UsageService {
    var fails = false
    private(set) var reads = 0

    func setFailure(_ value: Bool) { fails = value }

    func readRateLimits() async throws -> UsageSnapshot {
        reads += 1
        try await Task.sleep(for: .milliseconds(CommandLine.arguments.contains("--slow") ? 4_000 : 3_000))
        if fails { throw UsageServiceError.unavailable("Fixture error that changes the popover height.") }
        return try await RenderUsageService(usedPercent: 6, resetCount: 1).readRateLimits()
    }
}

@MainActor
private final class SurfaceObservation: ObservableObject {
    weak var view: NSView?
    var openedURL: URL?
    var activeMenu: NSMenu?
    @objc func menuStarted(_ notification: Notification) { activeMenu = notification.object as? NSMenu }
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
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: suite)!),
            newsService: RenderNewsService()
        )
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentSizedPopover {
                UsagePopoverView(controller: controller, updater: updater)
                    .background(SurfaceProbe(observation: surface))
                    .environment(\.openURL, OpenURLAction { url in
                        surface.openedURL = url
                        return .handled
                    })
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
            } else {
                Task { await controller.refresh() }
            }
            try await Task.sleep(for: .milliseconds(200))
            guard let button = NSApp.windows.compactMap(\.contentView)
                .compactMap(findStatusButton).first else {
                throw CheckFailure("Test status button unavailable")
            }
            try await setPopoverVisible(true, using: button)
            if !CommandLine.arguments.contains("--warm"), !controller.isRefreshing {
                throw CheckFailure("The loading fixture finished before its screenshot")
            }
            try await capture(CommandLine.arguments.contains("--warm") ? "refreshing" : "loading")
            try await checkFeedbackLink()
            try await waitForRefresh()
            try await capture("light-zh")
            try await checkFeedbackLink()
            try captureStatusItem(button)

            controller.setAppearance(.dark)
            try await settle()
            try await capture("dark-zh")
            controller.setLanguage(.english)
            try await settle()
            try await capture("dark-en")
            try await checkFeedbackLink()

            await service.setFailure(true)
            await controller.refresh()
            try await settle()
            try await capture("error-expanded")
            try await checkFeedbackLink()
            await service.setFailure(false)
            await controller.refresh()
            try await settle()
            try await capture("error-cleared")

            controller.setLanguage(.zhHans)
            controller.setAppearance(.light)
            try await settle()
            let readsBeforeReopening = await service.reads
            for index in 1...3 {
                if surface.view?.window?.isVisible != true {
                    try await setPopoverVisible(true, using: button)
                }
                try await setPopoverVisible(false, using: button)
                try await setPopoverVisible(true, using: button)
                try await waitForRefresh()
                try await capture("reopen-\(index)")
            }
            guard await service.reads == readsBeforeReopening else {
                throw CheckFailure("Reopening the popover triggered a usage refresh")
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

    private func setPopoverVisible(_ visible: Bool, using button: NSStatusBarButton) async throws {
        for _ in 0..<4 {
            try await clickStatusItem(button)
            try await settle()
            if (surface.view?.window?.isVisible == true) == visible { return }
        }
        throw CheckFailure("Status item did not \(visible ? "open" : "close") the popover")
    }

    private func statusItem() -> AXUIElement? {
        var menu: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateApplication(getpid()), "AXExtrasMenuBar" as CFString, &menu
        ) == .success, let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else { return nil }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            menu as! AXUIElement, kAXChildrenAttribute as CFString, &children
        ) == .success, let items = children as? [AXUIElement], items.count == 1 else { return nil }
        return items[0]
    }

    private func clickStatusItem(_ button: NSStatusBarButton) async throws {
        if statusItem() == nil, let window = button.window,
           let screen = window.screen, let primary = NSScreen.screens.first {
            // macOS may place a new status item in its hidden overflow area.
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let y = primary.frame.maxY - rect.midY
            for x in stride(from: screen.frame.minX, through: screen.frame.maxX, by: 4.0) {
                var hit: AXUIElement?
                guard AXUIElementCopyElementAtPosition(
                    AXUIElementCreateSystemWide(), Float(x), Float(y), &hit
                ) == .success, let hit else { continue }
                var identifier: CFTypeRef?
                guard AXUIElementCopyAttributeValue(hit, "AXIdentifier" as CFString, &identifier) == .success,
                      identifier as? String == "menu-bar-overflow-indicator" else { continue }
                guard AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success else {
                    throw CheckFailure("Could not reveal hidden menu bar items")
                }
                try await settle()
                break
            }
        }
        for _ in 0..<20 {
            if let item = statusItem() {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(item, "AXFrame" as CFString, &value) == .success,
                   let value, CFGetTypeID(value) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(value as! AXValue, .cgRect, &rect) {
                        let point = CGPoint(x: rect.midX, y: rect.midY)
                        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
                            guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                                      mouseCursorPosition: point, mouseButton: .left) else {
                                throw CheckFailure("Could not create a status item click")
                            }
                            event.post(tap: .cghidEventTap)
                            try await Task.sleep(for: .milliseconds(50))
                        }
                        return
                    }
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CheckFailure("Status item unavailable; enable Accessibility and reveal hidden menu bar items")
    }

    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    private func checkFeedbackLink() async throws {
        let title = LocalizationCatalog.string(.feedback, language: controller.language)
        guard let view = surface.view, let window = view.window else {
            throw CheckFailure("Feedback surface is unavailable")
        }
        // Open the top-right Settings menu; Feedback moved out of the footer.
        // Observe the actual native menu and invoke its Feedback item by title.
        let point = view.convert(NSPoint(
            x: view.bounds.maxX - 31,
            y: view.isFlipped ? view.bounds.minY + 34 : view.bounds.maxY - 34
        ), to: nil)
        surface.openedURL = nil
        surface.activeMenu = nil
        NotificationCenter.default.addObserver(surface, selector: #selector(SurfaceObservation.menuStarted(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(surface, name: NSMenu.didBeginTrackingNotification, object: nil) }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ) else { throw CheckFailure("Feedback click event is unavailable") }
            NSApp.postEvent(event, atStart: false)
        }
        try await settle()
        guard let menu = surface.activeMenu,
              let index = menu.items.firstIndex(where: { $0.title == title }) else {
            throw CheckFailure("Feedback item missing from Settings menu")
        }
        menu.performActionForItem(at: index)
        menu.cancelTracking()
        try await settle()
        guard surface.openedURL?.absoluteString == "https://github.com/hinson0/codex-usage/issues" else {
            throw CheckFailure("Feedback link did not open the project Issues page")
        }
        print("PASS: \(title) opens project Issues")
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
        if surface.view?.window?.isVisible != true,
           let button = NSApp.windows.compactMap(\.contentView).compactMap(findStatusButton).first {
            // A focus change can dismiss the popover; reopen it through the real status item.
            try await setPopoverVisible(true, using: button)
        }
        guard let view = surface.view, let window = view.window,
              let frame = window.contentView?.superview, window.isVisible else {
            let observedWindow = surface.view?.window
            throw CheckFailure("\(state): actual MenuBarExtra window is not visible "
                + "(surface: \(surface.view != nil), window: \(observedWindow != nil), "
                + "visible: \(observedWindow?.isVisible ?? false), active: \(NSApp.isActive))")
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
        guard surfaceOnScreen.minY >= window.frame.minY - 0.5,
              surfaceOnScreen.maxY <= window.frame.maxY + 0.5 else {
            throw CheckFailure("\(state): content extends beyond its window")
        }
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
        try checkWindowShadow(state, window: window)
        print("PASS: inset\(Int(inset))-\(state), surface \(rect)")
    }

    private func checkWindowShadow(_ state: String, window: NSWindow) throws {
        // Capture the compositor's window and shadow together; compositing the
        // alpha onto white avoids screen-coordinate ambiguity on multiple displays.
        let path = "\(output)/inset\(Int(inset))-\(state)-shadow.png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-l\(window.windowNumber)", path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let bitmap = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: path))) else {
            throw CheckFailure("\(state): window shadow capture failed")
        }
        let x = bitmap.pixelsWide / 2
        let opaqueRows = (0..<bitmap.pixelsHigh).filter {
            bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0 > 0.99
        }
        let scale = window.screen?.backingScaleFactor ?? 1
        guard let bottom = opaqueRows.last,
              opaqueRows.count >= Int(window.frame.height * scale * 0.85) else {
            throw CheckFailure("\(state): captured image does not contain the full window")
        }
        let luminance = try (2..<20).map { offset -> CGFloat in
            let y = bottom + Int(CGFloat(offset) * scale)
            guard y < bitmap.pixelsHigh,
                  let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
                throw CheckFailure("\(state): shadow sample outside window capture")
            }
            return 1 - color.alphaComponent + color.redComponent * color.alphaComponent
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
