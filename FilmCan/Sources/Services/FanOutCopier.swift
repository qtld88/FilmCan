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

// MARK: - FanOutCopier

actor FanOutCopier {
    struct Configuration {
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

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let s): return "Source not found: \(s)"
            case .sourceReadFailed(let s): return "Failed to read source: \(s)"
            case .noDestinations: return "No destinations configured"
            }
        }
    }

    private let config: Configuration

    init(config: Configuration) {
        self.config = config
    }

    /// Run the fan-out copy: read each source once, broadcast chunks to all
    /// destination writers via BoundedChannels, then collect per-dest results.
    func run() async throws -> [DestResult] {
        guard !config.destinations.isEmpty else { throw Error.noDestinations }
        guard !config.sources.isEmpty else { throw Error.sourceNotFound("(empty)") }

        // Clean any orphaned .filmcan-* temp files from previous runs
        let destURLs = config.destinations.map { URL(fileURLWithPath: $0.destPath) }
        await OrphanCleaner.shared.cleanOrphans(at: destURLs)

        let fm = FileManager.default

        // Compute chunk size from the slowest destination class
        let destInfos = config.destinations.map { DriveSpeedClassifier.info(for: $0.destPath) }
        let slowest = DriveSpeedClassifier.slowestDestClass(destInfos)
        let chunkSz = Constants.chunkBytes(forSlowestDest: slowest)

        // One result builder per destination — accumulates across all sources
        var builders: [String: DestResultBuilder] = [:]
        for dest in config.destinations {
            builders[dest.destPath] = DestResultBuilder(
                destPath: dest.destPath,
                displayName: dest.displayName,
                verifyMode: dest.verifyMode
            )
        }

        // --- Process each source file ---
        for sourcePath in config.sources {
            let sourceURL = URL(fileURLWithPath: sourcePath)
            let sourceName = sourceURL.lastPathComponent

            guard fm.fileExists(atPath: sourcePath) else {
                throw Error.sourceNotFound(sourcePath)
            }

            guard let attrs = try? fm.attributesOfItem(atPath: sourcePath),
                  let sourceSize = attrs[.size] as? Int64 else {
                throw Error.sourceReadFailed(sourcePath)
            }

            // 1. Create one BoundedChannel per destination
            var channels: [String: BoundedChannel<Chunk>] = [:]
            for dest in config.destinations {
                channels[dest.destPath] = BoundedChannel<Chunk>(capacity: 4)
            }

            // 2. Launch one writer Task per destination
            // Use Task<DestWriterResult, Never> — body catches all throws internally
            var writerTasks: [Task<DestWriterResult, Never>] = []

            for destCfg in config.destinations {
                let channel = channels[destCfg.destPath]!
                let destFileURL = URL(fileURLWithPath: destCfg.destPath)
                    .appendingPathComponent(sourceName)

                // MHL path: <dest>/.filmcan/hashlists/<sourceName>.mhl
                let mhlDir = URL(fileURLWithPath: destCfg.destPath)
                    .appendingPathComponent(".filmcan")
                    .appendingPathComponent("hashlists")
                let mhlURL = mhlDir.appendingPathComponent("\(sourceName).mhl")

                let task = Task<DestWriterResult, Never> {
                    // Always signal the channel on exit so the source-read
                    // loop never blocks on a dead consumer.
                    defer {
                        Task { await channel.finish() }
                    }

                    let startTime = Date()
                    var totalBytes: Int64 = 0
                    var writeFailed: DestFailureReason? = nil

                    // Create hasher
                    guard let destHasher = XXH128StreamingHasher() else {
                        // Drain channel to unblock source read
                        while (try? await channel.receive()) != nil {}
                        return DestWriterResult(
                            destPath: destCfg.destPath,
                            displayName: destCfg.displayName,
                            success: false,
                            bytesTransferred: 0,
                            filesTransferred: 0,
                            durationSec: Date().timeIntervalSince(startTime),
                            mhlPath: nil,
                            failureReason: .ioError("xxhash unavailable"),
                            verifyMode: destCfg.verifyMode
                        )
                    }

                    // Create DestWriter
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
                        while (try? await channel.receive()) != nil {}
                        return DestWriterResult(
                            destPath: destCfg.destPath,
                            displayName: destCfg.displayName,
                            success: false,
                            bytesTransferred: 0,
                            filesTransferred: 0,
                            durationSec: Date().timeIntervalSince(startTime),
                            mhlPath: nil,
                            failureReason: .ioError(error.localizedDescription),
                            verifyMode: destCfg.verifyMode
                        )
                    }

                    // 3. Consume chunks from channel
                    // Wrap for-try-await in do-catch so the outer closure stays non-throwing
                    do {
                        for try await chunk in channel {
                            if writeFailed == nil {
                                do {
                                    try await writer.write(data: chunk.data)
                                    destHasher.update(data: chunk.data)
                                    totalBytes += Int64(chunk.data.count)

                                    // Progress update
                                    var prog = DestProgress(
                                        id: destCfg.destPath,
                                        displayName: destCfg.displayName,
                                        status: .active,
                                        bytesTotal: sourceSize,
                                        filesTotal: config.sources.count,
                                        verifyMode: destCfg.verifyMode
                                    )
                                    prog.bytesCompleted = totalBytes
                                    prog.currentFile = sourceName
                                    config.progressHandler?(prog)
                                } catch {
                                    writeFailed = .ioError(error.localizedDescription)
                                    // Continue consuming to unblock source read
                                }
                            }
                        }
                    } catch {
                        // Channel finished — expected termination
                    }

                    // If a write failed, return error without finalizing
                    if let reason = writeFailed {
                        return DestWriterResult(
                            destPath: destCfg.destPath,
                            displayName: destCfg.displayName,
                            success: false,
                            bytesTransferred: totalBytes,
                            filesTransferred: 0,
                            durationSec: Date().timeIntervalSince(startTime),
                            mhlPath: nil,
                            failureReason: reason,
                            verifyMode: destCfg.verifyMode
                        )
                    }

                    // All chunks written successfully — finalize
                    let destHash = destHasher.finalize().hexString

                    do {
                        try await writer.finalize(fileHash: destHash, sourceSize: sourceSize)
                        try await writer.appendMHL(hash: destHash, fileName: sourceName)
                    } catch {
                        return DestWriterResult(
                            destPath: destCfg.destPath,
                            displayName: destCfg.displayName,
                            success: false,
                            bytesTransferred: totalBytes,
                            filesTransferred: 0,
                            durationSec: Date().timeIntervalSince(startTime),
                            mhlPath: nil,
                            failureReason: .ioError(error.localizedDescription),
                            verifyMode: destCfg.verifyMode
                        )
                    }

                    let duration = Date().timeIntervalSince(startTime)

                    // Final progress
                    var prog = DestProgress(
                        id: destCfg.destPath,
                        displayName: destCfg.displayName,
                        status: .complete,
                        bytesTotal: sourceSize,
                        filesTotal: config.sources.count,
                        verifyMode: destCfg.verifyMode
                    )
                    prog.bytesCompleted = totalBytes
                    prog.filesCompleted = 1
                    prog.currentFile = sourceName
                    config.progressHandler?(prog)

                    return DestWriterResult(
                        destPath: destCfg.destPath,
                        displayName: destCfg.displayName,
                        success: true,
                        bytesTransferred: totalBytes,
                        filesTransferred: 1,
                        durationSec: duration,
                        mhlPath: mhlURL.path,
                        failureReason: nil,
                        verifyMode: destCfg.verifyMode
                    )
                }
                writerTasks.append(task)
            }

            // 4. Source read loop — reads ONCE, broadcasts to all channels
            var sourceHash: String?
            var sourceError: (any Swift.Error)?
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

                    // Broadcast to all destination channels
                    let chunk = Chunk(data: chunkData)
                    for channel in channels.values {
                        await channel.send(chunk)
                    }
                }

                sourceHash = sourceHasher.finalize().hexString
            } catch {
                sourceError = error
            }

            // 5. Signal EOF to all channels
            for channel in channels.values {
                await channel.finish()
            }

            // 6. Wait for all writers and merge results into builders
            for task in writerTasks {
                let result = await task.value
                builders[result.destPath]?.incorporate(result)
            }

            // 7. After collecting writer results, re-throw source read error if any
            if let sourceError {
                throw sourceError
            }

            guard let verifiedSourceHash = sourceHash else {
                throw Error.sourceReadFailed(sourcePath)
            }

            // 8. Paranoid verification — re-read dest files and compare hashes
            if config.verifyMode == .paranoid {
                for destCfg in config.destinations {
                    let destFile = URL(fileURLWithPath: destCfg.destPath)
                        .appendingPathComponent(sourceName)
                    guard fm.fileExists(atPath: destFile.path) else { continue }

                    guard let verifier = XXH128StreamingHasher() else { continue }
                    let verifyHandle: FileHandle
                    do {
                        verifyHandle = try FileHandle(forReadingFrom: destFile)
                    } catch {
                        builders[destCfg.destPath]?.markVerificationFailed()
                        continue
                    }
                    _ = fcntl(verifyHandle.fileDescriptor, F_NOCACHE, 1)
                    defer { try? verifyHandle.close() }

                    while true {
                        let data: Data
                        if #available(macOS 10.15.4, *) {
                            guard let d = try? verifyHandle.read(upToCount: chunkSz),
                                  !d.isEmpty
                            else { break }
                            data = d
                        } else {
                            let d = verifyHandle.readData(ofLength: chunkSz)
                            if d.isEmpty { break }
                            data = d
                        }
                        verifier.update(data: data)
                    }

                    let destHash = verifier.finalize().hexString
                    if destHash != verifiedSourceHash {
                        builders[destCfg.destPath]?.markVerificationFailed()
                    }
                }
            }
        }

        // Convert builders → final DestResults
        return config.destinations.compactMap { builders[$0.destPath]?.build() }
    }
}
