import Foundation
import Darwin
import os

/// Receives chunks via actor-safe methods, writes to a temp file,
/// then atomically renames to the final destination on finalize.
actor DestWriter {
    enum WriterError: Swift.Error, LocalizedError {
        case createFailed(String)
        case writeFailed(String)
        case finalizeFailed(String)

        var errorDescription: String? {
            switch self {
            case .createFailed(let s): return "Create failed: \(s)"
            case .writeFailed(let s): return "Write failed: \(s)"
            case .finalizeFailed(let s): return "Finalize failed: \(s)"
            }
        }
    }

    struct Config {
        var destPath: String
        var displayName: String
        var verifyMode: VerifyMode
        var requiresFullFsync: Bool
        var chunkSize: Int?
    }

    private let destPath: String
    private let displayName: String
    private let verifyMode: VerifyMode
    private let requiresFullFsync: Bool
    private let mhlWriter: (any MHLWriting)?

    private var tempFileURL: URL?
    private var writeHandle: FileHandle?
    private var finalized = false

    private let fm = FileManager.default

    /// Accepts a pre-built MHL writer so multiple DestWriter instances writing into
    /// the same source root share one aggregator (avoids the last-writer-wins race
    /// over a single manifest file). The writer is either an `ASCMHLWriter` or a
    /// `SimpleMHLWriter` depending on the configured hash-list style.
    init(
        destPath: String,
        displayName: String,
        verifyMode: VerifyMode,
        requiresFullFsync: Bool,
        sharedMHLWriter: (any MHLWriting)?
    ) async throws {
        self.destPath = destPath
        self.displayName = displayName
        self.verifyMode = verifyMode
        self.requiresFullFsync = requiresFullFsync
        self.mhlWriter = sharedMHLWriter

        try setupTempFile()
    }

    private func setupTempFile() throws {
        let destURL = URL(fileURLWithPath: destPath)
        let parent = destURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let tempName = ".filmcan-\(uuid)-\(destURL.lastPathComponent)"
        let tempURL = parent.appendingPathComponent(tempName)

        guard fm.createFile(atPath: tempURL.path, contents: nil) else {
            throw WriterError.createFailed(tempURL.path)
        }
        tempFileURL = tempURL

        let handle = try FileHandle(forWritingTo: tempURL)
        // F_NOCACHE: backup writes are write-once and not re-read on this path
        // (the paranoid verify opens its own handle). Without it, writing a
        // multi-hundred-GB destination fills the unified buffer cache and, with
        // the equally-large source read, drives the system into memory pressure
        // (observed >30 GB, crash). Large sequential writes stay fast; durability
        // is still ensured by F_FULLFSYNC / synchronize() in finalize().
        _ = fcntl(handle.fileDescriptor, F_NOCACHE, 1)
        writeHandle = handle
    }

    /// Append a data chunk to the temp file.
    func write(data: Data) throws {
        guard let handle = writeHandle else {
            throw WriterError.writeFailed("No write handle (already finalized?)")
        }
        try handle.write(contentsOf: data)
    }

    /// Flush, fsync, close, then atomically rename temp → final destination.
    func finalize(fileHash: String, sourceSize: Int64) throws {
        guard !finalized, let tempURL = tempFileURL, let handle = writeHandle else { return }
        finalized = true

        if requiresFullFsync {
            let fd = handle.fileDescriptor
            if fcntl(fd, F_FULLFSYNC) == -1 {
                os_log(
                    "F_FULLFSYNC not honored on %{public}@ (errno=%d), falling back to fsync — drive cache flush not guaranteed",
                    log: OSLog(subsystem: "com.filmcan.app", category: "DestWriter"),
                    type: .error,
                    destPath,
                    errno
                )
                fsync(fd)
            }
        } else {
            try handle.synchronize()
        }

        try handle.close()
        writeHandle = nil

        let destURL = URL(fileURLWithPath: destPath)

        // POSIX rename(2) — atomic within the same volume
        let ok = tempURL.withUnsafeFileSystemRepresentation { tRep in
            destURL.withUnsafeFileSystemRepresentation { dRep in
                guard let t = tRep, let d = dRep else { return false }
                return Darwin.rename(t, d) == 0
            }
        }

        guard ok else {
            throw WriterError.finalizeFailed("rename(2) failed for \(destURL.path)")
        }
    }

    /// Append this file's hash to the per-destination MHL.
    func appendMHL(hash: String, fileName: String, size: Int64) async throws {
        try await mhlWriter?.append(relPath: fileName, size: size, hash: hash)
        try await mhlWriter?.flush()
    }

    deinit {
        if !finalized, let tempURL = tempFileURL {
            try? writeHandle?.close()
            try? fm.removeItem(at: tempURL)
        }
    }
}
