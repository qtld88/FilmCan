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

// MARK: - FanOutCopier

actor FanOutCopier {
    struct Configuration: Sendable {
        var sources: [String]
        var destinations: [DestWriter.Config]
        var verifyMode: VerifyMode
        var mhlBasePath: String?
        var dryRun: Bool
        var progressHandler: (@Sendable (DestProgress) -> Void)?
    }

    enum Error: Swift.Error, LocalizedError {
        case sourceNotFound(String)
        case sourceReadFailed(String)
        case noDestinations
        case sourceCorruption(String)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let s): return "Source not found: \(s)"
            case .sourceReadFailed(let s): return "Failed to read source: \(s)"
            case .noDestinations: return "No destinations configured"
            case .sourceCorruption(let s):
                return "Source corruption detected during copy — RAM or source drive issue. Retry recommended. (\(s))"
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
        let entries = await FileEnumerator.enumerateFiles(sources: config.sources, preset: nil)
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

        // Concurrency: cap by number of distinct source drives so we don't oversubscribe a single bus.
        let sourceConcurrency = max(1, distinctSourceDriveCount(forPaths: config.sources))

        let outcomes: [PerSourceOutcome] = try await withThrowingTaskGroup(of: PerSourceOutcome.self) { group in
            var iter = plannedFiles.enumerated().makeIterator()
            var inFlight = 0

            func enqueueNext() -> Bool {
                guard let (index, file) = iter.next() else { return false }
                let absURL = URL(fileURLWithPath: file.absPath)
                let cumBefore = cumulativeBeforeFile[index]
                group.addTask { [self] in
                    try await processSource(
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
                        relPath: file.relPath
                    )
                }
                inFlight += 1
                return true
            }

            for _ in 0..<min(sourceConcurrency, plannedFiles.count) {
                _ = enqueueNext()
            }

            var collected: [PerSourceOutcome] = []
            while inFlight > 0 {
                guard let outcome = try await group.next() else { break }
                inFlight -= 1
                collected.append(outcome)
                if outcome.sourceCorrupted {
                    group.cancelAll()
                    throw Error.sourceCorruption(outcome.sourcePath)
                }
                _ = enqueueNext()
            }
            return collected
        }

        for outcome in outcomes {
            for w in outcome.writerResults {
                builders[w.destPath]?.incorporate(w)
            }
            for dp in outcome.verifyFailedDestPaths {
                builders[dp]?.markVerificationFailed()
            }
        }

        return config.destinations.compactMap { builders[$0.destPath]?.build() }
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

    /// Process one source file: open with F_NOCACHE, spawn per-dest writer tasks,
    /// broadcast chunks through bounded channels, then verify per config.verifyMode.
    /// cumulativeBytesBeforeSource is the sum of all earlier source sizes for correct progress tracking.
    /// totalBytesAllSources is the sum of ALL source sizes (full job).
    /// Only emits .complete status when sourceIndex == totalSources - 1 (last source).
    nonisolated private func processSource(
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
        relPath: String
    ) async throws -> PerSourceOutcome {
        let sourcePath = sourceURL.path
        let fm = FileManager.default

        var channels: [String: BoundedChannel<Chunk>] = [:]
        for dest in config.destinations {
            channels[dest.destPath] = BoundedChannel<Chunk>(capacity: channelCapacity)
        }

        var writerTasks: [Task<DestWriterResult, Never>] = []

        for destCfg in config.destinations {
            let channel = channels[destCfg.destPath]!
            let destRootURL = URL(fileURLWithPath: destCfg.destPath)
                .appendingPathComponent(rootName)
            let destFileURL: URL
            if relPath.isEmpty {
                // Flat-file source: write directly under destRoot.
                destFileURL = destRootURL
            } else {
                destFileURL = destRootURL.appendingPathComponent(relPath)
                // Ensure parent directory exists; ignore "already exists" failures.
                let parent = destFileURL.deletingLastPathComponent()
                try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            let mhlURL = URL(fileURLWithPath: destCfg.destPath)
                .appendingPathComponent(".filmcan")
                .appendingPathComponent("hashlists")
                .appendingPathComponent("\(rootName).mhl")
            let progressHandler = config.progressHandler

            let task = Task<DestWriterResult, Never> {
                let startTime = Date()
                var totalBytes: Int64 = 0
                var writeFailed: DestFailureReason? = nil

                guard let destHasher = XXH128StreamingHasher() else {
                    await channel.finish()
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: 0, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .ioError("xxhash unavailable"),
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil
                    )
                }

                let writer: DestWriter
                do {
                    writer = try await DestWriter(
                        destPath: destFileURL.path,
                        displayName: destCfg.displayName,
                        verifyMode: destCfg.verifyMode,
                        requiresFullFsync: destCfg.requiresFullFsync,
                        mhlURL: mhlURL,
                        sourceName: sourceName
                    )
                } catch {
                    await channel.finish()
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: 0, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: .ioError(error.localizedDescription),
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil
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

                if let reason = writeFailed {
                    return DestWriterResult(
                        destPath: destCfg.destPath, displayName: destCfg.displayName,
                        success: false, bytesTransferred: totalBytes, filesTransferred: 0,
                        durationSec: Date().timeIntervalSince(startTime),
                        mhlPath: nil, failureReason: reason,
                        verifyMode: destCfg.verifyMode, destHashFromStream: nil
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
                        verifyMode: destCfg.verifyMode, destHashFromStream: destHash
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
                progressHandler?(prog)

                return DestWriterResult(
                    destPath: destCfg.destPath, displayName: destCfg.displayName,
                    success: true, bytesTransferred: totalBytes, filesTransferred: 1,
                    durationSec: duration, mhlPath: mhlURL.path,
                    failureReason: nil, verifyMode: destCfg.verifyMode,
                    destHashFromStream: destHash
                )
            }
            writerTasks.append(task)
        }

        var sourceHash: String?
        var sourceError: (any Swift.Error)?
        var deadDests: Set<String> = []
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            _ = fcntl(sourceHandle.fileDescriptor, F_NOCACHE, 1)
            defer { try? sourceHandle.close() }

            guard let sourceHasher = XXH128StreamingHasher() else {
                throw Error.sourceReadFailed("xxhash unavailable for \(sourcePath)")
            }

            while true {
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

        func destFilePath(for base: String) -> String {
            let root = URL(fileURLWithPath: base).appendingPathComponent(rootName)
            return relPath.isEmpty ? root.path : root.appendingPathComponent(relPath).path
        }

        var verifyFailed: Set<String> = []
        for r in writerResults where r.success {
            if let dh = r.destHashFromStream, dh != verifiedSourceHash {
                verifyFailed.insert(r.destPath)
                try? fm.removeItem(atPath: destFilePath(for: r.destPath))
            }
        }

        var corrupted = false
        if config.verifyMode == .paranoid {
            // Emit verify-start progress for each successful destination
            for r in writerResults where r.success {
                var prog = DestProgress(
                    id: r.destPath, displayName: (r.destPath as NSString).lastPathComponent,
                    status: .active, bytesTotal: totalBytesAllSources,
                    filesTotal: totalSources, verifyMode: .paranoid
                )
                prog.bytesCompleted = cumulativeBytesBeforeSource + sourceSize
                prog.filesCompleted = sourceIndex + 1
                prog.verifyBytesTotal = sourceSize
                prog.verifyBytesCompleted = 0
                prog.currentFile = "Verifying \(sourceName)…"
                config.progressHandler?(prog)
            }
            let sourceHashFromDisk = await rereadHash(url: sourceURL, chunkSz: chunkSz)
            if let diskHash = sourceHashFromDisk, diskHash != verifiedSourceHash {
                corrupted = true
                for r in writerResults where r.success {
                    try? fm.removeItem(atPath: destFilePath(for: r.destPath))
                    verifyFailed.insert(r.destPath)
                }
            } else {
                await withTaskGroup(of: (String, String?).self) { group in
                    for r in writerResults where r.success && !verifyFailed.contains(r.destPath) {
                        let destFileURL = URL(fileURLWithPath: destFilePath(for: r.destPath))
                        let destPath = r.destPath
                        group.addTask {
                            let hash = await Self.rereadHashDetached(url: destFileURL, chunkSz: chunkSz)
                            return (destPath, hash)
                        }
                    }
                    for await (destPath, hash) in group {
                        let hashMatchesExpected = hash == verifiedSourceHash
                        if let h = hash, h != verifiedSourceHash {
                            verifyFailed.insert(destPath)
                            try? fm.removeItem(atPath: destFilePath(for: destPath))
                        } else if hash == nil {
                            verifyFailed.insert(destPath)
                        }
                        if let _ = writerResults.first(where: { $0.destPath == destPath }) {
                            let verifyDestStatus: DestStatus
                            if hashMatchesExpected {
                                let isLastVerify = await self.recordVerifyCompletion(destPath: destPath, totalFiles: totalSources)
                                verifyDestStatus = isLastVerify ? .complete : .active
                            } else {
                                verifyDestStatus = .failed(.verify)
                            }
                            var prog = DestProgress(
                                id: destPath, displayName: (destPath as NSString).lastPathComponent,
                                status: verifyDestStatus,
                                bytesTotal: totalBytesAllSources, filesTotal: totalSources,
                                verifyMode: .paranoid
                            )
                            prog.bytesCompleted = cumulativeBytesBeforeSource + sourceSize
                            prog.filesCompleted = sourceIndex + 1
                            prog.verifyBytesTotal = sourceSize
                            prog.verifyBytesCompleted = sourceSize
                            prog.currentFile = hashMatchesExpected ? "✓ \(sourceName)" : "✗ \(sourceName)"
                            config.progressHandler?(prog)
                        }
                    }
                }
            }
        }

        return PerSourceOutcome(
            sourcePath: sourcePath,
            writerResults: writerResults,
            verifyFailedDestPaths: verifyFailed,
            sourceCorrupted: corrupted
        )
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
