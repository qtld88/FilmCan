import Foundation

// MARK: - Channel payload

struct Chunk: Sendable {
    let data: Data
}

// MARK: - Per-writer result (one per source × destination)

struct DestWriterResult: Sendable {
    let destPath: String
    let displayName: String
    let success: Bool
    let bytesTransferred: Int64
    let filesTransferred: Int
    let durationSec: TimeInterval
    let mhlPath: String?
    let failureReason: DestFailureReason?
    let verifyMode: VerifyMode
    let destHashFromStream: String?
    /// The exact path the file was written to (accounts for organization presets).
    let writtenFilePath: String
    /// The manifest-relative name of the file copied this run (nil unless success).
    /// Used to build a truthful "transferred items" list independent of the
    /// (cumulative) hash list.
    var transferredRelPath: String? = nil
}

// MARK: - Accumulator across sources for one destination

struct DestResultBuilder {
    let destPath: String
    let displayName: String
    let verifyMode: VerifyMode
    var totalBytes: Int64 = 0
    var totalFiles: Int = 0
    var success: Bool = true
    var failures: [DestFailureReason] = []
    var mhlPaths: [String] = []
    var totalDuration: TimeInterval = 0
    var verificationFailed: Bool = false
    /// Names of files actually copied this run (for a truthful transferred-items list).
    var transferredNames: [String] = []

    mutating func incorporate(_ result: DestWriterResult) {
        totalBytes += result.bytesTransferred
        totalFiles += result.filesTransferred
        if !result.success {
            success = false
            if let reason = result.failureReason {
                failures.append(reason)
            }
        }
        if let mhl = result.mhlPath {
            mhlPaths.append(mhl)
        }
        if result.success, let name = result.transferredRelPath {
            transferredNames.append(name)
        }
        totalDuration += result.durationSec
    }

    mutating func markVerificationFailed() {
        success = false
        verificationFailed = true
    }

    func build(skipped: Int = 0) -> DestResult {
        DestResult(
            destinationPath: destPath,
            displayName: displayName,
            success: success && !verificationFailed,
            filesTransferred: totalFiles,
            filesSkipped: skipped,
            filesFailedAfterCopy: verificationFailed ? totalFiles : failures.count,
            bytesTransferred: totalBytes,
            failureReason: verificationFailed ? .verify : failures.first,
            mhlPath: mhlPaths.first,
            durationSec: totalDuration,
            verifyMode: verifyMode,
            transferredFileNames: transferredNames
        )
    }
}

// MARK: - Per-source outcome (returned from concurrent worker)

struct PerSourceOutcome: Sendable {
    let sourcePath: String
    let writerResults: [DestWriterResult]
    let verifyFailedDestPaths: Set<String>
    let sourceCorrupted: Bool
}

/// Result of the copy phase for one source file, handed to the verify lane so
/// verification of file N can run while file N+1 is still being copied.
struct CopyResult: Sendable {
    let sourcePath: String
    let sourceURL: URL
    let sourceName: String
    let chunkSz: Int
    let writerResults: [DestWriterResult]
    let verifiedSourceHash: String
    let cumulativeBytesBeforeSource: Int64
    let sourceSize: Int64
    let sourceIndex: Int
    let totalSources: Int
    let totalBytesAllSources: Int64
    let jobStartTime: Date
    let skippedFiles: Int
    /// The copy was aborted mid-file by the user — skip verification entirely.
    let cancelledEarly: Bool
}

// MARK: - FanOutCopier

