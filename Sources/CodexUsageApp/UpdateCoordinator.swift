import Foundation
import Sparkle

@MainActor
final class UpdateCoordinator: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var hasAvailableUpdate = false
    @Published private(set) var canCheckForUpdates = false

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )
    private var canCheckObservation: NSKeyValueObservation?
    private var hasStarted = false

    override init() {
        super.init()
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

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        hasAvailableUpdate = true
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        hasAvailableUpdate = false
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
