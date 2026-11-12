import Foundation

/// Builds a backup report after the fact, for a roll of the catalog whose drive is
/// connected. Checksums come from the checksum list already on the drive: they are
/// not recomputed unless the user asks for a re-check, and a file that is not in the
/// list, or whose size no longer matches it, never shows one.
enum ReportRecreation {

    struct Listed: Equatable {
        var hash: String
        var size: Int64
    }

    struct Checksums: Equatable {
        /// Keyed by path relative to the roll folder.
        var byRelPath: [String: Listed] = [:]
        /// Checksum lists in the roll's `ascmhl` folder that could not be read.
        var unreadableLists = 0
        /// A usable checksum list was found on the drive.
        var found: Bool { !byRelPath.isEmpty }
    }

    // MARK: - Where the roll is now

    /// The roll folder as it is reachable now: the drive may be mounted under another
    /// name than at copy time, so the drive is found by its id. Nil when not reachable.
    static func currentRollFolder(copy: CatalogCopy, mountedRootsByUUID: [String: String],
                                  exists: (String) -> Bool) -> String? {
        guard let uuid = copy.destVolumeUUID else {
            return exists(copy.rollFolderPath) ? copy.rollFolderPath : nil
        }
        guard let root = mountedRootsByUUID[uuid] else { return nil }
        let oldRoot = CatalogCopy.volumeRoot(of: copy.rollFolderPath)
        var candidate = copy.rollFolderPath
        if oldRoot != "/", root != oldRoot, candidate == oldRoot || candidate.hasPrefix(oldRoot + "/") {
            candidate = root + String(candidate.dropFirst(oldRoot.count))
        }
        return exists(candidate) ? candidate : nil
    }

    static func mountedRootsByUUID() -> [String: String] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        var out: [String: String] = [:]
        for url in urls {
            if let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
                out[uuid] = url.standardizedFileURL.path
            }
        }
        return out
    }

    // MARK: - Checksum list on the drive

    /// Every ASC MHL generation in the roll's `ascmhl/` folder, oldest first (a later
    /// generation wins for the same file). Only entries that can be stood behind are
    /// kept: an xxh128 checksum with a recorded size. The simple hidden list is not
    /// used: it records no size and is shared by rolls of the same name, so it cannot
    /// prove which file a checksum belongs to.
    static func checksums(rollFolder: String) -> Checksums {
        var out = Checksums()
        let ascDir = FanOutCopier.ascMHLDir(rollFolder: rollFolder)
        func mtime(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let generations = ASCMHLChain.manifestFilesOnDisk(ascmhlDir: ascDir)
            .sorted { $0.seq != $1.seq ? $0.seq < $1.seq : mtime($0.url) < mtime($1.url) }
        for generation in generations {
            guard let entries = try? ASCMHLReader.read(url: generation.url) else {
                out.unreadableLists += 1
                continue
            }
            for entry in entries {
                guard entry.algorithm == "xxh128", let size = entry.size else {
                    // A later entry we cannot use still replaces an earlier one for that file.
                    out.byRelPath.removeValue(forKey: entry.relPath)
                    continue
                }
                out.byRelPath[entry.relPath] = Listed(hash: entry.hash, size: size)
            }
        }
        return out
    }

    // MARK: - The report (pure)

    static let noteNotListed = "Not in the checksum list"
    static let noteSizeChanged = "Size changed since the backup"
    static let noteMismatch = "Does not match the checksum list"

    /// `rechecked`: for a re-check, the checksum read back from each file (relative
    /// path → checksum, nil when the file could not be read). Nil: no re-check.
    /// `existsOnDrive`: for a listed path that is not in `filesOnDisk` (which leaves
    /// hidden files out), whether it is on the drive after all.
    static func build(roll: CatalogRoll, copy: CatalogCopy, rollFolder: String,
                      filesOnDisk: [CatalogFile], checksums: Checksums,
                      rechecked: [String: String?]? = nil,
                      existsOnDrive: (String) -> Bool = { _ in false },
                      now: Date, appVersion: String) -> BackupReport {
        var clips: [BackupReport.Clip] = []
        var sizeChanged = 0, notListed = 0, checked = 0, mismatched = 0
        let onDisk = Set(filesOnDisk.map(\.relPath))

        for file in filesOnDisk.sorted(by: { $0.relPath < $1.relPath }) {
            let ext = (file.relPath as NSString).pathExtension.lowercased()
            var clip = BackupReport.Clip(
                relPath: file.relPath,
                absolutePath: (rollFolder as NSString).appendingPathComponent(file.relPath),
                size: file.size, checksum: nil, checksumAlgorithm: nil,
                isVideo: BackupReport.videoExtensions.contains(ext),
                isAudio: BackupReport.audioExtensions.contains(ext))
            if let listed = checksums.byRelPath[file.relPath] {
                if listed.size != file.size {
                    sizeChanged += 1
                    clip.note = noteSizeChanged
                } else if let rechecked {
                    checked += 1
                    if let actual = rechecked[file.relPath] ?? nil, actual.lowercased() == listed.hash.lowercased() {
                        clip.checksum = listed.hash
                    } else {
                        mismatched += 1
                        clip.note = noteMismatch
                    }
                } else {
                    clip.checksum = listed.hash
                }
            } else if checksums.found {
                notListed += 1
                clip.note = noteNotListed
            }
            if clip.checksum != nil { clip.checksumAlgorithm = "xxh128" }
            clips.append(clip)
        }

        let missing = checksums.byRelPath.keys
            .filter { !onDisk.contains($0) && !existsOnDrive($0) }.sorted()
        let recreated = BackupReport.Recreated(
            createdAt: now, hasChecksumList: checksums.found, missingFiles: missing,
            sizeChanged: sizeChanged, notListed: notListed,
            recheck: rechecked == nil ? nil : .init(checked: checked, mismatched: mismatched),
            unreadableLists: checksums.unreadableLists)

        return BackupReport(
            projectName: roll.projectName, episode: "", day: roll.shootDay, unit: "",
            destinationPath: rollFolder, destinationVolumeName: copy.destVolumeName,
            startedAt: copy.date, endedAt: copy.date,
            success: true,
            // Never "verified": this report was not produced by the backup's own check.
            verified: false,
            warning: nil,
            rolls: [BackupReport.Roll(name: roll.rollName, folderPath: rollFolder,
                                      mediaKind: roll.mediaKind, clips: clips)],
            appVersion: appVersion,
            recreated: recreated)
    }

    /// Re-reads every file that is in the list with an unchanged size. Slow.
    static func recheck(rollFolder: String, filesOnDisk: [CatalogFile], checksums: Checksums) -> [String: String?] {
        var out: [String: String?] = [:]
        for file in filesOnDisk {
            guard let listed = checksums.byRelPath[file.relPath], listed.size == file.size else { continue }
            let url = URL(fileURLWithPath: rollFolder).appendingPathComponent(file.relPath)
            out[file.relPath] = .some(Hashing.hash(for: url, algorithm: .xxh128))
        }
        return out
    }

    // MARK: - Where the PDF goes

    /// In the reports folder on this Mac, next to the copies of the other reports:
    /// `<base>/<film>/<day>/<drive>/<roll>_report_recreated.pdf`.
    static func outputURL(roll: CatalogRoll, copy: CatalogCopy, base: URL) -> URL {
        ReportArchive.folder(base: base, film: roll.projectName, day: roll.shootDay,
                             date: copy.date, drive: copy.destVolumeName)
            .appendingPathComponent(ReportArchive.safeName(roll.rollName, fallback: "roll") + "_report_recreated.pdf")
    }
}
