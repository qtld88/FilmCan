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
        case sizeMismatch(written: Int64, expected: Int64)

        var errorDescription: String? {
            switch self {
            case .createFailed(let s): return "Create failed: \(s)"
            case .writeFailed(let s): return "Write failed: \(s)"
            case .finalizeFailed(let s): return "Finalize failed: \(s)"
            case .sizeMismatch(let written, let expected):
                return "Incomplete file: \(written) bytes written, \(expected) expected"
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

    private var tempFileURL: URL?
    private var tempName: String?
    private var writeHandle: FileHandle?
    private var finalized = false
    /// Bytes appended to the temp file so far; `finalize` refuses to rename the
    /// temp into place unless this matches the expected size.
    private var bytesWritten: Int64 = 0

    private let fm = FileManager.default

    /// Writes one file. Hash lists are recorded by the verify lane in `FanOutCopier`,
    /// not here.
    init(
        destPath: String,
        displayName: String,
        verifyMode: VerifyMode,
        requiresFullFsync: Bool
    ) async throws {
        self.destPath = destPath
        self.displayName = displayName
        self.verifyMode = verifyMode
        self.requiresFullFsync = requiresFullFsync

        try await setupTempFile()
    }

    private func setupTempFile() async throws {
        let destURL = URL(fileURLWithPath: destPath)
        let parent = destURL.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let tempName = ".filmcan-\(uuid)-\(destURL.lastPathComponent)"
        let tempURL = parent.appendingPathComponent(tempName)

        // Register the name BEFORE the file exists on disk, so a concurrent run's
        // OrphanCleaner can never see this temp un-registered and delete it
        // mid-write (TOCTOU). Unregister on the create-failure path.
        await OrphanCleaner.shared.registerActive(tempName)
        let created = IOPerfProbe.shared.measure(.tempCreate, key: displayName) {
            fm.createFile(atPath: tempURL.path, contents: nil)
        }
        guard created else {
            await OrphanCleaner.shared.unregisterActive(tempName)
            throw WriterError.createFailed(tempURL.path)
        }
        tempFileURL = tempURL
        self.tempName = tempName

        let handle = try IOPerfProbe.shared.measure(.tempCreate, key: displayName) {
            try FileHandle(forWritingTo: tempURL)
        }
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
        // Own pool: called from an async loop that may not suspend between chunks,
        // so anything the write bridges or autoreleases must not pile up for the run.
        try IOPerfProbe.shared.measure(.destWrite, key: displayName, bytes: Int64(data.count)) {
            try autoreleasepool { try handle.write(contentsOf: data) }
        }
        bytesWritten += Int64(data.count)
    }

    /// Close and delete the temp file without renaming it. Used when the file
    /// must not land under its final name (e.g. the source read failed).
    func discard() {
        guard !finalized, let tempURL = tempFileURL else { return }
        finalized = true
        try? writeHandle?.close()
        writeHandle = nil
        try? fm.removeItem(at: tempURL)
        tempFileURL = nil
        if let n = tempName { Task { await OrphanCleaner.shared.unregisterActive(n) } }
    }

    /// Flush, fsync, close, then atomically rename temp → final destination.
    /// - `sourceSize`: the source's byte count (logical size). When the bytes
    ///   written differ, the temp is deleted and `WriterError.sizeMismatch` is
    ///   thrown — an incomplete file never lands under its final name.
    /// - `conflictPolicy`: when `.skip` and dest exists, throws `SkippedDueToConflict`.
    ///   When `.increment`, finds an unused name using `counterTemplate` (e.g. `"_001"`).
    @discardableResult
    func finalize(
        fileHash: String, sourceSize: Int64,
        conflictPolicy: OrganizationPreset.DuplicatePolicy = .overwrite,
        counterTemplate: String = "_001"
    ) throws -> String {
        guard !finalized, let tempURL = tempFileURL, let handle = writeHandle else { return destPath }

        if bytesWritten != sourceSize {
            let written = bytesWritten
            discard()
            throw WriterError.sizeMismatch(written: written, expected: sourceSize)
        }

        let destURL = URL(fileURLWithPath: destPath)

        if conflictPolicy == .skip && fm.fileExists(atPath: destURL.path) {
            finalized = true
            try? handle.close()
            writeHandle = nil
            try? fm.removeItem(at: tempURL)
            tempFileURL = nil
            if let n = tempName { Task { await OrphanCleaner.shared.unregisterActive(n) } }
            throw SkippedDueToConflict()
        }

        let effectiveDestURL: URL
        if conflictPolicy == .increment && fm.fileExists(atPath: destURL.path) {
            effectiveDestURL = Self.findUnusedPath(base: destURL, template: counterTemplate)
        } else {
            effectiveDestURL = destURL
        }

        // Any failure from here on (flush, close, rename) must not leave the temp
        // behind: it is removed and unregistered before the error propagates.
        // `finalized` is set only once the file is under its final name.
        do {
            try flushCloseAndRename(handle: handle, tempURL: tempURL, to: effectiveDestURL)
        } catch {
            abandonTemp(tempURL)
            throw error
        }
        finalized = true
        tempFileURL = nil

        if let n = tempName { Task { await OrphanCleaner.shared.unregisterActive(n) } }
        return effectiveDestURL.path
    }

    private func abandonTemp(_ tempURL: URL) {
        finalized = true
        try? writeHandle?.close()
        writeHandle = nil
        try? fm.removeItem(at: tempURL)
        tempFileURL = nil
        if let n = tempName { Task { await OrphanCleaner.shared.unregisterActive(n) } }
    }

    private func flushCloseAndRename(handle: FileHandle, tempURL: URL, to effectiveDestURL: URL) throws {
        try IOPerfProbe.shared.measure(.flush, key: displayName) {
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
        }

        try handle.close()
        writeHandle = nil

        // POSIX rename(2) — atomic within the same volume
        let ok = IOPerfProbe.shared.measure(.rename, key: displayName) {
            tempURL.withUnsafeFileSystemRepresentation { tRep in
                effectiveDestURL.withUnsafeFileSystemRepresentation { dRep in
                    guard let t = tRep, let d = dRep else { return false }
                    return Darwin.rename(t, d) == 0
                }
            }
        }

        guard ok else {
            throw WriterError.finalizeFailed("rename(2) failed for \(effectiveDestURL.path)")
        }
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

    deinit {
        if !finalized, let tempURL = tempFileURL {
            try? writeHandle?.close()
            try? fm.removeItem(at: tempURL)
        }
        if let n = tempName {
            Task { await OrphanCleaner.shared.unregisterActive(n) }
        }
    }
}
