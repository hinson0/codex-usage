import AppKit
import CodexUsageCore
import SwiftUI

@MainActor
private final class UpdateSurface: ObservableObject {
    weak var view: NSView?
    var menu: NSMenu?
    @objc func menuStarted(_ notification: Notification) { menu = notification.object as? NSMenu }
}

private struct UpdateSurfaceProbe: NSViewRepresentable {
    let surface: UpdateSurface
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        surface.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// Exercises the production Settings action in a real MenuBarExtra. Sparkle and
// the account service are replaced; no update is installed and no screen is captured.
@main
@MainActor
struct UpdateWindowPresentationTests: App {
    @StateObject private var controller: UsageController
    @StateObject private var updater = UpdateCoordinator()
    @StateObject private var surface = UpdateSurface()
    private let suite = "UpdateWindowPresentationTests.\(UUID().uuidString)"

    init() {
        let controller = UsageController(service: RenderUsageService(),
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: suite)!))
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        MenuBarExtra {
            ContentSizedPopover {
                UsagePopoverView(controller: controller, updater: updater)
                    .background(UpdateSurfaceProbe(surface: surface))
            }
        } label: {
            Text("Update window test").task { await runChecks() }
        }
        .menuBarExtraStyle(.window)
    }

    private func runChecks() async {
        do {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                print("FAIL: update-window interaction timed out")
                exit(1)
            }
            try await settle()
            guard let button = NSApp.windows.compactMap(\.contentView)
                .compactMap(findStatusButton).first else { throw Failure("status button unavailable") }
            for (language, available) in [(AppLanguage.zhHans, false), (.english, false),
                                          (.zhHans, true), (.english, true)] {
                controller.setLanguage(language)
                updater.hasAvailableUpdate = available
                button.performClick(nil)
                try await settle()
                guard let view = surface.view, let popover = view.window, popover.isVisible else {
                    throw Failure("popover must be visible before selecting update")
                }
                let updateWindow = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 280),
                                            styleMask: [.titled], backing: .buffered, defer: false)
                var calls = 0
                var hiddenBeforeUpdate = false
                updater.onCheckForUpdates = {
                    calls += 1
                    hiddenBeforeUpdate = !popover.isVisible
                    updateWindow.makeKeyAndOrderFront(nil)
                }
                surface.menu = nil
                NotificationCenter.default.addObserver(surface, selector: #selector(UpdateSurface.menuStarted(_:)),
                                                       name: NSMenu.didBeginTrackingNotification, object: nil)
                let point = view.convert(NSPoint(x: view.bounds.maxX - 31,
                    y: view.isFlipped ? view.bounds.minY + 34 : view.bounds.maxY - 34), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popover.windowNumber,
                        context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
                        throw Failure("settings click unavailable")
                    }
                    NSApp.postEvent(event, atStart: false)
                }
                try await settle()
                let title = LocalizationCatalog.string(available ? .updateAvailable : .checkForUpdates,
                                                       language: language)
                guard let menu = surface.menu, let index = menu.items.firstIndex(where: { $0.title == title }) else {
                    throw Failure("update item unavailable")
                }
                menu.performActionForItem(at: index)
                menu.cancelTracking()
                NotificationCenter.default.removeObserver(surface)
                try await settle()
                guard calls == 1, hiddenBeforeUpdate, !popover.isVisible, updateWindow.isVisible else {
                    throw Failure("update action must hide the popover before opening the update window; calls=\(calls), hiddenBeforeUpdate=\(hiddenBeforeUpdate), popoverVisible=\(popover.isVisible), updateVisible=\(updateWindow.isVisible)")
                }
                updateWindow.orderOut(nil)
                updater.onCheckForUpdates = nil
                button.performClick(nil)
                try await settle()
                guard popover.isVisible else { throw Failure("status button must reopen the popover after update") }
                button.performClick(nil)
                try await settle()
                print("PASS: \(title) opens an unobstructed update window and popover reopens")
            }
            print("Native update window presentation checks passed")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            exit(0)
        } catch {
            print("FAIL: \(error)")
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            exit(1)
        }
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(350)) }
    private func findStatusButton(_ view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.compactMap(findStatusButton).first
    }
    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
