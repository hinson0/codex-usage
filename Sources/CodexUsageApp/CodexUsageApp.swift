import AppKit
import CodexUsageCore
import SwiftUI

@main
@MainActor
struct CodexUsageApplication: App {
    @StateObject private var controller: UsageController
    @StateObject private var updater: UpdateCoordinator

    init() {
        _controller = StateObject(wrappedValue: UsageController(service: CodexAppServerClient()))
        _updater = StateObject(wrappedValue: UpdateCoordinator())
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(controller: controller, updater: updater)
        } label: {
            StatusItemLabel(controller: controller, updater: updater)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusItemLabel: View {
    @ObservedObject var controller: UsageController
    @ObservedObject var updater: UpdateCoordinator

    var body: some View {
        Text(controller.statusTitle)
            .task { await updater.monitorForUpdates() }
            .task {
                await controller.refresh()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    guard !Task.isCancelled else { return }
                    await controller.refresh()
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: NSLocale.currentLocaleDidChangeNotification
            )) { _ in
                controller.notifySystemLocaleChanged()
            }
    }
}
