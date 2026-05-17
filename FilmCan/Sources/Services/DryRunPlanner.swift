import Foundation

actor DryRunPlanner {
    func plan(sourcePaths: [String], destinations: [DestWriter.Config]) async throws -> DryRunReport {
        guard !sourcePaths.isEmpty else {
            return DryRunReport(
                sourceName: "(empty)", destinations: [], timestamp: Date(),
                totalBytes: 0, totalFiles: 0,
                memoryPeakBytes: 0, ringCapBytesPerDest: 0, chunkBytes: 0,
                blockingErrors: ["No source paths provided"], warnings: [])
        }
        guard !destinations.isEmpty else {
            return DryRunReport(
                sourceName: sourcePaths.first ?? "", destinations: [], timestamp: Date(),
                totalBytes: 0, totalFiles: 0,
                memoryPeakBytes: 0, ringCapBytesPerDest: 0, chunkBytes: 0,
                blockingErrors: ["No destinations configured"], warnings: [])
        }

        let fm = FileManager.default
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var warnings: [String] = []
        var blockingErrors: [String] = []

        for sourcePath in sourcePaths {
            guard fm.fileExists(atPath: sourcePath) else {
                blockingErrors.append("Source not found: \(sourcePath)")
                continue
            }
        }

        let entries = await FileEnumerator.enumerateFiles(sources: sourcePaths, preset: nil)
        totalBytes = entries.reduce(Int64(0)) { $0 + $1.size }
        totalFiles = entries.count

        let physRam = ProcessInfo.processInfo.physicalMemory
        let ringCap = Constants.ringCapBytesPerDest(physRamBytes: physRam)

        let destInfos = destinations.map { DriveSpeedClassifier.info(for: $0.destPath) }
        let slowest = DriveSpeedClassifier.slowestDestClass(destInfos)
        let chunkSz = Constants.chunkBytes(forSlowestDest: slowest)
        let memoryPeak = UInt64(ringCap) + UInt64(chunkSz) * 4 + 1024 * 1024

        var destReports: [DryRunReport.DestReport] = []

        for dest in destinations {
            let info = DriveSpeedClassifier.info(for: dest.destPath)
            let speed = DriveSpeedClassifier.expectedSpeedMBps(info)
            let fsync = DriveSpeedClassifier.requiresFullFsync(info)
            let cls = DriveSpeedClassifier.slowestDestClass([info])

            let classLabel: String
            switch cls {
            case .nvmeLocal: classLabel = "NVMe"
            case .ssdLocal: classLabel = "SSD"
            case .hdd: classLabel = "HDD"
            case .exfat: classLabel = "exFAT"
            case .network: classLabel = "Network"
            case .unknown: classLabel = "Unknown"
            }

            let url = URL(fileURLWithPath: dest.destPath)
            let freeBytes: Int64
            if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
               let bytes = values.volumeAvailableCapacityForImportantUsage {
                freeBytes = Int64(bytes)
            } else {
                freeBytes = 0
            }

            if freeBytes == 0 {
                blockingErrors.append("Destination unreachable or not mounted: \(dest.displayName)")
            } else {
                let required = Int64(Double(totalBytes) * Constants.freeSpaceHeadroomMultiplier)
                if freeBytes < required {
                    blockingErrors.append("\(dest.displayName): only \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free, needs \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))")
                }
            }

            if info.isExFAT {
                warnings.append("\(dest.displayName): exFAT volume — F_FULLFSYNC will be used. Data loss risk on unsafe eject.")
            }

            let chunkSzDest = Constants.chunkBytes(forSlowestDest: cls)
            let txSec = speed > 0 ? Double(totalBytes) / (speed * 1_000_000) : 0
            let verifySec = dest.verifyMode == .paranoid ? txSec * 1.5 : 0

            let greenImplication: String
            if fsync {
                greenImplication = "F_FULLFSYNC enabled — prevents metadata loss on unsafe eject"
            } else {
                greenImplication = ""
            }

            destReports.append(DryRunReport.DestReport(
                displayName: dest.displayName,
                destPath: dest.destPath,
                estimatedSpeedMBps: speed,
                estimatedTransferSec: txSec,
                estimatedVerifySec: verifySec,
                chunkSize: chunkSzDest,
                requiresFullFsync: fsync,
                classLabel: classLabel,
                greenImplication: greenImplication
            ))
        }

        return DryRunReport(
            sourceName: sourcePaths.first ?? "",
            destinations: destReports,
            timestamp: Date(),
            totalBytes: totalBytes,
            totalFiles: totalFiles,
            memoryPeakBytes: memoryPeak,
            ringCapBytesPerDest: ringCap,
            chunkBytes: chunkSz,
            blockingErrors: blockingErrors,
            warnings: warnings
        )
    }
}
