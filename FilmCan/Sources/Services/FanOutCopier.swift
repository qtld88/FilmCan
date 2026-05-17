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

        let destURLs = config.destinations.map { URL(fileURLWithPath: $0.destPath) }
        await OrphanCleaner.shared.cleanOrphans(at: destURLs)

        let destInfos = config.destinations.map { DriveSpeedClassifier.info(for: $0.destPath) }
        let slowest = DriveSpeedClassifier.slowestDestClass(destInfos)
        let chunkSz = Constants.chunkBytes(forSlowestDest: slowest)
        let ringCapBytes = Constants.ringCapBytesPerDest()
        let channelCapacity = max(2, ringCapBytes / max(1, chunkSz))

        var builders: [String: DestResultBuilder] = [:]
        for dest in config.destinations {
            builders[dest.destPath] = DestResultBuilder(
                destPath: dest.destPath,
                displayName: dest.displayName,
                verifyMode: dest.verifyMode
            )
        }

        let sourceConcurrency = maxConcurrentSources()
        let sources = config.sources

        let outcomes: [PerSourceOutcome] = try await withThrowingTaskGroup(of: PerSourceOutcome.self) { group in
            var iter = sources.makeIterator()
            var inFlight = 0
            for _ in 0..<min(sourceConcurrency, sources.count) {
                if let src = iter.next() {
                    group.addTask { [self] in
                        try await processSource(sourcePath: src, channelCapacity: channelCapacity, chunkSz: chunkSz)
                    }
                    inFlight += 1
                }
            }
            var collected: [PerSourceOutcome] = []
            while inFlight > 0 {
                let outcome = try await group.next()!
                inFlight -= 1
                collected.append(outcome)
                if outcome.sourceCorrupted {
                    group.cancelAll()
                    throw Error.sourceCorruption(outcome.sourcePath)
                }
                if let src = iter.next() {
                    group.addTask { [self] in
                        try await processSource(sourcePath: src, channelCapacity: channelCapacity, chunkSz: chunkSz)
                    }
                    inFlight += 1
                }
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

    /// Process one source file: open with F_NOCACHE, spawn per-dest writer tasks,
    /// broadcast chunks through bounded channels, then verify per config.verifyMode.
    nonisolated private func processSource(
        sourcePath: String,
        channelCapacity: Int,
        chunkSz: Int
    ) async throws -> PerSourceOutcome {
        let fm = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let sourceName = sourceURL.lastPathComponent

        guard fm.fileExists(atPath: sourcePath) else {
            throw Error.sourceNotFound(sourcePath)
        }
        guard let attrs = try? fm.attributesOfItem(atPath: sourcePath),
              let sourceSize = attrs[.size] as? Int64 else {
            throw Error.sourceReadFailed(sourcePath)
        }

        var channels: [String: BoundedChannel<Chunk>] = [:]
        for dest in config.destinations {
            channels[dest.destPath] = BoundedChannel<Chunk>(capacity: channelCapacity)
        }

        var writerTasks: [Task<DestWriterResult, Never>] = []

        for destCfg in config.destinations {
            let channel = channels[destCfg.destPath]!
            let destFileURL = URL(fileURLWithPath: destCfg.destPath)
                .appendingPathComponent(sourceName)
            let mhlURL = URL(fileURLWithPath: destCfg.destPath)
                .appendingPathComponent(".filmcan")
                .appendingPathComponent("hashlists")
                .appendingPathComponent("\(sourceName).mhl")
            let progressHandler = config.progressHandler
            let totalSources = config.sources.count

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
                                    status: .active, bytesTotal: sourceSize,
                                    filesTotal: totalSources, verifyMode: destCfg.verifyMode
                                )
                                prog.bytesCompleted = totalBytes
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
                var prog = DestProgress(
                    id: destCfg.destPath, displayName: destCfg.displayName,
                    status: .complete, bytesTotal: sourceSize,
                    filesTotal: totalSources, verifyMode: destCfg.verifyMode
                )
                prog.bytesCompleted = totalBytes
                prog.filesCompleted = 1
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

        var verifyFailed: Set<String> = []
        for r in writerResults where r.success {
            if let dh = r.destHashFromStream, dh != verifiedSourceHash {
                verifyFailed.insert(r.destPath)
                let destFile = URL(fileURLWithPath: r.destPath).appendingPathComponent(sourceName)
                try? fm.removeItem(at: destFile)
            }
        }

        var corrupted = false
        if config.verifyMode == .paranoid {
            let sourceHashFromDisk = await rereadHash(url: sourceURL, chunkSz: chunkSz)
            if let diskHash = sourceHashFromDisk, diskHash != verifiedSourceHash {
                corrupted = true
                for r in writerResults where r.success {
                    let destFile = URL(fileURLWithPath: r.destPath).appendingPathComponent(sourceName)
                    try? fm.removeItem(at: destFile)
                    verifyFailed.insert(r.destPath)
                }
            } else {
                await withTaskGroup(of: (String, String?).self) { group in
                    for r in writerResults where r.success && !verifyFailed.contains(r.destPath) {
                        let destFile = URL(fileURLWithPath: r.destPath).appendingPathComponent(sourceName)
                        let destPath = r.destPath
                        group.addTask {
                            let hash = await Self.rereadHashDetached(url: destFile, chunkSz: chunkSz)
                            return (destPath, hash)
                        }
                    }
                    for await (destPath, hash) in group {
                        if let h = hash, h != verifiedSourceHash {
                            verifyFailed.insert(destPath)
                            let destFile = URL(fileURLWithPath: destPath).appendingPathComponent(sourceName)
                            try? fm.removeItem(at: destFile)
                        } else if hash == nil {
                            verifyFailed.insert(destPath)
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
