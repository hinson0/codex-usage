import AppKit
import CodexUsageCore
import SwiftUI

@main
@MainActor
struct CodexUsageApplication: App {
    @StateObject private var controller: UsageController
    @StateObject private var updater: UpdateCoordinator

    init() {
        _controller = StateObject(wrappedValue: UsageController(service: CodexAppServerClient(), newsService: DivinResetNewsService()))
        _updater = StateObject(wrappedValue: UpdateCoordinator())
    }

    var body: some Scene {
        MenuBarExtra {
            ContentSizedPopover {
                UsagePopoverView(controller: controller, updater: updater)
            }
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
        StatusItemContent(title: controller.statusTitle)
            .task { await updater.monitorForUpdates() }
            .task { await controller.monitorUsage() }
            .onReceive(NotificationCenter.default.publisher(
                for: NSLocale.currentLocaleDidChangeNotification
            )) { _ in
                controller.notifySystemLocaleChanged()
            }
    }
}
