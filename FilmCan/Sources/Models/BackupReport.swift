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
