import Foundation
import Sparkle

@MainActor
final class UpdateCoordinator: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?
    private var hasStarted = false

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            let available = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = available
            }
        }
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        controller.startUpdater()
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller.checkForUpdates(nil)
    }
}
