import Foundation

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
        case pipelineSetupFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceNotFound(let s): return "Source not found: \(s)"
            case .sourceReadFailed(let s): return "Failed to read source: \(s)"
            case .noDestinations: return "No destinations configured"
            case .pipelineSetupFailed(let s): return "Pipeline setup failed: \(s)"
            }
        }
    }

    private let config: Configuration
    private var destWriters: [DestWriter] = []

    init(config: Configuration) {
        self.config = config
    }

    /// Run the fan-out copy operation
    func run() async throws -> [DestResult] {
        guard !config.destinations.isEmpty else { throw Error.noDestinations }
        guard !config.sources.isEmpty else { throw Error.sourceNotFound("(empty)") }

        // Initialize dest writers
        for dest in config.destinations {
            destWriters.append(await DestWriter(config: dest))
        }

        var results: [DestResult] = []

        for sourcePath in config.sources {
            let fm = FileManager.default
            guard fm.fileExists(atPath: sourcePath) else {
                throw Error.sourceNotFound(sourcePath)
            }

            let sourceURL = URL(fileURLWithPath: sourcePath)
            let sourceSize = try FileManager.default.attributesOfItem(atPath: sourcePath)[.size] as! Int64

            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)

            // Enable F_NOCACHE on source handle
            let srcFD = sourceHandle.fileDescriptor
            fcntl(srcFD, F_NOCACHE, 1)

            // Determine chunk size from slowest destination class
            let destInfos = config.destinations.compactMap { cfg -> DriveInfo? in
                DriveSpeedClassifier.info(for: cfg.destPath)
            }
            let slowest = DriveSpeedClassifier.slowestDestClass(destInfos)
            let chunkSz = Constants.chunkBytes(forSlowestDest: slowest)

            defer { try? sourceHandle.close() }

            // Create MHL writer if base path is provided
            let mhlWriter: MHLWriter? = try {
                guard let base = config.mhlBasePath else { return nil }
                let sourceName = sourceURL.lastPathComponent
                let mhlURL = URL(fileURLWithPath: base).appendingPathComponent("\(sourceName).mhl")
                return try MHLWriter(url: mhlURL, sourceName: sourceName)
            }()

            // Progress per destination
            var progressMap: [String: DestProgress] = [:]
            for dest in config.destinations {
                progressMap[dest.destPath] = DestProgress(
                    id: dest.destPath,
                    displayName: dest.displayName,
                    status: .active,
                    bytesTotal: sourceSize,
                    filesTotal: 1,
                    verifyMode: dest.verifyMode
                )
            }

            // Read source, compute hash
            guard let sourceHasher = XXH128StreamingHasher() else {
                throw Error.sourceReadFailed("\(sourcePath): xxhash unavailable")
            }
            let sourceName = sourceURL.lastPathComponent

            while true {
                let chunkData: Data
                do {
                    if #available(macOS 10.15.4, *) {
                        guard let data = try sourceHandle.read(upToCount: chunkSz) else { break }
                        chunkData = data
                    } else {
                        let data = sourceHandle.readData(ofLength: chunkSz)
                        if data.isEmpty { break }
                        chunkData = data
                    }
                } catch {
                    // Update progress for all dests as failed due to source read error
                    for (path, var prog) in progressMap {
                        prog.status = .failed(.sourceUnavailable)
                        config.progressHandler?(prog)
                        progressMap[path] = prog
                    }
                    throw Error.sourceReadFailed(sourcePath)
                }

                sourceHasher.update(data: chunkData)
            }

            let sourceHash = sourceHasher.finalize().hexString

            // Append to MHL writer
            if let mhlWriter = mhlWriter {
                try await mhlWriter.append(hash: sourceHash, fileName: sourceName)
            }

            // For each destination: write file, produce result
            for dest in config.destinations {
                let destPath = (dest.destPath as NSString).appendingPathComponent(sourceName)

                var prog = progressMap[dest.destPath] ?? DestProgress(
                    id: dest.destPath,
                    displayName: dest.displayName,
                    status: .active,
                    bytesTotal: sourceSize,
                    filesTotal: 1,
                    verifyMode: dest.verifyMode
                )

                // Write file to destination
                do {
                    try await writeSourceToDest(sourcePath: sourcePath, destPath: destPath,
                                               chunkSize: chunkSz)

                    prog.bytesCompleted = sourceSize
                    prog.filesCompleted = 1
                    prog.status = .complete
                    config.progressHandler?(prog)
                    progressMap[dest.destPath] = prog
                } catch {
                    prog.status = .failed(.ioError(error.localizedDescription))
                    config.progressHandler?(prog)
                    progressMap[dest.destPath] = prog
                }
            }

            // Flush MHL writer
            if let mhlWriter = mhlWriter {
                try await mhlWriter.flush()
            }

            // Build results
            for dest in config.destinations {
                let prog = progressMap[dest.destPath] ?? DestProgress(
                    id: dest.destPath,
                    displayName: dest.displayName,
                    verifyMode: dest.verifyMode
                )
                let success: Bool
                let failReason: DestFailureReason?
                switch prog.status {
                case .complete:
                    success = true
                    failReason = nil
                case .failed(let reason):
                    success = false
                    failReason = reason
                default:
                    success = false
                    failReason = .ioError("Unfinished")
                }

                results.append(DestResult(
                    destinationPath: dest.destPath,
                    displayName: dest.displayName,
                    success: success,
                    filesTransferred: prog.filesCompleted,
                    filesSkipped: 0,
                    filesFailedAfterCopy: 0,
                    bytesTransferred: prog.bytesCompleted,
                    failureReason: failReason,
                    mhlPath: config.mhlBasePath.map { "\($0)/\(sourceName).mhl" },
                    durationSec: 0,
                    verifyMode: dest.verifyMode
                ))
            }
        }

        return results
    }

    /// Simple file copy from source to destination path
    private func writeSourceToDest(sourcePath: String, destPath: String, chunkSize: Int) async throws {
        let fm = FileManager.default
        let sourceHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: sourcePath))
        defer { try? sourceHandle.close() }

        // Create parent directory
        let destURL = URL(fileURLWithPath: destPath)
        try fm.createDirectory(at: destURL.deletingLastPathComponent(),
                              withIntermediateDirectories: true)

        // Create temp file
        let uuid = UUID().uuidString
        let tempName = ".filmcan-\(uuid)-\(destURL.lastPathComponent)"
        let tempURL = destURL.deletingLastPathComponent().appendingPathComponent(tempName)
        fm.createFile(atPath: tempURL.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? destHandle.close() }

        // F_NOCACHE on dest
        fcntl(destHandle.fileDescriptor, F_NOCACHE, 1)

        // Copy
        try sourceHandle.seek(toOffset: 0)
        while true {
            let chunk: Data
            if #available(macOS 10.15.4, *) {
                guard let data = try sourceHandle.read(upToCount: chunkSize) else { break }
                chunk = data
            } else {
                let data = sourceHandle.readData(ofLength: chunkSize)
                if data.isEmpty { break }
                chunk = data
            }
            try destHandle.write(contentsOf: chunk)
        }

        // F_FULLFSYNC if needed
        // (policy determined externally, default off)
        try destHandle.synchronize()

        // Atomic rename
        _ = try fm.replaceItemAt(destURL, withItemAt: tempURL)
    }
}
