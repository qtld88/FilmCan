import Foundation

struct DryRunReport: Codable, Identifiable {
    var id: String { "dryrun-\(sourceName)" }
    let sourceName: String
    let destinations: [DestReport]
    let timestamp: Date
    let totalBytes: Int64
    let totalFiles: Int
    let plannedRelPaths: [String]
    let memoryPeakBytes: UInt64
    let ringCapBytesPerDest: Int
    let chunkBytes: Int
    let blockingErrors: [String]
    let warnings: [String]

    init(sourceName: String, destinations: [DestReport], timestamp: Date, totalBytes: Int64, totalFiles: Int, plannedRelPaths: [String] = [], memoryPeakBytes: UInt64, ringCapBytesPerDest: Int, chunkBytes: Int, blockingErrors: [String], warnings: [String]) {
        self.sourceName = sourceName
        self.destinations = destinations
        self.timestamp = timestamp
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
        self.plannedRelPaths = plannedRelPaths
        self.memoryPeakBytes = memoryPeakBytes
        self.ringCapBytesPerDest = ringCapBytesPerDest
        self.chunkBytes = chunkBytes
        self.blockingErrors = blockingErrors
        self.warnings = warnings
    }

    struct DestReport: Codable, Identifiable {
        var id: String { displayName }
        let displayName: String
        let destPath: String
        let estimatedSpeedMBps: Double
        let estimatedTransferSec: TimeInterval
        let estimatedVerifySec: TimeInterval
        var estimatedTotalSec: TimeInterval { estimatedTransferSec + estimatedVerifySec }
        let chunkSize: Int
        let requiresFullFsync: Bool
        let classLabel: String
        let greenImplication: String
    }

    struct SpeedDisparity: Codable, Identifiable {
        var id: String { "\(fastest)-\(slowest)" }
        let fastest: String
        let slowest: String
        let ratio: Double
        let warning: String?
    }

    var speedDisparities: [SpeedDisparity] {
        guard destinations.count >= 2 else { return [] }
        let sorted = destinations.sorted { $0.estimatedSpeedMBps < $1.estimatedSpeedMBps }
        var disparities: [SpeedDisparity] = []
        for i in 0..<(sorted.count - 1) {
            let slow = sorted[i]
            let fast = sorted[i + 1]
            let ratio = fast.estimatedSpeedMBps / max(slow.estimatedSpeedMBps, 1)
            let warn: String? = ratio >= Constants.speedDisparityWarnRatio
                ? "\(slow.displayName) is \(String(format: "%.1f", ratio))× slower than \(fast.displayName). Consider removing slow destinations for this transfer."
                : nil
            disparities.append(SpeedDisparity(
                fastest: fast.displayName,
                slowest: slow.displayName,
                ratio: ratio,
                warning: warn
            ))
        }
        return disparities
    }

    var formattedSummary: String {
        var lines: [String] = [
            "Dry Run: \(sourceName)",
            "─────────────────",
            "Files: \(totalFiles)  Total: \(ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))",
            ""
        ]
        if !warnings.isEmpty {
            lines.append("⚠ Warnings:")
            for w in warnings {
                lines.append("  \(w)")
            }
            lines.append("")
        }
        if !blockingErrors.isEmpty {
            lines.append("✖ Blocking Errors:")
            for e in blockingErrors {
                lines.append("  \(e)")
            }
            lines.append("")
        }
        for dest in destinations {
            let cls = dest.classLabel
            let speed = String(format: "%.0f", dest.estimatedSpeedMBps)
            let sec = String(format: "%.0f", dest.estimatedTotalSec)
            lines.append("  \(dest.displayName) [\(cls) ~\(speed) MB/s] ~\(sec)s")
            if !dest.greenImplication.isEmpty {
                lines.append("    ⚡ \(dest.greenImplication)")
            }
        }
        let disparities = speedDisparities
        if !disparities.isEmpty {
            lines.append("")
            lines.append("⚠ Speed Disparities:")
            for d in disparities {
                if let w = d.warning { lines.append("  \(w)") }
            }
        }
        return lines.joined(separator: "\n")
    }
}
