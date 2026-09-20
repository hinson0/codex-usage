import AppKit
import CodexUsageCore
import SwiftUI

@main
@MainActor
struct CodexUsageApplication: App {
    @StateObject private var controller: UsageController

    init() {
        _controller = StateObject(wrappedValue: UsageController(service: CodexAppServerClient()))
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(controller: controller)
        } label: {
            StatusItemLabel(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct StatusItemLabel: View {
    @ObservedObject var controller: UsageController

    var body: some View {
        Text(controller.statusTitle)
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
