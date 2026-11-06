#if DEBUG
import Foundation

// Debug-only demo mode; env vars are documented in docs/promo/asset-list.md.
struct DemoSettings: Equatable {
    enum State: String { case setup, copying, verifying, done }

    var state: State = .copying
    var progress: Double = 0.60
    var speedBytesPerSecond: Double = 500_000_000
    var totalBytes: Int64 = 14_750_000_000
    var quickCopySources: [String] = []
    var quickCopyDestinations: [String] = []

    static let current: DemoSettings? = parse(ProcessInfo.processInfo.environment)
    static var isActive: Bool { current != nil }

    static func parse(_ env: [String: String]) -> DemoSettings? {
        let stateRaw = env["FILMCAN_DEMO_STATE"]?.lowercased()
        let sources = list(env["FILMCAN_DEMO_QUICKCOPY"])
        guard stateRaw != nil || !sources.isEmpty else { return nil }

        var settings = DemoSettings()
        if let stateRaw {
            guard let state = State(rawValue: stateRaw) else { return nil }
            settings.state = state
        } else {
            settings.state = .setup
        }
        if let raw = env["FILMCAN_DEMO_PROGRESS"], let value = Double(raw) {
            settings.progress = min(max(value, 0), 1)
        }
        if let raw = env["FILMCAN_DEMO_SPEED_MBPS"], let value = Double(raw), value > 0 {
            settings.speedBytesPerSecond = value * 1_000_000
        }
        if let raw = env["FILMCAN_DEMO_TOTAL_GB"], let value = Double(raw), value > 0 {
            settings.totalBytes = Int64(value * 1_000_000_000)
        }
        settings.quickCopySources = sources
        settings.quickCopyDestinations = list(env["FILMCAN_DEMO_QUICKCOPY_DEST"])
        return settings
    }

