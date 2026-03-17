import Foundation

struct FileCopyResult {
    let sourcePath: String
    let destinationPath: String
    let bytesWritten: Int64
    let sourceHash: Data?
    var destinationHash: Data?  // Optional when verification runs later
    
    var verified: Bool {
        guard let destHash = destinationHash, let sourceHash else { return false }
        return sourceHash == destHash
    }
}

enum FileCopyError: LocalizedError {
    case sourceNotReadable(String)
    case destinationNotWritable(String)
    case copyFailed(String)
    case verificationFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceNotReadable(let path):
            return "Cannot read source file: \(path)"
        case .destinationNotWritable(let path):
            return "Cannot write to destination: \(path)"
        case .copyFailed(let message):
            return "Copy failed: \(message)"
        case .verificationFailed(let path):
            return "Verification failed: \(path)"
        case .cancelled:
            return "Copy cancelled"
        }
    }
}

actor FileStreamCopier {
    private let defaultBufferSize = 1024 * 1024
    private let exfatBufferSize = 4 * 1024 * 1024
    private let exfatSyncInterval: Int64 = 32 * 1024 * 1024
    private var exfatCache: [String: Bool] = [:]

    /// Copy file with source hashing, return immediately without verifying destination
    /// Call computeFileHash() later to check destination hash
    func copyFile(
        source: String,
        destination: String,
        hashDuringCopy: Bool = true,
        hashAlgorithm: FilmCanHashAlgorithm,
        shouldCancel: @Sendable () -> Bool,
        progressCallback: @Sendable (Int64) -> Void
    ) async throws -> FileCopyResult {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: source) else {
            throw FileCopyError.sourceNotReadable(source)
        }

        let destDir = (destination as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: destDir) {
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        }

        guard let sourceHandle = FileHandle(forReadingAtPath: source) else {
            throw FileCopyError.sourceNotReadable(source)
        }
        defer { try? sourceHandle.close() }

        fm.createFile(atPath: destination, contents: nil)
        guard let destHandle = FileHandle(forWritingAtPath: destination) else {
            throw FileCopyError.destinationNotWritable(destination)
        }
        var didCloseDestHandle = false
        defer {
            if !didCloseDestHandle {
                try? destHandle.close()
            }
        }

        var sourceHasher: StreamingHasher? = nil
        if hashDuringCopy {
            guard let hasher = makeHasher(algorithm: hashAlgorithm) else {
                throw FileCopyError.copyFailed("xxHash128 unavailable. Ensure libxxhash is bundled.")
            }
            sourceHasher = hasher
        }
        var totalBytes: Int64 = 0
        var bytesSinceSync: Int64 = 0

        let isExFAT = isExFATFilesystem(path: destination)
        // Handle empty files explicitly
        let sourceSize = Int64((try? fm.attributesOfItem(atPath: source)[.size] as? NSNumber)?.int64Value ?? 0)
        let bufferSize = isExFAT ? exfatBufferSize : defaultBufferSize
        if sourceSize == 0 {
            let emptyHash: Data? = hashDuringCopy ? sourceHasher?.finalize() : nil
            try? copyFileAttributes(from: source, to: destination)
            return FileCopyResult(
                sourcePath: source,
                destinationPath: destination,
                bytesWritten: 0,
                sourceHash: emptyHash,
                destinationHash: emptyHash
            )
        }

        // Copy with autoreleasepool to prevent memory buildup
        var caughtError: Error? = nil
        while true {
            let shouldContinue = autoreleasepool { () -> Bool in
                if shouldCancel() || Task.isCancelled {
                    caughtError = FileCopyError.cancelled
                    return false
                }
                
                let data: Data
                do {
                    guard let readData = try sourceHandle.read(upToCount: bufferSize), !readData.isEmpty else {
                        return false  // Normal EOF
                    }
                    data = readData
                } catch {
                    caughtError = FileCopyError.copyFailed("Failed to read source: \(error.localizedDescription)")
                    return false
                }

                if hashDuringCopy {
                    sourceHasher?.update(data: data)
                }
                
                do {
                    try destHandle.write(contentsOf: data)
                } catch {
                    caughtError = FileCopyError.copyFailed("Failed to write destination: \(error.localizedDescription)")
                    return false
                }
                
                totalBytes += Int64(data.count)
                if isExFAT {
                    bytesSinceSync += Int64(data.count)
                    if bytesSinceSync >= exfatSyncInterval {
                        try? destHandle.synchronize()
                        bytesSinceSync = 0
                    }
                }
                progressCallback(totalBytes)
                return true
            }

            if let error = caughtError {
                throw error
            }
            if !shouldContinue {
                break
            }
        }

        let sourceHash: Data?
        if let hasher = sourceHasher {
            sourceHash = hasher.finalize()
        } else {
            sourceHash = nil
        }
        
        // Ensure file is fully written
        if isExFAT {
            if bytesSinceSync > 0 {
                try? destHandle.synchronize()
            }
            try? destHandle.close()
        } else {
            try? destHandle.synchronize()
            try? destHandle.close()
        }
        didCloseDestHandle = true
        
        try? copyFileAttributes(from: source, to: destination)

        // ✅ RETURN IMMEDIATELY - don't verify destination yet!
        return FileCopyResult(
            sourcePath: source,
            destinationPath: destination,
            bytesWritten: totalBytes,
            sourceHash: sourceHash,
            destinationHash: nil  // ← Not verified yet
        )
    }
    
    /// Compute a hash for any file path.
    /// Call this AFTER copyFile to verify destination or to hash sources when needed.
    /// The callback receives incremental bytes read (not cumulative).
    func computeFileHash(
        path: String,
        algorithm: FilmCanHashAlgorithm,
        shouldCancel: @Sendable () -> Bool,
        onBytesRead: @Sendable (Int64) -> Void
    ) async throws -> Data {
        // Small delay for network filesystems to catch up
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms

        let destinationHash = try computeFileHashSync(
            path: path,
            algorithm: algorithm,
            shouldCancel: shouldCancel,
            progressCallback: onBytesRead
        )
        return destinationHash
    }

    private func computeFileHashSync(
        path: String,
        algorithm: FilmCanHashAlgorithm,
        shouldCancel: @Sendable () -> Bool,
        progressCallback: @Sendable (Int64) -> Void
    ) throws -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw FileCopyError.sourceNotReadable(path)
        }
        defer { try? handle.close() }

        let bufferSize = isExFATFilesystem(path: path) ? exfatBufferSize : defaultBufferSize
        guard let hasher = makeHasher(algorithm: algorithm) else {
            throw FileCopyError.copyFailed("xxHash128 unavailable. Ensure libxxhash is bundled.")
        }
        var caughtError: Error? = nil
        
        while true {
            let shouldContinue = autoreleasepool { () -> Bool in
                if shouldCancel() || Task.isCancelled {
                    caughtError = FileCopyError.cancelled
                    return false
                }
                
                let data: Data
                do {
                    guard let readData = try handle.read(upToCount: bufferSize), !readData.isEmpty else {
                        return false  // EOF
                    }
                    data = readData
                } catch {
                    caughtError = FileCopyError.copyFailed("Failed to read file for verification: \(error.localizedDescription)")
                    return false
                }
                
                hasher.update(data: data)
                progressCallback(Int64(data.count))
                return true
            }

            if let error = caughtError {
                throw error
            }
            if !shouldContinue {
                break
            }
        }
        
        return hasher.finalize()
    }

    private func makeHasher(algorithm: FilmCanHashAlgorithm) -> StreamingHasher? {
        switch algorithm {
        case .xxh128:
            return XXH128StreamingHasher()
        }
    }


    private func isExFATFilesystem(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeURLKey]),
           let volumeUrl = resourceValues.allValues[.volumeURLKey] as? URL {
            if let cached = exfatCache[volumeUrl.path] { return cached }
            let isExfat = DriveUtilities.isExFAT(path: volumeUrl.path)
            exfatCache[volumeUrl.path] = isExfat
            return isExfat
        }
        return DriveUtilities.isExFAT(path: path)
    }

    private func copyFileAttributes(from source: String, to destination: String) throws {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: source) else { return }

        if let modDate = attrs[.modificationDate] as? Date {
            try? fm.setAttributes([.modificationDate: modDate], ofItemAtPath: destination)
        }
        if let permissions = attrs[.posixPermissions] as? NSNumber {
            try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination)
        }
    }
}
