import Foundation

enum TransferPhase: String {
    case idle      = "Idle"
    case checksumming = "Checksumming"
    case copying   = "Copying"
    case verifying = "Verifying"
    case finished  = "Finished"
}

enum VerificationPhase: String {
    case idle = "Idle"
    case preparingFileList = "Preparing file list"
    case verifying = "Verifying"
    case generatingHashList = "Generating hash list"
    case complete = "Complete"
}

/// Single ObservableObject instance that is reset in-place between transfers.
/// Never recreated — views hold a stable reference and always observe the live state.
class TransferProgress: ObservableObject {

    @Published var isRunning: Bool = false
    @Published var isCancelled: Bool = false
    @Published var isPaused: Bool = false

    // Byte-level progress (most accurate — from rsync per-file progress lines)
    @Published var bytesCompleted: Int64 = 0
    @Published var cumulativeBytes: Int64 = 0  // Total bytes written to destination (for folder-size tracking)
    @Published var totalBytes: Int64 = 0

    // File-count progress (from rsync "to-chk=X/Y" lines)
    @Published var filesCompleted: Int = 0
    @Published var filesTotal: Int = 0

    // Speed and ETA (parsed directly from rsync --progress lines)
    @Published var speedBytesPerSecond: Double = 0
    @Published var estimatedTimeRemaining: TimeInterval? = nil
    @Published var verificationStartTime: Date? = nil
    @Published var verificationEstimatedDuration: TimeInterval? = nil

    // Verification progress tracking
    @Published var verificationFilesCompleted: Int = 0
    @Published var verificationFilesTotal: Int = 0
    @Published var verificationCurrentFile: String = ""
    @Published var verificationPhase: VerificationPhase = .idle
    @Published var verificationBytesCompleted: Int64 = 0
    @Published var verificationBytesTotal: Int64 = 0
    @Published var verificationHasStarted: Bool = false
    @Published var verificationIsActive: Bool = false

    // Source hashing progress (for post-copy verification)
    @Published var sourceHashingFilesCompleted: Int = 0
    @Published var sourceHashingFilesTotal: Int = 0
    @Published var sourceHashingCurrentFile: String = ""
    @Published var sourceHashingActive: Bool = false

    // Phase and completion flag
    @Published var phase: TransferPhase = .idle
    @Published var copyingDone: Bool = false

    // Current file being transferred, and log of completed ones (newest first, capped at 50)
    @Published var currentFile: String = ""
    @Published var completedFiles: [String] = []

    // Error tracking
    @Published var currentError: String? = nil
    @Published var hasError: Bool = false

    /// Prefer byte progress when available (large files), fall back to file count.
    var overallProgress: Double {
        if !isRunning && phase == .finished && !hasError && !isCancelled && !isPaused {
            return 1.0
        }
        return weightedProgress(
            bytesCompleted: cumulativeBytes,
            bytesTotal: totalBytes,
            filesCompleted: filesCompleted,
            filesTotal: filesTotal
        )
    }

    var formattedProgress: String {
        if totalBytes > 0 {
            let progressBytes = cumulativeBytes > 0 ? cumulativeBytes : bytesCompleted
            let done = FilmCanFormatters.bytes(progressBytes, style: .binary)
            let total = FilmCanFormatters.bytes(totalBytes, style: .binary)
            return "\(done) / \(total)"
        }
        // When total is unknown, just show copied bytes
        let progressBytes = cumulativeBytes > 0 ? cumulativeBytes : bytesCompleted
        return FilmCanFormatters.bytes(progressBytes, style: .binary)
    }

    var formattedSpeed: String {
        guard speedBytesPerSecond > 0 else { return "--" }
        return FilmCanFormatters.speed(speedBytesPerSecond, style: .binary)
    }

    var formattedETA: String {
        guard let eta = estimatedTimeRemaining, eta > 0 else { return "--:--" }
        return FilmCanFormatters.durationApprox(eta)
    }

    var verificationProgress: Double {
        guard verificationFilesTotal > 0 else { return 0 }
        return min(1.0, Double(verificationFilesCompleted) / Double(verificationFilesTotal))
    }

    var formattedVerificationProgress: String {
        guard verificationFilesTotal > 0 else { return "--" }
        return "\(verificationFilesCompleted) / \(verificationFilesTotal)"
    }

    var verificationBytesProgress: Double {
        guard verificationBytesTotal > 0 else { return 0 }
        return min(1.0, Double(verificationBytesCompleted) / Double(verificationBytesTotal))
    }

    var verificationWeightedProgress: Double {
        weightedProgress(
            bytesCompleted: verificationBytesCompleted,
            bytesTotal: verificationBytesTotal,
            filesCompleted: verificationFilesCompleted,
            filesTotal: verificationFilesTotal
        )
    }

    private func weightedProgress(
        bytesCompleted: Int64,
        bytesTotal: Int64,
        filesCompleted: Int,
        filesTotal: Int
    ) -> Double {
        let byteProgress = bytesTotal > 0
            ? min(1.0, max(0, Double(bytesCompleted) / Double(bytesTotal)))
            : 0
        let fileProgress = filesTotal > 0
            ? min(1.0, max(0, Double(filesCompleted) / Double(filesTotal)))
            : 0
        if bytesTotal <= 0, filesTotal > 0 {
            return fileProgress
        }
        if filesTotal <= 0 {
            return byteProgress
        }
        let averageFileSize = bytesTotal / Int64(max(filesTotal, 1))
        let fileWeight: Double
        if averageFileSize < 1 * 1024 * 1024 {
            fileWeight = 0.5
        } else if averageFileSize < 10 * 1024 * 1024 {
            fileWeight = 0.3
        } else {
            fileWeight = 0.1
        }
        let combined = (1.0 - fileWeight) * byteProgress + fileWeight * fileProgress
        return min(1.0, max(0, combined))
    }

    var sourceHashingProgress: Double {
        guard sourceHashingFilesTotal > 0 else { return 0 }
        return min(1.0, Double(sourceHashingFilesCompleted) / Double(sourceHashingFilesTotal))
    }

    init() {}

    func resetProgress() {
        isRunning = false
        isCancelled = false
        isPaused = false
        bytesCompleted = 0
        cumulativeBytes = 0
        totalBytes = 0
        filesCompleted = 0
        filesTotal = 0
        speedBytesPerSecond = 0
        estimatedTimeRemaining = nil
        verificationStartTime = nil
        verificationEstimatedDuration = nil
        verificationFilesCompleted = 0
        verificationFilesTotal = 0
        verificationCurrentFile = ""
        verificationPhase = .idle
        verificationBytesCompleted = 0
        verificationBytesTotal = 0
        verificationHasStarted = false
        verificationIsActive = false
        sourceHashingFilesCompleted = 0
        sourceHashingFilesTotal = 0
        sourceHashingCurrentFile = ""
        sourceHashingActive = false
        phase = .idle
        copyingDone = false
        currentFile = ""
        completedFiles = []
        currentError = nil
        hasError = false
    }
}
