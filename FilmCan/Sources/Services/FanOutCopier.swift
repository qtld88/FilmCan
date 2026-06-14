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
        totalDuration += result.durationSec
    }

    mutating func markVerificationFailed() {
        success = false
        verificationFailed = true
    }

    func build() -> DestResult {
        DestResult(
            destinationPath: destPath,
            displayName: displayName,
            success: success && !verificationFailed,
            filesTransferred: totalFiles,
            filesSkipped: 0,
            filesFailedAfterCopy: verificationFailed ? totalFiles : failures.count,
            bytesTransferred: totalBytes,
            failureReason: verificationFailed ? .verify : failures.first,
            mhlPath: mhlPaths.first,
            durationSec: totalDuration,
            verifyMode: verifyMode
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

    private func buildSharedMHLs(forRootNames rootNames: Set<String>) throws -> [String: [String: MHLWriter]] {
        var result: [String: [String: MHLWriter]] = [:]
        for destCfg in config.destinations {
            var byRoot: [String: MHLWriter] = [:]
            for rootName in rootNames {
                let mhlURL = URL(fileURLWithPath: destCfg.destPath)
                    .appendingPathComponent(".filmcan")
                    .appendingPathComponent("hashlists")
                    .appendingPathComponent("\(rootName).mhl")
                let writer = try MHLWriter(url: mhlURL, sourceName: rootName)
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
        copySamplesByDest.removeAll()
        emaSpeedByDest.removeAll()
        lastSpeedEmitByDest.removeAll()

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

        let plannedFiles: [PlannedFile] = entries.map { entry in
            let rootName = (entry.sourceRoot as NSString).lastPathComponent
            return PlannedFile(
                rootPath: entry.sourceRoot,
                rootName: rootName,
                absPath: entry.sourcePath,
                relPath: entry.sourceIsDirectory ? entry.relativePath : "",
                size: entry.size
            )
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

        var builders: [String: DestResultBuilder] = [:]
        for dest in config.destinations {
            builders[dest.destPath] = DestResultBuilder(
                destPath: dest.destPath,
                displayName: dest.displayName,
                verifyMode: dest.verifyMode
            )
        }

        // Build all shared MHL writers upfront, grouped by dest and rootName
        let uniqueRootNames = Set(plannedFiles.map { $0.rootName })
        let sharedMHLsByDest = try buildSharedMHLs(forRootNames: uniqueRootNames)

        // Concurrency: cap by number of distinct source drives so we don't oversubscribe a single bus.
        let sourceConcurrency = max(1, distinctSourceDriveCount(forPaths: config.sources))

        // Wall-clock start for live copy speed / ETA reporting.
        let jobStartTime = Date()

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
                            jobStartTime: jobStartTime
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

        // Seal each shared MHL so it gets the <sealed/> trailer.
        for destMHLs in sharedMHLsByDest.values {
            for writer in destMHLs.values {
                try? await writer.seal()
            }
        }

        return config.destinations.compactMap { builders[$0.destPath]?.build() }
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
        sharedMHLsByDest: [String: [String: MHLWriter]],
        jobStartTime: Date
    ) async throws -> CopyResult {
        let sourcePath = sourceURL.path

        var channels: [String: BoundedChannel<Chunk>] = [:]
        for dest in config.destinations {
            channels[dest.destPath] = BoundedChannel<Chunk>(capacity: channelCapacity)
        }

        var writerTasks: [Task<DestWriterResult, Never>] = []

        for destCfg in config.destinations {
            let channel = channels[destCfg.destPath]!
            let destFileURL: URL
            let destRootPath = destCfg.destPath
            if let preset = config.organizationPreset {
                let resolved = OrganizationTemplate.resolve(
                    preset: preset,
                    sourcePath: rootPath,
                    destinationRoot: destRootPath,
                    counter: 0,
                    date: Date()
                )
                let folderBase = resolved.folderPath.isEmpty
                    ? destRootPath
                    : (destRootPath as NSString).appendingPathComponent(resolved.folderPath)
                let baseTarget: String
                if relPath.isEmpty {
                    // Flat file: dest = folderBase / renamedItem
                    baseTarget = (folderBase as NSString).appendingPathComponent(resolved.renamedItem)
                } else if config.copyFolderContents {
                    // Directory, content-only: dest = folderBase / relPath
                    baseTarget = (folderBase as NSString).appendingPathComponent(relPath)
                } else {
                    // Directory, include folder: dest = folderBase / renamedItem / relPath
                    let namedFolder = (folderBase as NSString).appendingPathComponent(resolved.renamedItem)
                    baseTarget = (namedFolder as NSString).appendingPathComponent(relPath)
                }
                let parent = (baseTarget as NSString).deletingLastPathComponent
                try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                destFileURL = URL(fileURLWithPath: baseTarget)
            } else if relPath.isEmpty {
                // Flat file, no preset: dest = destRoot / rootName
                destFileURL = URL(fileURLWithPath: (destRootPath as NSString).appendingPathComponent(rootName))
            } else if config.copyFolderContents {
                // Directory, content-only, no preset: dest = destRoot / relPath
                let target = (destRootPath as NSString).appendingPathComponent(relPath)
                let parent = (target as NSString).deletingLastPathComponent
                try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                destFileURL = URL(fileURLWithPath: target)
            } else {
                // Directory, include folder, no preset: dest = destRoot / rootName / relPath
                let namedFolder = (destRootPath as NSString).appendingPathComponent(rootName)
                let target = (namedFolder as NSString).appendingPathComponent(relPath)
                let parent = (target as NSString).deletingLastPathComponent
                try? FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
                destFileURL = URL(fileURLWithPath: target)
            }
            let progressHandler = config.progressHandler

            let task = Task<DestWriterResult, Never> {
                let startTime = Date()
                var totalBytes: Int64 = 0
                var writeFailed: DestFailureReason? = nil
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

                                var prog = DestProgress(
                                    id: destCfg.destPath, displayName: destCfg.displayName,
                                    status: .active, bytesTotal: totalBytesAllSources,
                                    filesTotal: totalSources, verifyMode: destCfg.verifyMode
                                )
                                prog.bytesCompleted = cumulativeBytesBeforeSource + totalBytes
                                prog.filesCompleted = sourceIndex
                                prog.currentFile = sourceName
                                prog.verifyBytesTotal = totalBytesAllSources
                                prog.verifyBytesCompleted = verifiedAtStart
                                let se = await self.windowedCopySpeed(
                                    destPath: destCfg.destPath,
                                    bytesCompleted: prog.bytesCompleted,
                                    bytesTotal: prog.bytesTotal)
                                prog.speedBytesPerSecond = se.speed
                                prog.estimatedTimeRemaining = se.eta
                                progressHandler?(prog)
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
                    try await writer.appendMHL(hash: destHash, fileName: sourceName)
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
                prog.bytesCompleted = cumulativeBytesBeforeSource + totalBytes
                prog.filesCompleted = sourceIndex + 1
                prog.currentFile = sourceName
                prog.verifyBytesTotal = totalBytesAllSources
                prog.verifyBytesCompleted = verifiedAtStart
                let se = await self.windowedCopySpeed(
                    destPath: destCfg.destPath,
                    bytesCompleted: prog.bytesCompleted,
                    bytesTotal: prog.bytesTotal)
                prog.speedBytesPerSecond = se.speed
                prog.estimatedTimeRemaining = se.eta
                progressHandler?(prog)

                let mhlPath = URL(fileURLWithPath: destCfg.destPath)
                    .appendingPathComponent(".filmcan")
                    .appendingPathComponent("hashlists")
                    .appendingPathComponent("\(rootName).mhl")
                    .path

                return DestWriterResult(
                    destPath: destCfg.destPath, displayName: destCfg.displayName,
                    success: true, bytesTransferred: totalBytes, filesTransferred: 1,
                    durationSec: duration, mhlPath: mhlPath,
                    failureReason: nil, verifyMode: destCfg.verifyMode,
                    destHashFromStream: destHash,
                    writtenFilePath: destFileURL.path
                )
            }
            writerTasks.append(task)
        }

        var sourceHash: String?
        var sourceError: (any Swift.Error)?
        var deadDests: Set<String> = []
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            // No F_NOCACHE here: the copy pass reads sequentially and benefits
            // from kernel readahead/prefetch. The hashed bytes are identical
            // whether cached or not; the paranoid verify uses its own F_NOCACHE
            // handle to re-read real device content. F_NOCACHE on this hot path
            // disables prefetch and slows large sequential reads.
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
            // Speed/ETA are copy-only (verify overlaps copy via the pipeline, so
            // it no longer adds to the timeline). Don't touch them on verify emits.
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
                    // Copy-only speed/ETA — left untouched on verify emits.
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

    // Throughput tracking per destination. Copy speed swings hard during a run
    // because verification (which overlaps copying via the pipeline) periodically
    // steals disk/bus bandwidth — observed ~300 MB/s when no verify is in flight,
    // ~180 when one is. Reporting the raw windowed rate makes the ETA lurch. So:
    //   1. measure an instantaneous rate over a short (~3s) window,
    //   2. feed it into a heavily-smoothed EMA → the *sustained* rate, which
    //      already bakes in the verify slowdown (so the ETA is honest: it lands
    //      near the real ~40 min instead of a no-verify-peak ~20 min),
    //   3. only let the *displayed* speed/ETA change once every few seconds.
    private var copySamplesByDest: [String: [(t: Date, bytes: Int64)]] = [:]
    private var emaSpeedByDest: [String: Double] = [:]
    private var lastSpeedEmitByDest: [String: (t: Date, speed: Double, eta: TimeInterval?)] = [:]
    private let copySpeedWindow: TimeInterval = 3.0
    private let speedEmitInterval: TimeInterval = 5.0
    private let emaAlpha: Double = 0.12

    private func windowedCopySpeed(
        destPath: String, bytesCompleted: Int64, bytesTotal: Int64
    ) -> (speed: Double, eta: TimeInterval?) {
        let now = Date()

        // 1. Instantaneous rate over the short window.
        var samples = copySamplesByDest[destPath] ?? []
        samples.append((now, bytesCompleted))
        let cutoff = now.addingTimeInterval(-copySpeedWindow)
        if let keepFrom = samples.firstIndex(where: { $0.t >= cutoff }), keepFrom > 0 {
            samples.removeFirst(keepFrom)
        }
        copySamplesByDest[destPath] = samples
        if let oldest = samples.first, samples.count >= 2 {
            let dt = now.timeIntervalSince(oldest.t)
            let db = bytesCompleted - oldest.bytes
            if dt >= 0.5, db > 0 {
                let inst = Double(db) / dt
                // 2. Smooth into the sustained-rate EMA.
                if let prev = emaSpeedByDest[destPath] {
                    emaSpeedByDest[destPath] = emaAlpha * inst + (1 - emaAlpha) * prev
                } else {
                    emaSpeedByDest[destPath] = inst
                }
            }
        }
        let ema = emaSpeedByDest[destPath] ?? 0

        // 3. Throttle the displayed value: hold it for speedEmitInterval seconds.
        if let last = lastSpeedEmitByDest[destPath],
           now.timeIntervalSince(last.t) < speedEmitInterval {
            return (last.speed, last.eta)
        }
        let remaining = bytesTotal - bytesCompleted
        let eta = (ema > 0 && remaining > 0) ? Double(remaining) / ema : nil
        lastSpeedEmitByDest[destPath] = (now, ema, eta)
        return (ema, eta)
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
            while true {
                if #available(macOS 10.15.4, *) {
                    guard let data = try? handle.read(upToCount: chunkSz), !data.isEmpty else { break }
                    hasher.update(data: data)
                } else {
                    let data = handle.readData(ofLength: chunkSz)
                    if data.isEmpty { break }
                    hasher.update(data: data)
                }
            }
            return hasher.finalize().hexString
        }.value
    }
}
