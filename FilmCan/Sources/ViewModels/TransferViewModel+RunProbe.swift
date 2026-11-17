import Foundation

extension TransferViewModel {
    /// Everything `startTransfer` needs to know about the run's drives, read in one
    /// go off the main thread: a slow, sleeping or network volume must not freeze the
    /// window at the Run click. Consumed at the same steps as before (roll numbering,
    /// capacity snapshot, copy mode, destination writer setup), so the run's order
    /// does not change.
    struct RunProbe {
        /// Sources only.
        var isDirectory: [String: Bool] = [:]
        /// Sources only: `RollNumberer.cardKey(forPath:)`.
        var cardKeys: [String: String] = [:]
        /// Sources only, and only when asked (roll numbering on): camera card signature.
        var signatures: [String: CardSignature] = [:]
        /// Every path, keyed by drive (`DriveUtilities.summary(for:).id`).
        var capacity: [String: DriveCapacitySnapshot] = [:]
        /// Destinations only: IOKit drive facts (`DriveSpeedClassifier.info(for:)`).
        var driveInfo: [String: DriveInfo] = [:]

        func cardKey(for path: String) -> String {
            cardKeys[path] ?? RollNumberer.cardKey(forPath: path)
        }

        func info(for destination: String) -> DriveInfo {
            driveInfo[destination] ?? DriveSpeedClassifier.info(for: destination)
        }
    }

    nonisolated static func probeRun(sources: [String], destinations: [String],
                                     detectCameras: Bool) async -> RunProbe {
        await Task.detached(priority: .userInitiated) {
            TransferViewModel.probeRunNow(sources: sources, destinations: destinations, detectCameras: detectCameras)
        }.value
    }

    nonisolated static func probeRunNow(sources: [String], destinations: [String],
                                        detectCameras: Bool) -> RunProbe {
        var probe = RunProbe()
        let fm = FileManager.default
        for path in sources {
            var isDir: ObjCBool = false
            probe.isDirectory[path] = fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            probe.cardKeys[path] = RollNumberer.cardKey(forPath: path)
            if detectCameras, let signature = CameraCardDetector.detect(rootPath: path) {
                probe.signatures[path] = signature
            }
        }
        for path in sources + destinations {
            let id = DriveUtilities.summary(for: path).id
            guard probe.capacity[id] == nil else { continue }
            let capacity = DriveUtilities.capacity(for: path)
            probe.capacity[id] = DriveCapacitySnapshot(totalBytes: capacity.total,
                                                       availableBytes: capacity.available)
        }
        for path in destinations where probe.driveInfo[path] == nil {
            probe.driveInfo[path] = DriveSpeedClassifier.info(for: path)
        }
        return probe
    }
}
