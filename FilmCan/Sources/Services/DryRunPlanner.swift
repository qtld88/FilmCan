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

        for sourcePath in sourcePaths {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir) else {
                warnings.append("Source not found: \(sourcePath)")
                continue
            }
            if isDir.boolValue {
                guard let enumerator = fm.enumerator(atPath: sourcePath) else {
                    warnings.append("Cannot enumerate: \(sourcePath)")
                    continue
                }
                for case let file as String in enumerator {
                    let fullPath = (sourcePath as NSString).appendingPathComponent(file)
                    if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64 {
                        totalBytes += size
                        totalFiles += 1
                    }
                }
            } else {
                if let attrs = try? fm.attributesOfItem(atPath: sourcePath),
                   let size = attrs[.size] as? Int64 {
                    totalBytes += size
                    totalFiles += 1
                }
            }
        }

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

            if let freeBytes = try? fm.attributesOfFileSystem(forPath: dest.destPath)[.systemFreeSize] as? Int64 {
                let required = Int64(Double(totalBytes) * Constants.freeSpaceHeadroomMultiplier)
                if freeBytes < required {
                    warnings.append("\(dest.displayName): only \(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free, needs \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file))")
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
            blockingErrors: [],
            warnings: warnings
        )
    }
}
