import Foundation

struct BackupReport: Equatable {
    struct Clip: Equatable {
        var relPath: String
        var absolutePath: String
        var size: Int64
        var checksum: String?
        var checksumAlgorithm: String?
        var isVideo: Bool
        var isAudio: Bool
        /// Why this file shows no checksum (report created after the fact only).
        var note: String? = nil

        var name: String { (relPath as NSString).lastPathComponent }
    }

    struct Roll: Equatable {
        var name: String
        var folderPath: String
        var mediaKind: SourceMediaKind
        var clips: [Clip]
        var totalBytes: Int64 { clips.reduce(0) { $0 + $1.size } }
    }

    var projectName: String
    var episode: String
    var day: String
    var unit: String
    var destinationPath: String
    var destinationVolumeName: String
    var startedAt: Date
    var endedAt: Date
    var success: Bool
    var verified: Bool
    var warning: String?
    var rolls: [Roll]
    var appVersion: String
    /// Set when the report was created after the backup, from what is on the drive.
    var recreated: Recreated? = nil

    /// What a report created after the fact must say about itself.
    struct Recreated: Equatable {
        struct Recheck: Equatable {
            var checked: Int
            var mismatched: Int
        }
        var createdAt: Date
        var hasChecksumList: Bool
        /// In the checksum list, no longer on the drive.
        var missingFiles: [String]
        var sizeChanged: Int
        var notListed: Int
        /// Nil: the files were not re-read.
        var recheck: Recheck?
        /// Checksum lists on the drive that could not be read.
        var unreadableLists: Int = 0

        var hasProblems: Bool {
            !missingFiles.isEmpty || sizeChanged > 0 || (recheck?.mismatched ?? 0) > 0 || unreadableLists > 0
        }

        /// Every file on the drive was re-read and matches the list, and nothing is unaccounted for.
        var isFullyRechecked: Bool {
            hasChecksumList && recheck != nil && !hasProblems && notListed == 0
        }

        /// The status line. Never says "verified": only a backup's own check does.
        var statusText: String {
            var notes: [String] = []
            if !missingFiles.isEmpty { notes.append("\(missingFiles.count) missing") }
            if sizeChanged > 0 { notes.append("\(sizeChanged) changed size") }
            if let recheck, recheck.mismatched > 0 { notes.append("\(recheck.mismatched) do not match") }
            if notListed > 0 { notes.append("\(notListed) not in the list") }
            if unreadableLists > 0 { notes.append("\(unreadableLists) checksum list\(unreadableLists == 1 ? "" : "s") could not be read") }
            guard hasChecksumList else {
                return (["No ASC MHL checksum list on this drive: files listed without checksums, nothing re-read"]
                        + notes.filter { $0.contains("could not be read") }).joined(separator: ". ")
            }
            let lead: String
            if let recheck {
                lead = "Re-checked: \(recheck.checked - recheck.mismatched) of \(recheck.checked) listed files match the checksum list"
            } else {
                lead = "Checksums from the backup's list. Files were not re-read"
            }
            return notes.isEmpty ? lead : lead + ". " + notes.joined(separator: ", ")
        }
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mxf", "avi", "mts", "m2ts", "braw", "r3d", "crm", "ari", "insv", "lrv"]
    static let audioExtensions: Set<String> = ["wav", "bwf", "aif", "aiff", "mp3", "m4a"]

    /// Builds the report for ONE destination result. Lists every file in each roll folder
    /// (what is on the drive, not only this run's copies), skipping hidden components and
    /// the `ascmhl/` directory, sorted by relative path.
    static func build(result: TransferResult, config: BackupConfiguration,
                      appVersion: String) -> BackupReport {
        let dest = result.destinationResults.first
        let rollFolders = dest?.rollFolders ?? [:]
        let destPath = dest?.destinationPath ?? result.destination

        let rolls: [Roll] = rollFolders
            .sorted { $0.value < $1.value }
            .map { rootPath, folder in
                Roll(name: (rootPath as NSString).lastPathComponent,
                     folderPath: folder,
                     mediaKind: config.sourceMediaKinds[rootPath] ?? .camera,
                     clips: clips(inRollFolder: folder))
            }

        let volumeName = (try? URL(fileURLWithPath: destPath)
            .resourceValues(forKeys: [.volumeNameKey]).volumeName)
            ?? (destPath as NSString).lastPathComponent

        return BackupReport(
            projectName: config.name,
            episode: config.episode, day: config.day, unit: config.unit,
            destinationPath: destPath,
            destinationVolumeName: volumeName,
            startedAt: result.startTime,
            endedAt: result.endTime ?? result.startTime,
            success: result.success,
            verified: result.wasVerified,
            warning: result.warningMessage,
            rolls: rolls,
            appVersion: appVersion)
    }

    private static func clips(inRollFolder folder: String) -> [Clip] {
        let root = URL(fileURLWithPath: folder)
        let fm = FileManager.default
        let rootPrefix = root.standardizedFileURL.path + "/"

        var checksums: [String: String] = [:]
        let ascDir = FanOutCopier.ascMHLDir(rollFolder: folder)
        if let name = ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir),
           let entries = try? ASCMHLReader.read(url: ascDir.appendingPathComponent(name)) {
            for e in entries { checksums[e.relPath] = e.hash }
        }

        guard let en = fm.enumerator(at: root,
                                     includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [Clip] = []
        for case let url as URL in en {
            let std = url.standardizedFileURL.path
            guard std.hasPrefix(rootPrefix) else { continue }
            let rel = String(std.dropFirst(rootPrefix.count))
            if rel == "ascmhl" || rel.hasPrefix("ascmhl/") {
                if rel == "ascmhl" { en.skipDescendants() }
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            let sum = checksums[rel]
            out.append(Clip(relPath: rel, absolutePath: std,
                            size: Int64(values?.fileSize ?? 0),
                            checksum: sum,
                            checksumAlgorithm: sum == nil ? nil : "xxh128",
                            isVideo: videoExtensions.contains(ext),
                            isAudio: audioExtensions.contains(ext)))
        }
        return out.sorted { $0.relPath < $1.relPath }
    }
}