actor FanOutCopier {
    struct Configuration: Sendable {
        var sources: [String]
        var destinations: [DestWriter.Config]
        var verifyMode: VerifyMode
        var mhlBasePath: String?
        var dryRun: Bool
        var progressHandler: (@Sendable (DestProgress) -> Void)?
        var organizationPreset: OrganizationPreset?
        var copyFolderContents: Bool = false
        /// Per-shoot metadata for the Netflix folder tokens.
        var shootMetadata: ShootMetadata = .empty
        /// Which hash-list format to write. The Netflix Ingest preset always forces
        /// ASC MHL regardless of this value.
        var hashListStyle: HashListStyle = .ascMHL
        /// Ignore prior hash lists and re-copy every file (disables resume skip).
        var forceRecopy: Bool = false
        /// Polled cooperatively to abort the run when the user hits Stop.
        var shouldCancel: (@Sendable () -> Bool)?
    }

    enum Error: Swift.Error, LocalizedError {
        case sourceNotFound(String)
        case sourceReadFailed(String)
        case noDestinations
        case sourceCorruption(String)
        case insufficientSpace(destPath: String, available: Int64, required: Int64)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let s): return "Source not found: \(s)"
            case .sourceReadFailed(let s): return "Failed to read source: \(s)"
            case .noDestinations: return "No destinations configured"
            case .sourceCorruption(let s):
                return "Source corruption detected during copy — RAM or source drive issue. Retry recommended. (\(s))"
            case .insufficientSpace(let path, let available, let required):
                let dest = (path as NSString).lastPathComponent
                let avMB = available / (1024 * 1024)
                let reqMB = required / (1024 * 1024)
                return "Not enough space on \"\(dest)\" — \(reqMB) MB needed, \(avMB) MB available. Free space before backing up."
            }
        }
    }

    /// One file to copy. `rootPath` is the original source entry the user picked
    /// (file or directory). `relPath` is "" for a flat-file source; otherwise it's
    /// the path inside the root tree, including subdirs.
    private struct PlannedFile {
        let rootPath: String
        let rootName: String
        let absPath: String
        let relPath: String
        let size: Int64
    }

    private var completedFilesByDest: [String: Int] = [:]
    private var verifiedFilesByDest: [String: Int] = [:]
    private var verifiedBytesByDest: [String: Int64] = [:]

    private func recordFileCompletion(destPath: String, totalFiles: Int) -> Bool {
        let next = (completedFilesByDest[destPath] ?? 0) + 1
        completedFilesByDest[destPath] = next
        return next >= totalFiles
    }

    private func recordVerifyCompletion(destPath: String, totalFiles: Int) -> Bool {
        let next = (verifiedFilesByDest[destPath] ?? 0) + 1
        verifiedFilesByDest[destPath] = next
        return next >= totalFiles
    }

    /// Adds `bytes` to the per-dest cumulative verified total and returns the new value.
    private func recordVerifyBytes(destPath: String, adding bytes: Int64) -> Int64 {
        let next = (verifiedBytesByDest[destPath] ?? 0) + bytes
        verifiedBytesByDest[destPath] = next
        return next
    }

    private func verifiedBytesForDest(_ destPath: String) -> Int64 {
        verifiedBytesByDest[destPath] ?? 0
    }

    /// The exact path a planned file is written to at a destination, accounting
    /// for the organization preset and copy-folder-contents. Pure (no I/O); the
    /// caller creates the parent directory when actually writing.
    nonisolated static func resolveDestFilePath(
        destRoot: String, rootName: String, rootPath: String, relPath: String,
        preset: OrganizationPreset?, copyFolderContents: Bool, date: Date,
        metadata: ShootMetadata = .empty
    ) -> String {
        if let preset {
            let resolved = OrganizationTemplate.resolve(
                preset: preset, sourcePath: rootPath, destinationRoot: destRoot,
                counter: 0, date: date, metadata: metadata)
            let folderBase = resolved.folderPath.isEmpty
                ? destRoot
                : (destRoot as NSString).appendingPathComponent(resolved.folderPath)
            if relPath.isEmpty {
                return (folderBase as NSString).appendingPathComponent(resolved.renamedItem)
            } else if copyFolderContents {
                return (folderBase as NSString).appendingPathComponent(relPath)
            } else {
                let named = (folderBase as NSString).appendingPathComponent(resolved.renamedItem)
                return (named as NSString).appendingPathComponent(relPath)
            }
        } else if relPath.isEmpty {
            return (destRoot as NSString).appendingPathComponent(rootName)
        } else if copyFolderContents {
            return (destRoot as NSString).appendingPathComponent(relPath)
        } else {
            let named = (destRoot as NSString).appendingPathComponent(rootName)
            return (named as NSString).appendingPathComponent(relPath)
        }
    }

    /// The destination folder that holds one source root's files (the "roll folder").
    /// The roll's ASC MHL lives at <rollFolder>/ascmhl/0001_<rootName>.mhl, so the roll
    /// folder is the directory directly above ascmhl/ (Netflix "reel = folder above MHL").
    /// For a directory root the resolved root path IS the folder; for a flat-file root
    /// it's a file, so we take its parent directory.
    nonisolated static func resolveRollFolder(
        destRoot: String, rootName: String, rootPath: String,
        isDirectoryRoot: Bool, preset: OrganizationPreset?,
        copyFolderContents: Bool, date: Date, metadata: ShootMetadata = .empty
    ) -> String {
        let resolvedRoot = resolveDestFilePath(
            destRoot: destRoot, rootName: rootName, rootPath: rootPath,
            relPath: "", preset: preset, copyFolderContents: copyFolderContents,
            date: date, metadata: metadata)
        return isDirectoryRoot ? resolvedRoot : (resolvedRoot as NSString).deletingLastPathComponent
    }

    /// The roll's `ascmhl/` folder (holds the generation manifests + chain index).
    nonisolated static func ascMHLDir(rollFolder: String) -> URL {
        URL(fileURLWithPath: rollFolder).appendingPathComponent("ascmhl")
    }

    /// Create Netflix's required sibling folders (`Reports/`, `Sound_Media/`) under the
    /// shoot-day root (the first path component of the roll folder beneath the dest),
    /// so the delivered structure is complete even when only camera media was copied.
    nonisolated static func scaffoldNetflixSiblings(destRoot: String, rollFolder: String) {
        let rel = rollFolder.hasPrefix(destRoot) ? String(rollFolder.dropFirst(destRoot.count)) : rollFolder
        guard let firstComp = rel.split(separator: "/").first.map(String.init), !firstComp.isEmpty else { return }
        let dayRoot = (destRoot as NSString).appendingPathComponent(firstComp)
        for sub in ["Reports", "Sound_Media"] {
            try? FileManager.default.createDirectory(
                at: URL(fileURLWithPath: dayRoot).appendingPathComponent(sub),
                withIntermediateDirectories: true)
        }
    }

    /// (fileName, hash) pairs already recorded for one root at one dest, for resume-skip.
    /// Prefers the ASC MHL at the roll root; falls back to the legacy hidden manifest so
    /// pre-1.3 backups still resume once. `fileName` == the path recorded in the manifest
    /// (relPath for directory roots, basename for flat-file roots).
    nonisolated static func loadExistingMHLEntries(
        destPath: String, rootName: String, rollFolder: String
    ) -> [(fileName: String, hash: String, size: Int64)] {
        let ascDir = ascMHLDir(rollFolder: rollFolder)
        if let latest = ASCMHLChain.latestManifestPath(ascmhlDir: ascDir),
           let entries = try? ASCMHLReader.read(url: ascDir.appendingPathComponent(latest)) {
            return entries.map { (fileName: $0.relPath, hash: $0.hash, size: $0.size ?? 0) }
        }
        let legacy = URL(fileURLWithPath: destPath)
            .appendingPathComponent(".filmcan").appendingPathComponent("hashlists")
            .appendingPathComponent("\(rootName).mhl")
        if FileManager.default.fileExists(atPath: legacy.path),
           let data = try? Data(contentsOf: legacy) {
            return Self.parseLegacyMHL(data)
        }
        return []
    }

    /// Minimal parser for the old <file name=".."><hash>..</hash></file> format.
    /// (The legacy format carried no size, so size is reported as 0.)
    nonisolated private static func parseLegacyMHL(_ data: Data) -> [(fileName: String, hash: String, size: Int64)] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var out: [(String, String, Int64)] = []
        let ns = xml as NSString
        let pattern = #"<file name=\"(.*?)\"><hash>(.*?)</hash></file>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        re.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            let name = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
            let hash = ns.substring(with: m.range(at: 2))
            out.append((name, hash, 0))
        }
        return out
    }

    private func buildSharedMHLs(
        forRootNames rootNames: Set<String>,
        directoryRoots: Set<String>,
        rootPaths: [String: String],
        jobStartTime: Date
    ) throws -> [String: [String: any MHLWriting]] {
        // Netflix delivery always needs ASC MHL; otherwise honor the config style.
        let isNetflix = config.organizationPreset?.name == OrganizationPreset.netflixIngestName
        let style: HashListStyle = isNetflix ? .ascMHL : config.hashListStyle
        var result: [String: [String: any MHLWriting]] = [:]
        for destCfg in config.destinations {
            var byRoot: [String: any MHLWriting] = [:]
            for rootName in rootNames {
                let writer: any MHLWriting
                switch style {
                case .ascMHL:
                    let rollFolder = Self.resolveRollFolder(
                        destRoot: destCfg.destPath, rootName: rootName,
                        rootPath: rootPaths[rootName] ?? rootName,
                        isDirectoryRoot: directoryRoots.contains(rootName),
                        preset: config.organizationPreset,
                        copyFolderContents: config.copyFolderContents, date: jobStartTime, metadata: config.shootMetadata)
                    if isNetflix {
                        Self.scaffoldNetflixSiblings(destRoot: destCfg.destPath, rollFolder: rollFolder)
                    }
                    let ascDir = Self.ascMHLDir(rollFolder: rollFolder)
                    writer = try ASCMHLWriter(ascmhlDir: ascDir, rollName: rootName)
                case .simpleHidden:
                    writer = try SimpleMHLWriter(destRoot: destCfg.destPath, rollName: rootName)
                }
                byRoot[rootName] = writer
            }
            result[destCfg.destPath] = byRoot
        }
        return result
    }

    nonisolated let config: Configuration

    init(config: Configuration) {
        self.config = config
    }

    /// Run the fan-out copy. Sources from distinct drives are processed
    /// concurrently (one worker per source drive); sources from the same
    /// drive are processed sequentially within their drive's worker.
    func run() async throws -> [DestResult] {
        guard !config.destinations.isEmpty else { throw Error.noDestinations }
        guard !config.sources.isEmpty else { throw Error.sourceNotFound("(empty)") }


        completedFilesByDest.removeAll()
        verifiedFilesByDest.removeAll()
        verifiedBytesByDest.removeAll()
        copyDoneByDest.removeAll()
        combinedSamplesByDest.removeAll()
        etaEmitByDest.removeAll()

        let destURLs = config.destinations.map { URL(fileURLWithPath: $0.destPath) }
        await OrphanCleaner.shared.cleanOrphans(at: destURLs)

        let destInfos = config.destinations.map { DriveSpeedClassifier.info(for: $0.destPath) }
        let slowest = DriveSpeedClassifier.slowestDestClass(destInfos)
        let chunkSz = Constants.chunkBytes(forSlowestDest: slowest)
        let ringCapBytes = Constants.ringCapBytesPerDest()
        let channelCapacity = max(2, ringCapBytes / max(1, chunkSz))

        // Validate roots up-front so caller gets a clear sourceNotFound error.
        let fmPre = FileManager.default
        for path in config.sources {
            guard fmPre.fileExists(atPath: path) else {
                throw Error.sourceNotFound(path)
            }
        }

        // Expand every source root into its constituent files. A flat-file root
        // yields one PlannedFile with relPath == "" and rootName == basename.
        // A directory root yields one PlannedFile per regular file under it.
        let entries = await FileEnumerator.enumerateFiles(sources: config.sources, preset: config.organizationPreset)
        guard !entries.isEmpty else {
            throw Error.sourceReadFailed(config.sources.first ?? "")
        }

        let allPlannedFiles: [PlannedFile] = entries.map { entry in
            let rootName = (entry.sourceRoot as NSString).lastPathComponent
            return PlannedFile(
                rootPath: entry.sourceRoot,
                rootName: rootName,
                absPath: entry.sourcePath,
                relPath: entry.sourceIsDirectory ? entry.relativePath : "",
                size: entry.size
            )
        }

        var builders: [String: DestResultBuilder] = [:]
        for dest in config.destinations {
            builders[dest.destPath] = DestResultBuilder(
                destPath: dest.destPath,
                displayName: dest.displayName,
                verifyMode: dest.verifyMode
            )
        }

        // Wall-clock start, also used as the date for organization-template path
        // resolution so the resume presence-check and the actual copy agree.
        let jobStartTime = Date()

        // Resume skip: a file already recorded in EVERY destination's hash list
        // AND still present on disk there is not recopied. The MHL lives at
        // <dest>/.filmcan/hashlists/<rootName>.mhl — a stable, date-independent
        // location. The presence check re-copies a file that was recorded but is
        // missing (e.g. deleted by the user). `forceRecopy` skips all of this.
        let allRootNames = Set(allPlannedFiles.map { $0.rootName })
        let directoryRoots: Set<String> = Set(allPlannedFiles.filter { !$0.relPath.isEmpty }.map { $0.rootName })
        func rootPath(for rootName: String) -> String {
            allPlannedFiles.first(where: { $0.rootName == rootName })?.rootPath ?? rootName
        }
        var existingMHLByDest: [String: [String: [(fileName: String, hash: String, size: Int64)]]] = [:]
        for dest in config.destinations {
            var byRoot: [String: [(fileName: String, hash: String, size: Int64)]] = [:]
            for root in allRootNames {
                let rf = Self.resolveRollFolder(
                    destRoot: dest.destPath, rootName: root, rootPath: rootPath(for: root),
                    isDirectoryRoot: directoryRoots.contains(root),
                    preset: config.organizationPreset, copyFolderContents: config.copyFolderContents,
                    date: jobStartTime, metadata: config.shootMetadata)
                byRoot[root] = Self.loadExistingMHLEntries(destPath: dest.destPath, rootName: root, rollFolder: rf)
            }
            existingMHLByDest[dest.destPath] = byRoot
        }
        func plannedSourceName(_ f: PlannedFile) -> String {
            f.relPath.isEmpty ? (f.absPath as NSString).lastPathComponent : f.relPath
        }
        var skippedFiles = 0
        let plannedFiles: [PlannedFile] = config.forceRecopy ? allPlannedFiles : allPlannedFiles.filter { f in
            let name = plannedSourceName(f)
            let doneEverywhere = config.destinations.allSatisfy { dest in
                guard existingMHLByDest[dest.destPath]?[f.rootName]?.contains(where: { $0.fileName == name }) == true else { return false }
                // Quick presence check: the recorded file must still exist.
                let path = Self.resolveDestFilePath(
                    destRoot: dest.destPath, rootName: f.rootName, rootPath: f.rootPath,
                    relPath: f.relPath, preset: config.organizationPreset,
                    copyFolderContents: config.copyFolderContents, date: jobStartTime,
                    metadata: config.shootMetadata)
                return FileManager.default.fileExists(atPath: path)
            }
            if doneEverywhere { skippedFiles += 1; return false }
            return true
        }

        // Everything already backed up to every destination — nothing to copy.
        guard !plannedFiles.isEmpty else {
            return config.destinations.compactMap { builders[$0.destPath]?.build(skipped: skippedFiles) }
        }

        let totalBytesAllSources = plannedFiles.reduce(Int64(0)) { $0 + $1.size }

        // Pre-flight: ensure every destination has enough free space before we start.
        // Use live statfs free space (not the cached ImportantUsage metric) so a
        // drive the user just cleared isn't falsely reported as full.
        for dest in config.destinations {
            if let available = DriveUtilities.liveAvailableBytes(for: dest.destPath),
               available < totalBytesAllSources {
                throw Error.insufficientSpace(
                    destPath: dest.destPath,
                    available: available,
                    required: totalBytesAllSources
                )
            }
        }

        // Pre-compute cumulative bytes before each planned file.
        var cumulativeBeforeFile: [Int64] = []
        cumulativeBeforeFile.reserveCapacity(plannedFiles.count)
        var runningBytes: Int64 = 0
        for f in plannedFiles {
            cumulativeBeforeFile.append(runningBytes)
            runningBytes += f.size
        }
        let totalFiles = plannedFiles.count

        // Build all shared MHL writers upfront, grouped by dest and rootName.
        // Seed each with the destination's existing entries so a resumed run
        // appends to its hash list instead of truncating already-recorded files.
        let uniqueRootNames = Set(plannedFiles.map { $0.rootName })
        var rootPathsByName: [String: String] = [:]
        for f in allPlannedFiles where rootPathsByName[f.rootName] == nil { rootPathsByName[f.rootName] = f.rootPath }
        let sharedMHLsByDest = try buildSharedMHLs(
            forRootNames: uniqueRootNames,
            directoryRoots: directoryRoots,
            rootPaths: rootPathsByName,
            jobStartTime: jobStartTime)
        // Seed each writer with the destination's prior entries so a resumed run
        // appends rather than truncating. Carry the real file size (not 0), and
        // only carry forward an entry whose file STILL EXISTS at the destination —
        // a file deleted out-of-band must not stay certified in the manifest.
        for (destPath, byRoot) in sharedMHLsByDest {
            for (rootName, writer) in byRoot {
                guard let existing = existingMHLByDest[destPath]?[rootName], !existing.isEmpty else { continue }
                let isDir = directoryRoots.contains(rootName)
                let rp = rootPathsByName[rootName] ?? rootName
                let present = existing.filter { entry in
                    let destFile = Self.resolveDestFilePath(
                        destRoot: destPath, rootName: rootName, rootPath: rp,
                        relPath: isDir ? entry.fileName : "",
                        preset: config.organizationPreset,
                        copyFolderContents: config.copyFolderContents,
                        date: jobStartTime, metadata: config.shootMetadata)
                    return FileManager.default.fileExists(atPath: destFile)
                }
                if !present.isEmpty {
                    await writer.seed(present.map { MHLEntry(relPath: $0.fileName, size: $0.size, hash: $0.hash) })
                }
            }
        }

        // Concurrency: cap by number of distinct source drives so we don't oversubscribe a single bus.
        let sourceConcurrency = max(1, distinctSourceDriveCount(forPaths: config.sources))

        // Pipeline: the copy task group produces CopyResults; a single verify
        // lane (drainVerifies) consumes them, so file N is verified while file
        // N+1 is still copying. The lane is serial → the verify bar stays
        // monotonic.
        let verifyChannel = BoundedChannel<CopyResult>(capacity: 64)
        async let verifyOutcomes: [PerSourceOutcome] = drainVerifies(verifyChannel)

        var copyError: (any Swift.Error)?
        do {
            try await withThrowingTaskGroup(of: CopyResult.self) { group in
                var iter = plannedFiles.enumerated().makeIterator()
                var inFlight = 0

                func enqueueNext() -> Bool {
                    // Stop starting new files once the user cancels.
                    if config.shouldCancel?() == true { return false }
                    guard let (index, file) = iter.next() else { return false }
                    let absURL = URL(fileURLWithPath: file.absPath)
                    let cumBefore = cumulativeBeforeFile[index]
                    group.addTask { [self] in
                        try await copySource(
                            sourceURL: absURL,
                            sourceName: file.relPath.isEmpty ? (file.absPath as NSString).lastPathComponent : file.relPath,
                            sourceSize: file.size,
                            cumulativeBytesBeforeSource: cumBefore,
                            totalBytesAllSources: totalBytesAllSources,
                            sourceIndex: index,
                            totalSources: totalFiles,
                            channelCapacity: channelCapacity,
                            chunkSz: chunkSz,
                            rootName: file.rootName,
                            rootPath: file.rootPath,
                            relPath: file.relPath,
                            sharedMHLsByDest: sharedMHLsByDest,
                            jobStartTime: jobStartTime,
                            skippedFiles: skippedFiles
                        )
                    }
                    inFlight += 1
                    return true
                }

                for _ in 0..<min(sourceConcurrency, plannedFiles.count) {
                    _ = enqueueNext()
                }

                while inFlight > 0 {
                    guard let copyResult = try await group.next() else { break }
                    inFlight -= 1
                    try? await verifyChannel.send(copyResult)
                    _ = enqueueNext()
                }
            }
        } catch {
            copyError = error
        }

        // Always close the lane and drain it, whether copy succeeded or threw,
        // so the consumer task can't deadlock on a pending receive.
        await verifyChannel.finish()
        let outcomes = await verifyOutcomes
        if let copyError { throw copyError }

        if let corrupt = outcomes.first(where: { $0.sourceCorrupted }) {
            throw Error.sourceCorruption(corrupt.sourcePath)
        }

        for outcome in outcomes {
            for w in outcome.writerResults {
                builders[w.destPath]?.incorporate(w)
            }
            for dp in outcome.verifyFailedDestPaths {
                builders[dp]?.markVerificationFailed()
            }
        }

        // Finalize each shared MHL. A cancelled run writes a PARTIAL manifest (no
        // chain entry) so it never certifies an interrupted generation; a clean run
        // seals and records the generation in the chain.
        let wasCancelled = config.shouldCancel?() == true
        for destMHLs in sharedMHLsByDest.values {
            for writer in destMHLs.values {
                if wasCancelled {
                    try? await writer.finalizeAsPartial(reason: "Run cancelled or failed before completion")
                } else {
                    try? await writer.seal()
                }
            }
        }

        return config.destinations.compactMap { builders[$0.destPath]?.build(skipped: skippedFiles) }
    }

    /// Single serial verify lane: pulls copied files in order and verifies each,
    /// running concurrently with the copy of later files.
    private func drainVerifies(_ channel: BoundedChannel<CopyResult>) async -> [PerSourceOutcome] {
        var out: [PerSourceOutcome] = []
        var it = channel.makeAsyncIterator()
        while let copyResult = try? await it.next() {
            out.append(await verifySource(copyResult))
        }
        return out
    }

    /// Source concurrency: one worker per distinct source drive, capped at sources.count.
    /// Multi-card backup → parallel. Single-card with many files → sequential
    /// (would otherwise thrash the card head).
    nonisolated private func maxConcurrentSources() -> Int {
        let driveIds = Set(config.sources.map { DriveUtilities.driveId(for: $0) })
        return max(1, min(driveIds.count, config.sources.count))
    }

    /// Distinguish source paths by their volume UUID (falling back to path)
    /// so files on the same physical drive get the same concurrency slot.
    private nonisolated func distinctSourceDriveCount(forPaths paths: [String]) -> Int {
        var seen: Set<String> = []
        for p in paths {
            let info = DriveSpeedClassifier.info(for: p)
            let key = info.volumeUUID ?? p
            seen.insert(key)
        }
        return max(1, seen.count)
    }

    /// Copy phase for one source file: read sequentially (cached, with readahead),
    /// spawn per-dest writer tasks, broadcast chunks through bounded channels.
    /// Verification is performed separately in `verifySource` so it can overlap
    /// the next file's copy.
    /// cumulativeBytesBeforeSource is the sum of all earlier source sizes for correct progress tracking.
    /// totalBytesAllSources is the sum of ALL source sizes (full job).
    nonisolated private func copySource(
        sourceURL: URL,
        sourceName: String,
        sourceSize: Int64,
        cumulativeBytesBeforeSource: Int64,
        totalBytesAllSources: Int64,
        sourceIndex: Int,
        totalSources: Int,
        channelCapacity: Int,
        chunkSz: Int,
        rootName: String,
        rootPath: String,
        relPath: String,
        sharedMHLsByDest: [String: [String: any MHLWriting]],
        jobStartTime: Date,
        skippedFiles: Int
    ) async throws -> CopyResult {
        let sourcePath = sourceURL.path

        var channels: [String: BoundedChannel<Chunk>] = [:]
        for dest in config.destinations {
            channels[dest.destPath] = BoundedChannel<Chunk>(capacity: channelCapacity)
        }

        var writerTasks: [Task<DestWriterResult, Never>] = []

        for destCfg in config.destinations {
            let channel = channels[destCfg.destPath]!
            let targetPath = Self.resolveDestFilePath(
                destRoot: destCfg.destPath, rootName: rootName, rootPath: rootPath,
                relPath: relPath, preset: config.organizationPreset,
                copyFolderContents: config.copyFolderContents, date: jobStartTime,
                metadata: config.shootMetadata)
            let parent = (targetPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
            let destFileURL = URL(fileURLWithPath: targetPath)
            let progressHandler = config.progressHandler

            let task = Task<DestWriterResult, Never> {
                let startTime = Date()
                var totalBytes: Int64 = 0
                var writeFailed: DestFailureReason? = nil
                // Throttle copy-phase progress emits to ~10/s. Emitting per 8MB
                // chunk spawned thousands of progress Tasks per file, flooding the
                // main thread. The per-file copy-done emit below is always sent.
                var lastEmit = Date.distantPast
                // Snapshot verified bytes at the start of this source so copy-phase
                // progress emits keep the verify bar frozen at the right position.
                let verifiedAtStart = await self.verifiedBytesForDest(destCfg.destPath)

                guard let destHasher = XXH128StreamingHasher() else {
                    await channel.finish()
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: 0, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .ioError("xxhash unavailable"),
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil,
                        writtenFilePath: destFileURL.path
                    )
                }

                let writer: DestWriter
                do {
                    let sharedMHL = sharedMHLsByDest[destCfg.destPath]?[rootName]
                    writer = try await DestWriter(
                        destPath: destFileURL.path,
                        displayName: destCfg.displayName,
                        verifyMode: destCfg.verifyMode,
                        requiresFullFsync: destCfg.requiresFullFsync,
                        sharedMHLWriter: sharedMHL
                    )
                } catch {
                    await channel.finish()
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: 0, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .ioError(error.localizedDescription),
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil,
                        writtenFilePath: destFileURL.path
                    )
                }

                do {
                    for try await chunk in channel {
                        if writeFailed == nil {
                            do {
                                try await writer.write(data: chunk.data)
                                destHasher.update(data: chunk.data)
                                totalBytes += Int64(chunk.data.count)

                                let now = Date()
                                if now.timeIntervalSince(lastEmit) >= 0.1 {
                                    lastEmit = now
                                    var prog = DestProgress(
                                        id: destCfg.destPath, displayName: destCfg.displayName,
                                        status: .active, bytesTotal: totalBytesAllSources,
                                        filesTotal: totalSources, verifyMode: destCfg.verifyMode
                                    )
                                    let paranoid = destCfg.verifyMode == .paranoid
                                    prog.bytesCompleted = cumulativeBytesBeforeSource + totalBytes
                                    prog.filesCompleted = sourceIndex
                                    prog.currentFile = sourceName
                                    prog.verifyBytesTotal = paranoid ? totalBytesAllSources : 0
                                    prog.verifyBytesCompleted = verifiedAtStart
                                    let se = await self.combinedThroughputETA(
                                        destPath: destCfg.destPath,
                                        copyDoneNow: prog.bytesCompleted,
                                        copyTotal: totalBytesAllSources,
                                        paranoid: paranoid,
                                        jobStart: jobStartTime)
                                    prog.speedBytesPerSecond = se.speed
                                    prog.estimatedTimeRemaining = se.eta
                                    prog.filesSkipped = skippedFiles
                                    progressHandler?(prog)
                                }
                            } catch {
                                writeFailed = .ioError(error.localizedDescription)
                                await channel.finish()
                            }
                        }
                    }
                } catch {
                    // Channel finished — expected termination
                }

                // User cancel: return before finalize so the temp file is never
                // renamed to its final path. DestWriter.deinit removes the temp.
                if config.shouldCancel?() == true {
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: totalBytes, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .userCancel,
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil,
                        writtenFilePath: destFileURL.path
                    )
                }

                if let reason = writeFailed {
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: totalBytes, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: reason,
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil,
                        writtenFilePath: destFileURL.path
                    )
                }

                let destHash = destHasher.finalize().hexString
                do {
                    try await writer.finalize(fileHash: destHash, sourceSize: sourceSize)
                    try await writer.appendMHL(hash: destHash, fileName: sourceName, size: sourceSize)
                } catch {
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: totalBytes, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .ioError(error.localizedDescription),
                        verifyMode: destCfg.verifyMode, destHashFromStream: destHash,
                        writtenFilePath: destFileURL.path
                    )
                }

                let duration = Date().timeIntervalSince(startTime)
                let isLastFile = await self.recordFileCompletion(destPath: destCfg.destPath, totalFiles: totalSources)
                let copyStatus: DestStatus = isLastFile ? .complete : .active
                var prog = DestProgress(
                    id: destCfg.destPath, displayName: destCfg.displayName,
                    status: copyStatus, bytesTotal: totalBytesAllSources,
                    filesTotal: totalSources, verifyMode: destCfg.verifyMode
                )
                let paranoidDone = destCfg.verifyMode == .paranoid
                prog.bytesCompleted = cumulativeBytesBeforeSource + totalBytes
                prog.filesCompleted = sourceIndex + 1
                prog.currentFile = sourceName
                prog.verifyBytesTotal = paranoidDone ? totalBytesAllSources : 0
                prog.verifyBytesCompleted = verifiedAtStart
                let se = await self.combinedThroughputETA(
                    destPath: destCfg.destPath,
                    copyDoneNow: prog.bytesCompleted,
                    copyTotal: totalBytesAllSources,
                    paranoid: paranoidDone,
                    jobStart: jobStartTime)
                prog.speedBytesPerSecond = se.speed
                prog.estimatedTimeRemaining = se.eta
                prog.filesSkipped = skippedFiles
                progressHandler?(prog)

                let mhlPath = sharedMHLsByDest[destCfg.destPath]?[rootName]?.manifestPath ?? ""

                return DestWriterResult(
                    destPath: destCfg.destPath, displayName: destCfg.displayName,
                    success: true, bytesTransferred: totalBytes, filesTransferred: 1,
                    durationSec: duration, mhlPath: mhlPath,
                    failureReason: nil, verifyMode: destCfg.verifyMode,
                    destHashFromStream: destHash,
                    writtenFilePath: destFileURL.path,
                    transferredRelPath: sourceName
                )
            }
            writerTasks.append(task)
        }

        var sourceHash: String?
        var sourceError: (any Swift.Error)?
        var deadDests: Set<String> = []
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            // F_NOCACHE: the source is read once and never re-read on this path
            // (paranoid verify uses its own handle), so caching it is pure waste —
            // without this, copying a multi-hundred-GB source fills the unified
            // buffer cache with data we never touch again, driving system memory
            // pressure (observed: >30 GB, system crash). The kernel still does
            // some prefetch on the descriptor; sequential throughput stays high.
            _ = fcntl(sourceHandle.fileDescriptor, F_NOCACHE, 1)
            defer { try? sourceHandle.close() }

            guard let sourceHasher = XXH128StreamingHasher() else {
                throw Error.sourceReadFailed("xxhash unavailable for \(sourcePath)")
            }

            while true {
                // User cancel: stop reading; channels are finished below so the
                // writer tasks drain and abort before finalizing (no partial file).
                if config.shouldCancel?() == true { break }
                let chunkData: Data
                if #available(macOS 10.15.4, *) {
                    guard let data = try sourceHandle.read(upToCount: chunkSz), !data.isEmpty
                    else { break }
                    chunkData = data
                } else {
                    let data = sourceHandle.readData(ofLength: chunkSz)
                    if data.isEmpty { break }
                    chunkData = data
                }
                sourceHasher.update(data: chunkData)

                let chunk = Chunk(data: chunkData)
                for (destPath, channel) in channels where !deadDests.contains(destPath) {
                    do {
                        try await channel.send(chunk)
                    } catch {
                        deadDests.insert(destPath)
                    }
                }
                if deadDests.count == channels.count { break }
            }
            sourceHash = sourceHasher.finalize().hexString
        } catch {
            sourceError = error
        }

        for channel in channels.values { await channel.finish() }

        var writerResults: [DestWriterResult] = []
        for task in writerTasks {
            writerResults.append(await task.value)
        }

        if let sourceError { throw sourceError }
        guard let verifiedSourceHash = sourceHash else {
            throw Error.sourceReadFailed(sourcePath)
        }

        return CopyResult(
            sourcePath: sourcePath,
            sourceURL: sourceURL,
            sourceName: sourceName,
            chunkSz: chunkSz,
            writerResults: writerResults,
            verifiedSourceHash: verifiedSourceHash,
            cumulativeBytesBeforeSource: cumulativeBytesBeforeSource,
            sourceSize: sourceSize,
            sourceIndex: sourceIndex,
            totalSources: totalSources,
            totalBytesAllSources: totalBytesAllSources,
            jobStartTime: jobStartTime,
            skippedFiles: skippedFiles,
            cancelledEarly: config.shouldCancel?() == true
        )
    }

    /// Verify one already-copied file. Runs on a single serial lane concurrently
    /// with the copy of later files, so paranoid re-reads don't block copying.
    nonisolated private func verifySource(_ c: CopyResult) async -> PerSourceOutcome {
        let fm = FileManager.default
        let successDests = c.writerResults.filter { $0.success }.map { $0.destPath }

        // Emit a terminal failed(.userCancel) for each in-progress destination so
        // the UI shows red crosses and the live pills/ETA stop. Returns the dest
        // set marked as failed so the per-dest result is not a success.
        func emitCancelled() async -> Set<String> {
            for r in c.writerResults where r.success {
                var prog = DestProgress(
                    id: r.destPath, displayName: (r.destPath as NSString).lastPathComponent,
                    status: .failed(.userCancel), bytesTotal: c.totalBytesAllSources,
                    filesTotal: c.totalSources, verifyMode: c.writerResults.first?.verifyMode ?? .paranoid
                )
                prog.bytesCompleted = c.cumulativeBytesBeforeSource + c.sourceSize
                prog.filesCompleted = c.sourceIndex + 1
                prog.verifyBytesTotal = c.totalBytesAllSources
                prog.verifyBytesCompleted = await self.verifiedBytesForDest(r.destPath)
                prog.currentFile = "Cancelled"
                config.progressHandler?(prog)
            }
            return Set(successDests)
        }

        // Cancelled before or during verification: mark cancelled, don't verify.
        if c.cancelledEarly || config.shouldCancel?() == true {
            let cancelled = await emitCancelled()
            return PerSourceOutcome(
                sourcePath: c.sourcePath, writerResults: c.writerResults,
                verifyFailedDestPaths: cancelled, sourceCorrupted: false
            )
        }

        // Verification disabled: copy only, no checks.
        if config.verifyMode == .off {
            return PerSourceOutcome(
                sourcePath: c.sourcePath, writerResults: c.writerResults,
                verifyFailedDestPaths: [], sourceCorrupted: false
            )
        }

        // Fast + paranoid both compare the streamed dest hash to the source.
        var verifyFailed: Set<String> = []
        for r in c.writerResults where r.success {
            if let dh = r.destHashFromStream, dh != c.verifiedSourceHash {
                verifyFailed.insert(r.destPath)
                try? fm.removeItem(atPath: r.writtenFilePath)
            }
        }

        guard config.verifyMode == .paranoid else {
            return PerSourceOutcome(
                sourcePath: c.sourcePath, writerResults: c.writerResults,
                verifyFailedDestPaths: verifyFailed, sourceCorrupted: false
            )
        }

        // Give drives that don't reliably honor F_FULLFSYNC time to flush their
        // write cache before the paranoid re-read. Without this, the re-read can
        // return stale data and produce a false hash mismatch.
        let hasFullFsyncDest = config.destinations.contains { $0.requiresFullFsync }
        if hasFullFsyncDest {
            try? await Task.sleep(for: .seconds(1))
        }

        // Cancel can land during the settle delay.
        if config.shouldCancel?() == true {
            let cancelled = await emitCancelled()
            return PerSourceOutcome(
                sourcePath: c.sourcePath, writerResults: c.writerResults,
                verifyFailedDestPaths: verifyFailed.union(cancelled), sourceCorrupted: false
            )
        }

        // Emit verify-start progress for each successful destination.
        for r in c.writerResults where r.success {
            var prog = DestProgress(
                id: r.destPath, displayName: (r.destPath as NSString).lastPathComponent,
                status: .active, bytesTotal: c.totalBytesAllSources,
                filesTotal: c.totalSources, verifyMode: .paranoid
            )
            prog.bytesCompleted = c.cumulativeBytesBeforeSource + c.sourceSize
            prog.filesCompleted = c.sourceIndex + 1
            prog.verifyBytesTotal = c.totalBytesAllSources
            prog.verifyBytesCompleted = await self.verifiedBytesForDest(r.destPath)
            prog.currentFile = "Verifying \(c.sourceName)…"
            let se = await self.combinedThroughputETA(
                destPath: r.destPath, copyDoneNow: nil,
                copyTotal: c.totalBytesAllSources, paranoid: true, jobStart: c.jobStartTime)
            prog.speedBytesPerSecond = se.speed
            prog.estimatedTimeRemaining = se.eta
            prog.filesSkipped = c.skippedFiles
            config.progressHandler?(prog)
        }

        var corrupted = false
        let sourceHashFromDisk = await rereadHash(url: c.sourceURL, chunkSz: c.chunkSz)
        if let diskHash = sourceHashFromDisk, diskHash != c.verifiedSourceHash {
            corrupted = true
            for r in c.writerResults where r.success {
                try? fm.removeItem(atPath: r.writtenFilePath)
                verifyFailed.insert(r.destPath)
            }
        } else {
            let writtenPathByDest: [String: String] = Dictionary(
                uniqueKeysWithValues: c.writerResults.map { ($0.destPath, $0.writtenFilePath) }
            )
            await withTaskGroup(of: (String, String?).self) { group in
                for r in c.writerResults where r.success && !verifyFailed.contains(r.destPath) {
                    let destFileURL = URL(fileURLWithPath: r.writtenFilePath)
                    let destPath = r.destPath
                    group.addTask {
                        let hash = await Self.rereadHashDetached(url: destFileURL, chunkSz: c.chunkSz)
                        return (destPath, hash)
                    }
                }
                for await (destPath, hash) in group {
                    let hashMatchesExpected = hash == c.verifiedSourceHash
                    if let h = hash, h != c.verifiedSourceHash {
                        verifyFailed.insert(destPath)
                        if let wp = writtenPathByDest[destPath] { try? fm.removeItem(atPath: wp) }
                    } else if hash == nil {
                        verifyFailed.insert(destPath)
                    }
                    let verifyDestStatus: DestStatus
                    let newVerifiedBytes: Int64
                    if hashMatchesExpected {
                        let isLastVerify = await self.recordVerifyCompletion(destPath: destPath, totalFiles: c.totalSources)
                        newVerifiedBytes = await self.recordVerifyBytes(destPath: destPath, adding: c.sourceSize)
                        verifyDestStatus = isLastVerify ? .complete : .active
                    } else {
                        newVerifiedBytes = await self.verifiedBytesForDest(destPath)
                        verifyDestStatus = .failed(.verify)
                    }
                    var prog = DestProgress(
                        id: destPath, displayName: (destPath as NSString).lastPathComponent,
                        status: verifyDestStatus,
                        bytesTotal: c.totalBytesAllSources, filesTotal: c.totalSources,
                        verifyMode: .paranoid
                    )
                    prog.bytesCompleted = c.cumulativeBytesBeforeSource + c.sourceSize
                    prog.filesCompleted = c.sourceIndex + 1
                    prog.verifyBytesTotal = c.totalBytesAllSources
                    prog.verifyBytesCompleted = newVerifiedBytes
                    prog.currentFile = hashMatchesExpected ? "✓ \(c.sourceName)" : "✗ \(c.sourceName)"
                    let se = await self.combinedThroughputETA(
                        destPath: destPath, copyDoneNow: nil,
                        copyTotal: c.totalBytesAllSources, paranoid: true, jobStart: c.jobStartTime)
                    prog.speedBytesPerSecond = se.speed
                    prog.estimatedTimeRemaining = se.eta
                    prog.filesSkipped = c.skippedFiles
                    config.progressHandler?(prog)
                }
            }
        }

        return PerSourceOutcome(
            sourcePath: c.sourcePath,
            writerResults: c.writerResults,
            verifyFailedDestPaths: verifyFailed,
            sourceCorrupted: corrupted
        )
    }

    // Combined-throughput speed/ETA per destination.
    //
    // The copy-only rate swings hard (~300<->180 MB/s) as verification, which
    // overlaps copying via the pipeline, periodically steals disk bandwidth. But
    // the *total* disk throughput — copy bytes + verify bytes moved per second —
    // is roughly constant (the drive's bandwidth).
    //
    // A cumulative average since job start over-weights the fast cached opening
    // and lags the real rate, so the ETA drifts (Finder-grade ETAs use a moving
    // average of *recent* throughput). So we measure the combined throughput over
    // a short sliding window: stable (combined is ~constant even in paranoid) and
    // accurate within ~10s, with no early-history drift.
    //
    // Total work is known up front (copy + verify = ~2x data in paranoid), so
    // remaining_work / windowed_throughput is honest from the start. Displayed
    // speed is that throughput ÷ verify factor — the effective copy rate, which
    // predicts the verify slowdown rather than showing the no-verify peak.
    private var copyDoneByDest: [String: Int64] = [:]
    private var combinedSamplesByDest: [String: [(t: Date, done: Int64)]] = [:]
    private var etaEmitByDest: [String: (t: Date, speed: Double, eta: TimeInterval?)] = [:]
    private let etaMinElapsed: TimeInterval = 2.0
    private let etaEmitInterval: TimeInterval = 3.0
    private let throughputWindow: TimeInterval = 10.0

    /// `copyDoneNow` updates the stored copy progress (pass on copy emits, nil on
    /// verify emits). Reads live verified bytes from `verifiedBytesByDest`.
    private func combinedThroughputETA(
        destPath: String, copyDoneNow: Int64?, copyTotal: Int64,
        paranoid: Bool, jobStart: Date
    ) -> (speed: Double, eta: TimeInterval?) {
        if let c = copyDoneNow {
            copyDoneByDest[destPath] = max(copyDoneByDest[destPath] ?? 0, c)
        }
        let copyDone = copyDoneByDest[destPath] ?? 0
        let verifyDone = verifiedBytesByDest[destPath] ?? 0
        let verifyTotal: Int64 = paranoid ? copyTotal : 0
        let combinedDone = copyDone + verifyDone
        let combinedTotal = copyTotal + verifyTotal
        let now = Date()

        // Record a sample of cumulative combined work and keep a sliding window.
        var samples = combinedSamplesByDest[destPath] ?? []
        samples.append((now, combinedDone))
        let cutoff = now.addingTimeInterval(-throughputWindow)
        if let keepFrom = samples.firstIndex(where: { $0.t >= cutoff }), keepFrom > 0 {
            samples.removeFirst(keepFrom)
        }
        combinedSamplesByDest[destPath] = samples

        let elapsed = now.timeIntervalSince(jobStart)
        guard elapsed >= etaMinElapsed, combinedDone > 0, combinedTotal > 0, copyTotal > 0
        else { return (0, nil) }

        // Throttle the displayed value (hold between ticks).
        if let last = etaEmitByDest[destPath], now.timeIntervalSince(last.t) < etaEmitInterval {
            return (last.speed, last.eta)
        }

        // Windowed throughput = work done across the retained window.
        guard let oldest = samples.first else { return (0, nil) }
        let dt = now.timeIntervalSince(oldest.t)
        let db = combinedDone - oldest.done
        guard dt >= 0.5, db > 0 else {
            // Not enough movement yet — keep showing the last value if we have one.
            if let last = etaEmitByDest[destPath] { return (last.speed, last.eta) }
            return (0, nil)
        }

        let result = Self.computeCombinedSpeedETA(
            combinedDone: combinedDone, combinedTotal: combinedTotal,
            copyTotal: copyTotal, throughput: Double(db) / dt)
        etaEmitByDest[destPath] = (now, result.speed, result.eta)
        return result
    }

    /// Pure speed/ETA math (no timing/throttle) so it can be unit-tested.
    /// `throughput` is the measured combined (copy+verify) bytes/sec. Speed =
    /// throughput ÷ verify factor (effective copy rate, predicts the verify
    /// slowdown). ETA = remaining combined work ÷ throughput (counts the verify
    /// pass from the start).
    static func computeCombinedSpeedETA(
        combinedDone: Int64, combinedTotal: Int64, copyTotal: Int64, throughput: Double
    ) -> (speed: Double, eta: TimeInterval?) {
        guard throughput > 0, combinedDone > 0, copyTotal > 0 else { return (0, nil) }
        let verifyFactor = Double(combinedTotal) / Double(copyTotal)
        let speed = throughput / verifyFactor
        let remaining = combinedTotal - combinedDone
        let eta = remaining > 0 ? Double(remaining) / throughput : nil
        return (speed, eta)
    }

    nonisolated private func rereadHash(url: URL, chunkSz: Int) async -> String? {
        await Self.rereadHashDetached(url: url, chunkSz: chunkSz)
    }

    nonisolated private static func rereadHashDetached(url: URL, chunkSz: Int) async -> String? {
        await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path),
                  let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
            guard let hasher = XXH128StreamingHasher() else { return nil }
            // This is a tight synchronous loop with no `await` to drain the
            // autorelease pool, so FileHandle.read's autoreleased Data would
            // accumulate for the ENTIRE file (observed: 2 dests + source re-read
            // ~= 3x a multi-GB clip = >15 GB). Drain per chunk.
            while true {
                let done = autoreleasepool { () -> Bool in
                    if #available(macOS 10.15.4, *) {
                        guard let data = try? handle.read(upToCount: chunkSz), !data.isEmpty else { return true }
                        hasher.update(data: data)
                    } else {
                        let data = handle.readData(ofLength: chunkSz)
                        if data.isEmpty { return true }
                        hasher.update(data: data)
                    }
                    return false
                }
                if done { break }
            }
            return hasher.finalize().hexString
        }.value
    }
}
