import Foundation

actor DryRunPlanner {
    func plan(sourcePath: String, destinations: [DestWriter.Config]) async throws -> DryRunReport {
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let attrs = try FileManager.default.attributesOfItem(atPath: sourcePath)
        let totalBytes = (attrs[.size] as? Int64) ?? 0
        let totalFiles = 1

        var destReports: [DryRunReport.DestReport] = []
        let sourceInfo = DriveSpeedClassifier.info(for: sourcePath)

        for dest in destinations {
            let info = DriveSpeedClassifier.info(for: dest.destPath)
            let speed = DriveSpeedClassifier.expectedSpeedMBps(info)
            let fsync = DriveSpeedClassifier.requiresFullFsync(info)
            let cls = DriveSpeedClassifier.slowestDestClass([info, sourceInfo])

            let classLabel: String
            switch cls {
            case .nvmeLocal: classLabel = "NVMe"
            case .ssdLocal: classLabel = "SSD"
            case .hdd: classLabel = "HDD"
            case .exfat: classLabel = "exFAT"
            case .network: classLabel = "Network"
            case .unknown: classLabel = "Unknown"
            }

            let chunkSz = Constants.chunkBytes(forSlowestDest: cls)
            let txSec = speed > 0 ? Double(totalBytes) / (speed * 1_000_000) : 0
            let verifySec = dest.verifyMode == .paranoid ? txSec * 1.5 : 0

            let greenImplication: String
            if fsync {
                greenImplication = "F_FULLFSYNC enabled — reduces throughput but prevents metadata loss"
            } else {
                greenImplication = ""
            }

            destReports.append(DryRunReport.DestReport(
                displayName: dest.displayName,
                destPath: dest.destPath,
                estimatedSpeedMBps: speed,
                estimatedTransferSec: txSec,
                estimatedVerifySec: verifySec,
                chunkSize: chunkSz,
                requiresFullFsync: fsync,
                classLabel: classLabel,
                greenImplication: greenImplication
            ))
        }

        return DryRunReport(
            sourceName: sourceURL.lastPathComponent,
            destinations: destReports,
            timestamp: Date(),
            totalBytes: totalBytes,
            totalFiles: totalFiles
        )
    }
}