    private static func list(_ raw: String?) -> [String] {
        (raw ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

struct DemoRunSnapshot: Equatable {
    static let defaultFilesTotal = 15
    static let verifyLag = 0.85

    let state: DemoSettings.State
    let totalBytes: Int64
    let copiedBytes: Int64
    let verifiedBytes: Int64
    let filesTotal: Int
    let filesCompleted: Int
    let currentFile: String
    let speedBytesPerSecond: Double
    let eta: TimeInterval?

    static func make(state: DemoSettings.State,
                     totalBytes: Int64,
                     progress: Double,
                     speedBytesPerSecond: Double,
                     filesTotal: Int = defaultFilesTotal) -> DemoRunSnapshot {
        let p = min(max(progress, 0), 1)
        let total = max(totalBytes, 0)
        let files = max(filesTotal, 1)
        func bytes(_ fraction: Double) -> Int64 { Int64((Double(total) * fraction).rounded(.down)) }
        func etaSeconds(done: Int64) -> TimeInterval? {
            guard speedBytesPerSecond > 0, total > done else { return nil }
            return Double(total - done) / speedBytesPerSecond
        }
        func fileName(_ index: Int) -> String { String(format: "A003C%03d_R1KD.mov", index + 1) }
        let filesAtP = min(Int(p * Double(files)), files)

        switch state {
        case .setup:
            return DemoRunSnapshot(state: state, totalBytes: total, copiedBytes: 0, verifiedBytes: 0,
                                   filesTotal: files, filesCompleted: 0, currentFile: "",
                                   speedBytesPerSecond: 0, eta: nil)
        case .copying:
            let copied = bytes(p)
            return DemoRunSnapshot(state: state, totalBytes: total, copiedBytes: copied,
                                   verifiedBytes: bytes(p * verifyLag),
                                   filesTotal: files, filesCompleted: filesAtP,
                                   currentFile: fileName(min(filesAtP, files - 1)),
                                   speedBytesPerSecond: speedBytesPerSecond,
                                   eta: etaSeconds(done: copied))
        case .verifying:
            let verified = bytes(p)
            return DemoRunSnapshot(state: state, totalBytes: total, copiedBytes: total,
                                   verifiedBytes: verified,
                                   filesTotal: files, filesCompleted: files,
                                   currentFile: fileName(min(filesAtP, files - 1)),
                                   speedBytesPerSecond: speedBytesPerSecond,
                                   eta: etaSeconds(done: verified))
        case .done:
            return DemoRunSnapshot(state: state, totalBytes: total, copiedBytes: total,
                                   verifiedBytes: total,
                                   filesTotal: files, filesCompleted: files, currentFile: "",
                                   speedBytesPerSecond: 0, eta: nil)
        }
    }

    func destProgress(id: String, displayName: String, verifyMode: VerifyMode) -> DestProgress {
        var dest = DestProgress(id: id, displayName: displayName,
                                status: state == .done ? .complete : .active,
                                verifyMode: verifyMode)
        dest.bytesTotal = totalBytes
        dest.bytesCompleted = copiedBytes
        dest.filesTotal = filesTotal
        dest.filesCompleted = filesCompleted
        dest.currentFile = currentFile
        dest.speedBytesPerSecond = speedBytesPerSecond
        dest.estimatedTimeRemaining = eta
        if verifyMode != .off {
            dest.verifyBytesTotal = totalBytes
            dest.verifyBytesCompleted = verifiedBytes
        }
        return dest
    }
}

extension TransferViewModel {
    func applyDemoRun(configId: UUID?,
                      sources: [String],
                      destinations: [String],
                      verifyMode: VerifyMode,
                      settings: DemoSettings) {
        guard settings.state != .setup else { return }
        let snap = DemoRunSnapshot.make(state: settings.state,
                                        totalBytes: settings.totalBytes,
                                        progress: settings.progress,
                                        speedBytesPerSecond: settings.speedBytesPerSecond)
        let finished = settings.state == .done
        let verifying = settings.state == .verifying

        activeConfigId = configId
        currentSources = sources
        allDestinations = destinations
        isParallelRun = destinations.count > 1
        isTransferring = !finished
        cancelledDestinations = []
        alreadyBackedUp = nil

        progress.resetProgress()
        progress.perDestProgress = destinations.map {
            snap.destProgress(id: $0, displayName: ($0 as NSString).lastPathComponent, verifyMode: verifyMode)
        }
        progress.syncFromPerDest()
        progress.isRunning = !finished
        progress.phase = finished ? .finished : (verifying ? .verifying : .copying)
        progress.copyingDone = finished || verifying
        progress.cumulativeBytes = snap.copiedBytes
        progress.speedBytesPerSecond = snap.speedBytesPerSecond
        progress.estimatedTimeRemaining = snap.eta
        progress.currentFile = snap.currentFile
        if verifyMode != .off {
            progress.verificationBytesTotal = snap.totalBytes
            progress.verificationBytesCompleted = snap.verifiedBytes
            progress.verificationFilesTotal = snap.filesTotal
            progress.verificationFilesCompleted = snap.totalBytes > 0
                ? Int(Double(snap.filesTotal) * Double(snap.verifiedBytes) / Double(snap.totalBytes))
                : 0
            progress.verificationHasStarted = true
            progress.verificationIsActive = !finished
            progress.verificationPhase = finished ? .complete : .verifying
        }

        var capacities: [String: DriveCapacitySnapshot] = [:]
        if !finished {
            for path in sources + destinations {
                let summary = DriveUtilities.summary(for: path)
                if capacities[summary.id] == nil {
                    let capacity = DriveUtilities.capacity(for: path)
                    capacities[summary.id] = DriveCapacitySnapshot(totalBytes: capacity.total,
                                                                   availableBytes: capacity.available)
                }
            }
        }
        driveCapacitySnapshot = capacities

        guard finished else {
            results = []
            return
        }
        let end = Date()
        let start = end.addingTimeInterval(-Double(snap.totalBytes) / 500_000_000)
        results = destinations.map { destination in
            let dest = DestResult(destinationPath: destination,
                                  displayName: (destination as NSString).lastPathComponent,
                                  success: true,
                                  filesTransferred: snap.filesTotal,
                                  bytesTransferred: snap.totalBytes,
                                  durationSec: end.timeIntervalSince(start),
                                  verifyMode: verifyMode)
            var result = TransferResult(configurationName: "Demo",
                                        destination: destination,
                                        startTime: start,
                                        endTime: end,
                                        filesTransferred: snap.filesTotal,
                                        bytesTransferred: snap.totalBytes,
                                        totalBytes: snap.totalBytes,
                                        wasVerified: verifyMode != .off)
            result.destinationResults = [dest]
            return result
        }
    }
}

enum DemoMode {
    @MainActor
    static func launch() {
        guard let settings = DemoSettings.current else { return }
        if !settings.quickCopySources.isEmpty {
            QuickCopyCoordinator.shared.openDemo(settings)
            return
        }
        guard let config = AppState.shared.selectedConfig else { return }
        TransferViewModel.shared.applyDemoRun(
            configId: config.id,
            sources: config.sourcePaths,
            destinations: config.destinationPaths,
            verifyMode: config.engineOptions.verificationMode,
            settings: settings)
    }
}
#endif
