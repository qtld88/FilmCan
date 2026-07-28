import Foundation
import Sparkle

final class UpdaterService: NSObject {
    static let shared = UpdaterService()

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
