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

    /// Thrown from `finalize` when `conflictPolicy == .skip` and the destination
    /// file already exists. Caller should treat the file as skipped, not failed.
    struct SkippedDueToConflict: Swift.Error {}

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
    /// - `conflictPolicy`: when `.skip` and dest exists, throws `SkippedDueToConflict`.
    ///   When `.increment`, finds an unused name using `counterTemplate` (e.g. `"_001"`).
    @discardableResult
    func finalize(
        fileHash: String, sourceSize: Int64,
        conflictPolicy: OrganizationPreset.DuplicatePolicy = .overwrite,
        counterTemplate: String = "_001"
    ) throws -> String {
        guard !finalized, let tempURL = tempFileURL, let handle = writeHandle else { return destPath }

        let destURL = URL(fileURLWithPath: destPath)

        if conflictPolicy == .skip && fm.fileExists(atPath: destURL.path) {
            finalized = true
            try? handle.close()
            writeHandle = nil
            try? fm.removeItem(at: tempURL)
            tempFileURL = nil
            throw SkippedDueToConflict()
        }

        let effectiveDestURL: URL
        if conflictPolicy == .increment && fm.fileExists(atPath: destURL.path) {
            effectiveDestURL = Self.findUnusedPath(base: destURL, template: counterTemplate)
        } else {
            effectiveDestURL = destURL
        }

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

        // POSIX rename(2) — atomic within the same volume
        let ok = tempURL.withUnsafeFileSystemRepresentation { tRep in
            effectiveDestURL.withUnsafeFileSystemRepresentation { dRep in
                guard let t = tRep, let d = dRep else { return false }
                return Darwin.rename(t, d) == 0
            }
        }

        guard ok else {
            throw WriterError.finalizeFailed("rename(2) failed for \(effectiveDestURL.path)")
        }

        return effectiveDestURL.path
    }

    private static func findUnusedPath(base: URL, template: String) -> URL {
        let dir = base.deletingLastPathComponent()
        let ext = base.pathExtension
        let stem = base.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let suffix = String(format: "%03d", counter)
            let candidate = ext.isEmpty
                ? dir.appendingPathComponent("\(stem)\(template.replacingOccurrences(of: "001", with: suffix))")
                : dir.appendingPathComponent("\(stem)\(template.replacingOccurrences(of: "001", with: suffix)).\(ext)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            counter += 1
            if counter > 999 { return candidate }
        }
    }

    /// Append this file's hash to the per-destination MHL.
    func appendMHL(hash: String, fileName: String, size: Int64, mtime: Int64?) async throws {
        try await mhlWriter?.append(relPath: fileName, size: size, hash: hash, mtime: mtime)
        try await mhlWriter?.flush()
    }

    deinit {
        if !finalized, let tempURL = tempFileURL {
            try? writeHandle?.close()
            try? fm.removeItem(at: tempURL)
        }
    }
}
