import Foundation

extension String {
    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }
    
    var deletingLastPathComponent: String {
        (self as NSString).deletingLastPathComponent
    }
    
    var expandingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}

extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

extension Data {
    var prettyPrintedJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    var hexString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}

enum FilmCanFormatters {
    static func bytes(_ bytes: Int64, style: ByteCountFormatter.CountStyle = .decimal) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: style)
    }

    static func speed(_ bytesPerSecond: Double, style: ByteCountFormatter.CountStyle = .decimal) -> String {
        guard bytesPerSecond > 0 else { return "--" }
        let formatted = bytes(Int64(bytesPerSecond), style: style)
        return "\(formatted)/s"
    }

    static func durationCompact(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%dh %dm %ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    static func durationClock(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    static func durationApprox(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        if total < 45 { return "Less than 1 min" }
        if total < 90 { return "About 1 min" }
        if total < 45 * 60 {
            let mins = Int((Double(total) / 60.0).rounded())
            return "About \(max(1, mins)) min"
        }
        if total < 90 * 60 { return "About 1 hour" }
        let hours = Int((Double(total) / 3600.0).rounded())
        return "About \(max(1, hours)) hours"
    }
}

enum FilmCanPaths {
    static let hidden = ".filmcan"
    static let partial = "\(hidden)/partial"
    static let hashLists = "\(hidden)/hashlists"

    static func hashListPath(for basePath: String) -> String {
        (basePath as NSString).appendingPathComponent(hashLists)
    }

    static func isHidden(_ path: String) -> Bool {
        path.contains("/\(hidden)/")
    }
}

extension FileHandle {
    func readUpToLengthOrThrow(_ length: Int) throws -> Data {
        if #available(macOS 10.15.4, *) {
            guard let data = try self.read(upToCount: length) else {
                throw FileCopyError.readFailed
            }
            return data
        } else {
            let data = self.readData(ofLength: length)
            if data.isEmpty {
                throw FileCopyError.readFailed
            }
            return data
        }
    }
}

extension Notification.Name {
    static let filmCanRestartTour = Notification.Name("FilmCanRestartTour")
    static let filmCanTourNameConfirmed = Notification.Name("FilmCanTourNameConfirmed")
    static let filmCanTourNameSubmitted = Notification.Name("FilmCanTourNameSubmitted")
    static let filmCanHotkeyRunNow = Notification.Name("FilmCanHotkeyRunNow")
    static let filmCanHotkeyAddSource = Notification.Name("FilmCanHotkeyAddSource")
    static let filmCanHotkeyAddDestination = Notification.Name("FilmCanHotkeyAddDestination")
    static let filmCanHotkeyRefreshDrives = Notification.Name("FilmCanHotkeyRefreshDrives")
    static let filmCanDriveListChanged = Notification.Name("FilmCanDriveListChanged")
}

// MARK: - TransferProgress + fan-out

extension TransferProgress {
    func incorporate(_ dest: DestProgress) {
        totalBytes = max(totalBytes, dest.bytesTotal)
        bytesCompleted += dest.bytesCompleted
        filesTotal = max(filesTotal, dest.filesTotal)
        filesCompleted += dest.filesCompleted
        // Track worst status
        switch dest.status {
        case .pending: if currentTask.isEmpty { currentTask = dest.displayName }
        case .active: currentTask = dest.displayName
        case .complete: break
        case .failed: currentTask = "⚠ \(dest.displayName)"
        }
    }
}

// MARK: - DestProgress + DestResult extensions

extension DestProgress {
    var isActive: Bool {
        if case .active = status { return true }
        return false
    }

    var isComplete: Bool {
        if case .complete = status { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var progressFraction: Double {
        guard bytesTotal > 0 else { return 0 }
        return min(Double(bytesCompleted) / Double(bytesTotal), 1.0)
    }

    var speedFormatted: String {
        if speedBytesPerSecond >= 1_000_000_000 {
            return String(format: "%.1f GB/s", speedBytesPerSecond / 1_000_000_000)
        } else if speedBytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", speedBytesPerSecond / 1_000_000)
        } else if speedBytesPerSecond >= 1_000 {
            return String(format: "%.1f KB/s", speedBytesPerSecond / 1_000)
        } else {
            return "\(Int(speedBytesPerSecond)) B/s"
        }
    }
}

extension DestResult {
    var isError: Bool { !success }
    var errorMessage: String { failureReason?.displayMessage ?? "OK" }
    var summaryLine: String {
        let status = success ? "✓" : "✗"
        let bytes = ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
        return "\(status) \(displayName): \(bytes) in \(String(format: "%.1f", durationSec))s"
    }
}
