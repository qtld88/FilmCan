import Foundation
import Combine
#if canImport(Darwin)
import Darwin
#endif

enum RsyncError: LocalizedError {
    case sourceNotFound(String)
    case destinationNotFound(String)
    case invalidOptions(String)
    case executionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path):   return "Source not found: \(path)"
        case .destinationNotFound(let p): return "Destination not found: \(p)"
        case .invalidOptions(let msg):    return "Invalid rsync options: \(msg)"
        case .executionFailed(let msg):   return "rsync failed: \(msg)"
        case .cancelled:                  return "Transfer was cancelled"
        }
    }
}

// MARK: - Background Size Calculation Helpers (nonisolated)

/// Calculate total size of multiple sources asynchronously on background thread
private func calculateTotalSizeAsync(sources: [String]) async -> Int64 {
    await Task.detached(priority: .utility) {
        var totalSize: Int64 = 0
        let fm = FileManager.default
        
        for source in sources {
            totalSize += calculateFolderSize(path: source, fileManager: fm)
        }
        return totalSize
    }.value
}

/// Calculate size of a single path (file or directory)
private func calculateFolderSize(path: String, fileManager: FileManager) -> Int64 {
    guard fileManager.fileExists(atPath: path) else { return 0 }
    
    var isDir: ObjCBool = false
    fileManager.fileExists(atPath: path, isDirectory: &isDir)
    
    if !isDir.boolValue {
        // Single file
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            return size
        }
        return 0
    }
    
    // Directory - use shell du command for efficiency (macOS-friendly flags)
    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
    task.arguments = ["-sk", "-A", path]
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    
    do {
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            // du -sk -A outputs: "12345\t/path/to/dir" (size in KB)
            let parts = output.split(separator: "\t", maxSplits: 1)
            if task.terminationStatus == 0,
               let sizeStr = parts.first,
               let sizeKB = Int64(sizeStr) {
                return sizeKB * 1024
            }
        }
    } catch {
        // Fallback: enumerate files manually (slower but reliable)
        return enumerateFolderSize(path: path, fileManager: fileManager)
    }
    
    // Fallback when du output is unavailable or invalid
    return enumerateFolderSize(path: path, fileManager: fileManager)
}

/// Calculate destination folder size asynchronously to avoid blocking the main actor.
private func calculateDestinationSizeAsync(path: String) async -> Int64 {
    await Task.detached(priority: .utility) {
        calculateFolderSize(path: path, fileManager: FileManager.default)
    }.value
}

/// Check if the destination path is still accessible (drive not disconnected)
private func isDestinationAccessible(path: String) -> Bool {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    let exists = fm.fileExists(atPath: path, isDirectory: &isDirectory)
    guard exists else { return false }
    guard isDirectory.boolValue else { return false }
    // Try to list contents to verify read access
    return (try? fm.contentsOfDirectory(atPath: path)) != nil
}

/// Fallback: enumerate folder manually (slower)
private func enumerateFolderSize(path: String, fileManager: FileManager) -> Int64 {
    var totalSize: Int64 = 0
    guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
    while let file = enumerator.nextObject() as? String {
        let filePath = (path as NSString).appendingPathComponent(file)
        if let attrs = try? fileManager.attributesOfItem(atPath: filePath),
           let size = attrs[.size] as? Int64,
           attrs[.type] as? FileAttributeType != .typeDirectory {
            totalSize += size
        }
    }
    return totalSize
}

@MainActor
class RsyncService: ObservableObject {
    @Published var progress = TransferProgress()

    private var currentProcess: Process?
    private var isCancelled = false
    private var isPaused = false
    private var stderrBuffer: String = ""
    private var errorFileHandle: FileHandle?
    private var outputFileHandle: FileHandle?
    private var stderrReadTask: Task<Void, Never>?
    private var transferStartTime: Date?
    private var lastInstantSpeedBytesPerSecond: Double = 0
    private var expectsChecksumPhase: Bool = false
    private var hasStartedCopying: Bool = false
    private var totalRegularFiles: Int = 0
    private var transferredRegularFiles: Int = 0
    private var sawStatsLines: Bool = false
    private var transferredFilePaths: Set<String> = []
    private var currentOutputRoot: String = ""
    private var sawItemizeOutput: Bool = false
    private var lastTerminationReason: Process.TerminationReason?
    private var didClearQuarantine: Bool = false
    private var hashListWriter: HashListWriter?
    private var hashListContinuation: AsyncStream<String>.Continuation?
    private var hashListTask: Task<Void, Never>?
    private var hashListPath: String?
    private var hashListWarning: String? = nil
    
    // Track destination folder size for cumulative progress
    private var initialDestinationSize: Int64 = 0
    private var destinationPath: String = ""
    private var maxRecordedBytes: Int64 = 0
    private lazy var rsyncURL: URL? = resolveRsyncURL()

    // MARK: - Reset (in-place)

    func resetProgress() {
        progress.isRunning = false
        progress.isCancelled = false
        progress.isPaused = false
        progress.bytesCompleted = 0
        progress.cumulativeBytes = 0
        progress.totalBytes = 0
        progress.filesCompleted = 0
        progress.filesTotal = 0
        progress.speedBytesPerSecond = 0
        progress.estimatedTimeRemaining = nil
        progress.verificationStartTime = nil
        progress.verificationEstimatedDuration = nil
        progress.verificationFilesCompleted = 0
        progress.verificationFilesTotal = 0
        progress.verificationCurrentFile = ""
        progress.verificationPhase = .idle
        progress.sourceHashingFilesCompleted = 0
        progress.sourceHashingFilesTotal = 0
        progress.sourceHashingCurrentFile = ""
        progress.sourceHashingActive = false
        progress.phase = .idle
        progress.copyingDone = false
        progress.currentFile = ""
        progress.completedFiles = []
        stderrBuffer = ""
        isPaused = false
        initialDestinationSize = 0
        destinationPath = ""
        maxRecordedBytes = 0
        transferStartTime = nil
        lastInstantSpeedBytesPerSecond = 0
        expectsChecksumPhase = false
        hasStartedCopying = false
        totalRegularFiles = 0
        transferredRegularFiles = 0
        sawStatsLines = false
        transferredFilePaths = []
        currentOutputRoot = ""
        sawItemizeOutput = false
        lastTerminationReason = nil
        hashListWriter = nil
        hashListContinuation = nil
        hashListTask?.cancel()
        hashListTask = nil
        hashListPath = nil
    }

    // MARK: - Helpers

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func computeFileCounts() -> (transferred: Int, total: Int, skipped: Int) {
        guard sawStatsLines else {
            return (0, 0, 0)
        }
        let transferred = max(0, transferredRegularFiles)
        let total = max(0, totalRegularFiles)
        return (transferred, total, max(0, total - transferred))
    }

    private func shouldPrehashSourcesForVerify(options: RsyncOptions) -> Bool {
        return options.postVerify
    }

    private func hasHashList(destinationRoot: String) -> Bool {
        let fm = FileManager.default
        let dirPaths = [
            FilmCanPaths.hashListPath(for: destinationRoot),
            (destinationRoot as NSString).appendingPathComponent(FilmCanPaths.hidden)
        ]
        for dirPath in dirPaths {
            if let entries = try? fm.contentsOfDirectory(atPath: dirPath),
               entries.contains(where: { $0.lowercased().hasSuffix(".xxh128") }) {
                return true
            }
        }
        let hiddenRoot = (destinationRoot as NSString).appendingPathComponent(FilmCanPaths.hidden)
        if let enumerator = fm.enumerator(atPath: hiddenRoot) {
            for case let file as String in enumerator {
                if file.lowercased().hasSuffix(".xxh128") {
                    return true
                }
            }
        }
        return false
    }

    private func configureHashListStreaming(hashListPath: String?) {
        hashListWriter = nil
        hashListContinuation = nil
        hashListTask?.cancel()
        hashListTask = nil
        self.hashListPath = hashListPath
        hashListWarning = nil
        guard let hashListPath, let writer = HashListWriter(outputPath: hashListPath, algorithm: .xxh128) else { return }
        hashListWriter = writer
        let stream = AsyncStream<String> { continuation in
            self.hashListContinuation = continuation
        }
        hashListTask = Task.detached(priority: .utility) {
            for await path in stream {
                if Task.isCancelled { break }
                if let hash = Hashing.hash(for: URL(fileURLWithPath: path), algorithm: .xxh128) {
                    await writer.append(hashHex: hash, path: path)
                }
            }
        }
    }

    private func enqueueHashListPath(_ path: String) {
        guard hashListWriter != nil else { return }
        hashListContinuation?.yield(path)
    }

    private func finalizeHashList(success: Bool) async -> String? {
        hashListContinuation?.finish()
        if let hashListTask {
            _ = await hashListTask.value
        }
        guard let writer = hashListWriter else {
            return nil
        }
        if !success {
            await writer.removeFile()
            return nil
        }
        if let error = await writer.errorMessage() {
            hashListWarning = "Hash list could not be written: \(error)"
            await writer.removeFile()
            return nil
        }
        let count = await writer.count()
        if count == 0 {
            await writer.removeFile()
            return nil
        }
        await writer.close()
        return hashListPath
    }

    private struct SourceFileEntry {
        let sourceRoot: String
        let sourcePath: String
        let relativePath: String
        let sourceIsDirectory: Bool
    }

    nonisolated private static func sourceEntryKey(sourceRoot: String, relativePath: String) -> String {
        sourceRoot + "||" + relativePath
    }

    private func enumerateSourceEntries(sources: [String]) async -> [SourceFileEntry] {
        await Task.detached(priority: .utility) {
            var entries: [SourceFileEntry] = []
            let fm = FileManager.default
            for source in sources {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }
                let sourceURL = URL(fileURLWithPath: source).standardizedFileURL
                let sourceRoot = sourceURL.path
                if isDir.boolValue {
                    let enumerator = fm.enumerator(
                        at: sourceURL,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                    while let fileURL = enumerator?.nextObject() as? URL {
                        let standardized = fileURL.standardizedFileURL.path
                        if FilmCanPaths.isHidden(standardized) { continue }
                        if fileURL.lastPathComponent == ".DS_Store" { continue }
                        if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                           values.isDirectory == true {
                            continue
                        }
                        var relative = standardized
                        if standardized.hasPrefix(sourceRoot) {
                            relative = String(standardized.dropFirst(sourceRoot.count))
                            if relative.hasPrefix("/") {
                                relative.removeFirst()
                            }
                        }
                        if relative.isEmpty {
                            relative = fileURL.lastPathComponent
                        }
                        entries.append(SourceFileEntry(
                            sourceRoot: sourceRoot,
                            sourcePath: standardized,
                            relativePath: relative,
                            sourceIsDirectory: true
                        ))
                    }
                } else {
                    let relative = sourceURL.lastPathComponent
                    entries.append(SourceFileEntry(
                        sourceRoot: sourceRoot,
                        sourcePath: sourceRoot,
                        relativePath: relative,
                        sourceIsDirectory: false
                    ))
                }
            }
            return entries
        }.value
    }

    nonisolated private static func destinationPath(
        for entry: SourceFileEntry,
        destinationRoot: String,
        copyFolderContents: Bool,
        organizationRoots: [String: String]
    ) -> String {
        let base: String
        if let orgRoot = organizationRoots[entry.sourceRoot] {
            base = orgRoot
        } else if entry.sourceIsDirectory {
            if copyFolderContents {
                base = destinationRoot
            } else {
                base = (destinationRoot as NSString).appendingPathComponent(
                    (entry.sourceRoot as NSString).lastPathComponent
                )
            }
        } else {
            base = destinationRoot
        }
        return (base as NSString).appendingPathComponent(entry.relativePath)
    }

    private func hashEntries(
        _ entries: [SourceFileEntry],
        progressHandler: @escaping (Int, Int, String) -> Void
    ) async -> [String: String] {
        var hashes: [String: String] = [:]
        let total = entries.count
        var completed = 0
        let batchSize = 8
        let batches = stride(from: 0, to: entries.count, by: batchSize).map {
            Array(entries[$0..<min($0 + batchSize, entries.count)])
        }

        for batch in batches {
            if Task.isCancelled { break }
            await withTaskGroup(of: (String, String?, String).self) { group in
                for entry in batch {
                    group.addTask {
                        let url = URL(fileURLWithPath: entry.sourcePath)
                        let hash = Hashing.hash(for: url, algorithm: .xxh128)
                        let key = Self.sourceEntryKey(sourceRoot: entry.sourceRoot, relativePath: entry.relativePath)
                        return (key, hash, entry.relativePath)
                    }
                }
                for await (key, hash, relativePath) in group {
                    if let hash {
                        hashes[key] = hash
                    }
                    completed += 1
                    progressHandler(completed, total, relativePath)
                }
            }
        }
        return hashes
    }

    private func verifyEntries(
        _ entries: [SourceFileEntry],
        destinationRoot: String,
        copyFolderContents: Bool,
        organizationRoots: [String: String],
        sourceHashes: [String: String]
    ) async -> [String] {
        await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [] }
            var mismatches: [String] = []
            var completed = 0
            for entry in entries {
                if await MainActor.run(body: { self.isCancelled }) { break }
                let key = Self.sourceEntryKey(sourceRoot: entry.sourceRoot, relativePath: entry.relativePath)
                let sourceHash = sourceHashes[key] ?? Hashing.hash(for: URL(fileURLWithPath: entry.sourcePath), algorithm: .xxh128)
                let destPath = Self.destinationPath(
                    for: entry,
                    destinationRoot: destinationRoot,
                    copyFolderContents: copyFolderContents,
                    organizationRoots: organizationRoots
                )
                let destHash = Hashing.hash(for: URL(fileURLWithPath: destPath), algorithm: .xxh128)
                if sourceHash == nil || destHash == nil || sourceHash != destHash {
                    mismatches.append(entry.relativePath)
                }
                completed += 1
                let currentCompleted = completed
                let currentFile = entry.relativePath
                await MainActor.run {
                    self.progress.verificationFilesCompleted = currentCompleted
                    self.progress.verificationCurrentFile = currentFile
                }
            }
            return mismatches
        }.value
    }

    private func startSourceHashingTask(
        sources: [String]
    ) -> Task<(entries: [SourceFileEntry], hashes: [String: String]), Never> {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return ([], [:]) }
            await MainActor.run {
                self.progress.sourceHashingActive = true
                self.progress.sourceHashingFilesCompleted = 0
                self.progress.sourceHashingFilesTotal = 0
                self.progress.sourceHashingCurrentFile = ""
            }
            let entries = await self.enumerateSourceEntries(sources: sources)
            await MainActor.run {
                self.progress.sourceHashingFilesTotal = entries.count
            }
            let hashes = await self.hashEntries(entries) { completed, total, relativePath in
                Task { @MainActor in
                    self.progress.sourceHashingFilesCompleted = completed
                    self.progress.sourceHashingFilesTotal = total
                    self.progress.sourceHashingCurrentFile = relativePath
                }
            }
            await MainActor.run {
                self.progress.sourceHashingActive = false
            }
            return (entries, hashes)
        }
    }

    private func performRsyncVerification(
        sources: [String],
        destination: String,
        options: RsyncOptions,
        logFile: String?,
        finalResult: inout TransferResult
    ) async {
        progress.verificationPhase = .verifying
        progress.verificationFilesCompleted = 0
        progress.verificationFilesTotal = 0
        progress.verificationCurrentFile = ""

        var verifyArgs: [String] = ["--checksum", "--dry-run", "--quiet", "-r", "--out-format=%i"]
        verifyArgs.append("--checksum-choice=xxh128")
        verifyArgs.append(contentsOf: RsyncOptions.defaultExcludeArgs())
        verifyArgs.append(contentsOf: sources)
        verifyArgs.append(destination.hasSuffix("/") ? destination : destination + "/")

        #if DEBUG
        DebugLog.info("VERIFY COMMAND: \(rsyncPathString()) \(verifyArgs.joined(separator: " "))")
        #endif

        let verifyTask = Process()
        let verifyPipe = Pipe()
        guard let rsyncURL else {
            finalResult.success = false
            finalResult.errorMessage = "rsync not found for verification."
            return
        }
        verifyTask.executableURL = rsyncURL
        verifyTask.arguments = verifyArgs
        verifyTask.standardOutput = verifyPipe
        verifyTask.standardError  = verifyPipe

        do {
            try verifyTask.run()
            let data = verifyPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                verifyTask.terminationHandler = { _ in c.resume() }
            }
            let lines = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let itemizePrefixes: Set<Character> = ["<", ">", "c", "h", ".", "*"]
            let itemizeTypes: Set<Character> = ["f", "d", "L", "D", "S", "."]
            let diffLines = lines.filter { line in
                guard line.count >= 2 else { return false }
                let chars = Array(line)
                return itemizePrefixes.contains(chars[0]) && itemizeTypes.contains(chars[1])
            }

            let errorLines = lines.filter { line in
                let lower = line.lowercased()
                return lower.contains("rsync:") || lower.contains("error") || lower.contains("failed")
            }

            if !diffLines.isEmpty {
                finalResult.success = false
                finalResult.errorMessage = "Post-copy verification failed: files differ between source and destination"
                appendVerificationLog(
                    logFile: logFile,
                    title: "Verification differences",
                    lines: diffLines
                )
            } else if verifyTask.terminationStatus != 0 && !errorLines.isEmpty {
                finalResult.success = false
                finalResult.errorMessage = "Post-copy verification failed: \(errorLines.first ?? "Unknown error")"
                appendVerificationLog(
                    logFile: logFile,
                    title: "Verification error",
                    lines: errorLines
                )
            } else if verifyTask.terminationStatus != 0 {
                appendVerificationLog(
                    logFile: logFile,
                    title: "Verification warning",
                    lines: lines
                )
            }
        } catch {
            #if DEBUG
            DebugLog.warn("Verification error: \(error.localizedDescription)")
            #endif
        }

        progress.verificationPhase = .complete
        progress.verificationCurrentFile = ""
    }

    /// Calculate total size of source files in background BEFORE transfer starts.
    /// This runs on a background thread and updates progress.totalBytes once complete.
    private func preCalculateSourceSize(sources: [String]) async -> Int64 {
        // Run entirely on background - use nonisolated helper
        return await calculateTotalSizeAsync(sources: sources)
    }

    // MARK: - Main transfer

    func runRsync(
        sources: [String],
        destination: String,
        options: RsyncOptions,
        logFile: String?,
        hashListPath: String?,
        organizationPreset: OrganizationPreset?,
        copyFolderContents: Bool,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        duplicateCounterTemplate: String,
        reuseInfo: OrganizationReuseInfo?,
        duplicateResolver: (@Sendable (DuplicatePrompt) async -> DuplicateResolution)?
    ) async throws -> TransferResult {
        isCancelled = false
        isPaused = false
        resetProgress()
        progress.isRunning = true
        progress.isPaused = false
        expectsChecksumPhase = options.useChecksum
        progress.phase = expectsChecksumPhase ? .checksumming : .copying
        transferStartTime = Date()

        let fm = FileManager.default

        for source in sources {
            guard fm.fileExists(atPath: source) else {
                progress.isRunning = false
                throw RsyncError.sourceNotFound(source)
            }
        }

        var finalResult = TransferResult(
            configurationName: "",
            destination: destination,
            startTime: Date()
        )
        var organizationRoots: [String: String] = [:]
        var duplicateHits = 0
        var skippedByPolicy = 0
        var presetName: String? = nil
        var presetPolicy: OrganizationPreset.DuplicatePolicy? = nil
        var activeDuplicatePolicy = duplicatePolicy
        var activeDuplicateCounterTemplate = duplicateCounterTemplate

        if !fm.fileExists(atPath: destination) {
            try? fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
        }

        // Store destination path and calculate initial size BEFORE rsync starts
        destinationPath = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
        currentOutputRoot = destinationPath
        initialDestinationSize = await calculateDestinationSizeAsync(path: destinationPath)
        configureHashListStreaming(hashListPath: hashListPath)

        // Pre-calculate source size BEFORE starting rsync (runs in background)
        let sourceSizeTask = Task {
            await self.preCalculateSourceSize(sources: sources)
        }

        var sourceHashTask: Task<(entries: [SourceFileEntry], hashes: [String: String]), Never>? = nil
        let useParallelHashing = shouldPrehashSourcesForVerify(options: options)
        if useParallelHashing {
            sourceHashTask = startSourceHashingTask(sources: sources)
        }

        var baseArgs: [String] = []
        baseArgs.append(contentsOf: options.buildArgs())

        if let log = logFile, !log.isEmpty {
            let logDir = (log as NSString).deletingLastPathComponent
            var canUseLog = true

            if !logDir.isEmpty {
                if !fm.fileExists(atPath: logDir) {
                    do {
                        try fm.createDirectory(atPath: logDir, withIntermediateDirectories: true)
                    } catch {
                        #if DEBUG
                        DebugLog.warn("⚠️ Cannot create log directory: \(error.localizedDescription)")
                        #endif
                        canUseLog = false
                    }
                }

                if canUseLog {
                    let testPath = (logDir as NSString).appendingPathComponent(".filmcan_write_test")
                    canUseLog = fm.createFile(atPath: testPath, contents: nil)
                    if canUseLog {
                        try? fm.removeItem(atPath: testPath)
                    } else {
                        #if DEBUG
                        DebugLog.warn("⚠️ Cannot write to log directory: \(logDir)")
                        #endif
                    }
                }
            }

            if canUseLog {
                baseArgs.append("--log-file=\(log)")
            } else {
                #if DEBUG
                DebugLog.warn("⚠️ Skipping log file due to permission issues")
                #endif
            }
        }

        if let preset = organizationPreset {
            presetName = preset.name
            presetPolicy = duplicatePolicy
            baseArgs.append(contentsOf: buildFilterArgs(preset))
        }

        let sourceSize = await sourceSizeTask.value
        if sourceSize > 0 {
            progress.totalBytes = sourceSize
        }

        // Progress monitoring - use du -sk -A to track cumulative bytes transferred
        let progressTask = Task {
            while !Task.isCancelled && self.progress.isRunning {
                try? await Task.sleep(nanoseconds: 1_500_000_000)

                // Check if destination drive is still accessible
                if !isDestinationAccessible(path: self.destinationPath) {
                    self.progress.hasError = true
                    self.progress.currentError = "Destination drive disconnected or unavailable"
                    self.progress.isRunning = false
                    self.currentProcess?.terminate()
                    break
                }

                let currentSize = await calculateDestinationSizeAsync(path: self.destinationPath)
                let newBytes = currentSize - self.initialDestinationSize
                let monotonicBytes = max(self.maxRecordedBytes, max(0, newBytes))
                self.maxRecordedBytes = monotonicBytes
                self.progress.cumulativeBytes = monotonicBytes

                if self.progress.totalBytes > 0 && monotonicBytes > 0 {
                    self.progress.bytesCompleted = monotonicBytes

                    if let start = self.transferStartTime {
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed > 0 {
                            let averageSpeed = Double(monotonicBytes) / elapsed
                            let minBytesForEstimate: Int64 = 1_048_576
                            let minElapsedForEstimate: TimeInterval = 2.0
                            let minSpeedForEstimate: Double = 10 * 1024

                            if monotonicBytes >= minBytesForEstimate && elapsed >= minElapsedForEstimate && averageSpeed >= minSpeedForEstimate {
                                self.progress.speedBytesPerSecond = averageSpeed
                                let remaining = self.progress.totalBytes - monotonicBytes
                                if remaining > 0 {
                                    let eta = Double(remaining) / averageSpeed
                                    let maxEta: Double = 24 * 60 * 60
                                    if eta <= maxEta {
                                        self.progress.estimatedTimeRemaining = eta
                                    }
                                } else {
                                    self.progress.estimatedTimeRemaining = nil
                                }
                            } else if self.lastInstantSpeedBytesPerSecond > 0 {
                                self.progress.speedBytesPerSecond = self.lastInstantSpeedBytesPerSecond
                            }
                        }
                    } else if self.lastInstantSpeedBytesPerSecond > 0 {
                        self.progress.speedBytesPerSecond = self.lastInstantSpeedBytesPerSecond
                    }
                }
            }
        }

        func runTask(arguments: [String]) async throws -> Int32 {
            let task = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()

            guard let rsyncURL else {
                throw RsyncError.executionFailed("rsync not found. FilmCan bundles Homebrew rsync (3.4.0+). Rebuild the app with Homebrew rsync installed, or install rsync via Homebrew.")
            }
            clearQuarantineIfNeeded(for: rsyncURL)
            task.executableURL = rsyncURL
            task.arguments = arguments
            task.standardOutput = outputPipe
            task.standardError = errorPipe

            currentProcess = task

            let stdoutHandle = outputPipe.fileHandleForReading
            let stderrHandle = errorPipe.fileHandleForReading
            outputFileHandle = stdoutHandle
            errorFileHandle = stderrHandle

            stdoutHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self?.parseRsyncOutput(text)
                }
            }

            stderrHandle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self?.stderrBuffer.append(text)
                    self?.parseRsyncOutput(text)
                }
            }

            do {
                try task.run()
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    task.terminationHandler = { _ in c.resume() }
                }
                self.lastTerminationReason = task.terminationReason
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                outputFileHandle = nil
                errorFileHandle = nil
                throw error
            }

            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil
            outputFileHandle = nil
            errorFileHandle = nil

            return task.terminationStatus
        }

        var exitCode: Int32 = 0

        do {
            if let preset = organizationPreset {
                let destinationRoot = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
                let shouldCheckHashList = activeDuplicatePolicy == .verify || activeDuplicatePolicy == .ask
                let hasHashIndex = shouldCheckHashList && hasHashList(destinationRoot: destinationRoot)
                let hashIndex = hasHashIndex ? loadLatestHashIndex(destinationRoot: destinationRoot) : [:]
                func resolveDuplicateAction(
                    sourcePath: String,
                    destinationPath: String,
                    isDirectory: Bool
                ) async -> DuplicateResolution {
                    if activeDuplicatePolicy != .ask {
                        if activeDuplicatePolicy == .verify {
                            if let duplicateResolver {
                                return await duplicateResolver(
                                    DuplicatePrompt(
                                        sourcePath: sourcePath,
                                        destinationPath: destinationPath,
                                        isDirectory: isDirectory,
                                        counterTemplate: activeDuplicateCounterTemplate,
                                        canVerifyWithHashList: hasHashIndex && !isDirectory,
                                        hashListMissing: !hasHashIndex
                                    )
                                )
                            }
                            return DuplicateResolution(
                                action: .overwrite,
                                applyToAll: false,
                                counterTemplate: nil
                            )
                        }
                        return DuplicateResolution(
                            action: activeDuplicatePolicy,
                            applyToAll: false,
                            counterTemplate: nil
                        )
                    }
                    guard let duplicateResolver else {
                        return DuplicateResolution(action: .skip, applyToAll: false, counterTemplate: nil)
                    }
                    let resolution = await duplicateResolver(
                        DuplicatePrompt(
                            sourcePath: sourcePath,
                            destinationPath: destinationPath,
                            isDirectory: isDirectory,
                            counterTemplate: activeDuplicateCounterTemplate,
                            canVerifyWithHashList: hasHashIndex && !isDirectory,
                            hashListMissing: !hasHashIndex
                        )
                    )
                    if resolution.applyToAll {
                        activeDuplicatePolicy = resolution.action
                        presetPolicy = resolution.action
                        if resolution.action == .increment,
                           let template = resolution.counterTemplate,
                           !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            activeDuplicateCounterTemplate = template
                        }
                    }
                    return resolution
                }
                for (index, source) in sources.enumerated() {
                    if isCancelled { break }
                    let counter = index + 1
                    let resolved = OrganizationTemplate.resolve(
                        preset: preset,
                        sourcePath: source,
                        destinationRoot: destinationRoot,
                        counter: counter,
                        date: Date()
                    )
                    let folderPath = resolved.folderPath.isEmpty
                        ? destinationRoot
                        : (destinationRoot as NSString).appendingPathComponent(resolved.folderPath)
                    try? fm.createDirectory(atPath: folderPath, withIntermediateDirectories: true)

                    let isDir = isDirectory(source)
                    let reuseRoot = reuseRootPath(
                        for: source,
                        destinationRoot: destinationRoot,
                        preset: preset,
                        reuseInfo: reuseInfo,
                        options: options
                    )

                    if isDir {
                        let parentFolder = folderPath
                        let parentExisted = fm.fileExists(atPath: parentFolder)
                        var targetFolder = copyFolderContents
                            ? parentFolder
                            : (parentFolder as NSString).appendingPathComponent(resolved.renamedItem)
                        let targetExisted = fm.fileExists(atPath: targetFolder)
                        var forceOverwrite = activeDuplicatePolicy == .overwrite || activeDuplicatePolicy == .verify
                            && (copyFolderContents ? parentExisted : targetExisted)

                        if !copyFolderContents {
                            if targetExisted {
                                duplicateHits += 1
                                let resolution = await resolveDuplicateAction(
                                    sourcePath: source,
                                    destinationPath: targetFolder,
                                    isDirectory: true
                                )
                                switch resolution.action {
                                case .skip:
                                    skippedByPolicy += 1
                                    continue
                                case .overwrite:
                                    forceOverwrite = true
                                    break
                                case .increment:
                                    let template = resolution.counterTemplate
                                        ?? activeDuplicateCounterTemplate
                                    targetFolder = uniqueFolderPath(targetFolder, template: template)
                                case .verify:
                                    forceOverwrite = true
                                    break
                                case .ask:
                                    break
                                }
                            }
                        }

                        try? fm.createDirectory(atPath: targetFolder, withIntermediateDirectories: true)
                        let sourcePath = source.hasSuffix("/") ? source : source + "/"
                        let destinationPath = targetFolder.hasSuffix("/") ? targetFolder : targetFolder + "/"
                        var args = baseArgs + reuseArgs(reuseRoot: reuseRoot, destinationRoot: targetFolder)
                        if forceOverwrite && !args.contains("--ignore-times") {
                            args.append("--ignore-times")
                        }
                        args.append(contentsOf: [sourcePath, destinationPath])
                        #if DEBUG
                        DebugLog.info("RSYNC COMMAND: \(rsyncPathString()) \(args.joined(separator: " "))")
                        #endif
                        currentOutputRoot = targetFolder
                        exitCode = try await runTask(arguments: args)
                        organizationRoots[source] = targetFolder
                    } else {
                        var destinationPath = (folderPath as NSString).appendingPathComponent(resolved.renamedItem)
                        let existed = fm.fileExists(atPath: destinationPath)
                        var overwriteThisFile = false
                        if existed {
                            duplicateHits += 1
                            let resolution = await resolveDuplicateAction(
                                sourcePath: source,
                                destinationPath: destinationPath,
                                isDirectory: false
                            )
                            switch resolution.action {
                            case .skip:
                                skippedByPolicy += 1
                                continue
                            case .overwrite:
                                overwriteThisFile = true
                                break
                            case .increment:
                                let template = resolution.counterTemplate
                                    ?? activeDuplicateCounterTemplate
                                destinationPath = uniqueFilePath(destinationPath, template: template)
                            case .verify:
                                if hasHashIndex {
                                    let normalizedDestination = URL(fileURLWithPath: destinationPath)
                                        .standardizedFileURL.path
                                    if let expectedHash = hashIndex[normalizedDestination],
                                       fm.fileExists(atPath: destinationPath),
                                       let sourceHash = Hashing.hash(for: URL(fileURLWithPath: source), algorithm: .xxh128),
                                       sourceHash.lowercased() == expectedHash.lowercased() {
                                        skippedByPolicy += 1
                                        continue
                                    }
                                }
                                overwriteThisFile = true
                                break
                            case .ask:
                                break
                            }
                        }
                        var args = baseArgs + reuseArgs(reuseRoot: reuseRoot, destinationRoot: folderPath)
                        if overwriteThisFile && existed && !args.contains("--ignore-times") {
                            args.append("--ignore-times")
                        }
                        args.append(contentsOf: [source, destinationPath])
                        #if DEBUG
                        DebugLog.info("RSYNC COMMAND: \(rsyncPathString()) \(args.joined(separator: " "))")
                        #endif
                        currentOutputRoot = (destinationPath as NSString).deletingLastPathComponent
                        exitCode = try await runTask(arguments: args)
                        organizationRoots[source] = folderPath
                    }

                    if exitCode != 0 { break }
                }
            } else {
                let destPath = destination.hasSuffix("/") ? destination : destination + "/"
                let adjustedSources = sources.map { source in
                    if isDirectory(source) {
                        if copyFolderContents {
                            return source.hasSuffix("/") ? source : source + "/"
                        }
                        return source.hasSuffix("/") ? String(source.dropLast()) : source
                    }
                    return source
                }
                let rsyncArgs = baseArgs + adjustedSources + [destPath]
                #if DEBUG
                DebugLog.info("RSYNC COMMAND: \(rsyncPathString()) \(rsyncArgs.joined(separator: " "))")
                #endif
                currentOutputRoot = destinationPath
                exitCode = try await runTask(arguments: rsyncArgs)
            }
        } catch {
            progressTask.cancel()
            progress.phase = .finished
            progress.isRunning = false
            finalResult.endTime = Date()
            finalResult.success = false
            finalResult.errorMessage = "Failed to launch rsync: \(error.localizedDescription)"
            return finalResult
        }

        progressTask.cancel()
        finalResult.organizationRoots = organizationRoots
        finalResult.totalBytes = progress.totalBytes

        func applySuccessStats() async {
            loadStatsFromLogIfNeeded(logFile: logFile)
            let counts = computeFileCounts()
            if counts.transferred > 0 || counts.total > 0 {
                finalResult.filesTransferred = counts.transferred
                finalResult.filesSkipped = counts.skipped
            }
            if skippedByPolicy > 0 {
                finalResult.filesSkipped += skippedByPolicy
            }
            if progress.totalBytes > 0 {
                let finalSize = await calculateDestinationSizeAsync(path: destinationPath)
                let finalCumulativeRaw = max(0, finalSize - initialDestinationSize)
                let finalCumulative = max(maxRecordedBytes, finalCumulativeRaw)
                progress.cumulativeBytes = finalCumulative
                progress.bytesCompleted = finalCumulative
                progress.cumulativeBytes = progress.totalBytes
                progress.bytesCompleted = progress.totalBytes
                finalResult.bytesTransferred = finalCumulative
            }
        }

        if isPaused {
            finalResult.success = false
            finalResult.wasPaused = true
            finalResult.errorMessage = "Paused by user"
        } else if isCancelled {
            finalResult.success = false
            finalResult.errorMessage = "Cancelled by user"
        } else if exitCode == 0 {
            finalResult.success = true
            await applySuccessStats()
        } else if exitCode == 23 && isIgnorablePermissionDenied(stderrBuffer) {
            finalResult.success = true
            finalResult.warningMessage = "Some protected macOS system folders were skipped due to permissions (expected on external drives)."
            await applySuccessStats()
        } else {
            finalResult.success = false
            loadStatsFromLogIfNeeded(logFile: logFile)
            let counts = computeFileCounts()
            if counts.transferred > 0 || counts.total > 0 {
                finalResult.filesTransferred = counts.transferred
                finalResult.filesSkipped = counts.skipped
            }
            if skippedByPolicy > 0 {
                finalResult.filesSkipped += skippedByPolicy
            }
            var baseError = parseRsyncError(exitCode: exitCode, stderr: stderrBuffer, logFile: logFile)
            let stderrSummary = stderrBuffer
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            if exitCode == 6, (logFile == nil || logFile?.isEmpty == true) {
                if let stderrSummary {
                    baseError = "Rsync error: \(stderrSummary)"
                } else {
                    baseError = "Rsync error (code 6) with logs disabled. No stderr output."
                }
            } else if let stderrSummary, !baseError.contains(stderrSummary) {
                baseError = baseError + " (" + stderrSummary + ")"
            }
            if exitCode == 23 {
                if counts.total > 0 {
                    let noun = counts.total == 1 ? "file" : "files"
                    finalResult.errorMessage = "\(baseError) (\(counts.transferred) of \(counts.total) \(noun) transferred)"
                } else if counts.transferred > 0 {
                    let noun = counts.transferred == 1 ? "file" : "files"
                    finalResult.errorMessage = "\(baseError) (\(counts.transferred) \(noun) transferred)"
                } else {
                    finalResult.errorMessage = baseError
                }
            } else {
                finalResult.errorMessage = baseError
            }
        }

        if let presetName {
            finalResult.organizationPresetName = presetName
        }
        if let presetPolicy {
            finalResult.duplicatePolicy = presetPolicy
        }
        if duplicateHits > 0 {
            finalResult.duplicateHits = duplicateHits
        }
        finalResult.transferredPaths = Array(transferredFilePaths)
        finalResult.usedItemizedOutput = sawItemizeOutput

        var verificationAttempted = false
        if options.postVerify && finalResult.success && !isCancelled && !isPaused {
            verificationAttempted = true
            progress.copyingDone = true
            progress.phase = .verifying
            progress.currentFile = "Comparing checksums..."
            progress.verificationPhase = .preparingFileList
            progress.verificationStartTime = Date()
            progress.verificationEstimatedDuration = nil
            progress.verificationFilesCompleted = 0
            progress.verificationFilesTotal = 0
            progress.verificationCurrentFile = ""

            if useParallelHashing {
                var entries: [SourceFileEntry] = []
                var sourceHashes: [String: String] = [:]
                if let sourceHashTask {
                    let result = await sourceHashTask.value
                    entries = result.entries
                    sourceHashes = result.hashes
                }
                if entries.isEmpty {
                    entries = await enumerateSourceEntries(sources: sources)
                }

                progress.verificationFilesTotal = entries.count
                progress.verificationPhase = .verifying

                let mismatches = await verifyEntries(
                    entries,
                    destinationRoot: destination,
                    copyFolderContents: copyFolderContents,
                    organizationRoots: organizationRoots,
                    sourceHashes: sourceHashes
                )

                if !mismatches.isEmpty {
                    finalResult.success = false
                    finalResult.errorMessage = "Post-copy verification failed: \(mismatches.count) files differ between source and destination"
                    appendVerificationLog(
                        logFile: logFile,
                        title: "Verification differences",
                        lines: mismatches
                    )
                }
                if !sourceHashes.isEmpty {
                    finalResult.sourceHashes = sourceHashes
                }

                progress.verificationPhase = .complete
                progress.verificationCurrentFile = ""
            } else {
                await performRsyncVerification(
                    sources: sources,
                    destination: destination,
                    options: options,
                    logFile: logFile,
                    finalResult: &finalResult
                )
            }

            progress.currentFile = ""
            progress.verificationStartTime = nil
            progress.verificationEstimatedDuration = nil
        }
        if !verificationAttempted {
            sourceHashTask?.cancel()
        }

        if verificationAttempted && finalResult.success {
            finalResult.wasVerified = true
        }

        if let path = await finalizeHashList(success: finalResult.success && !isCancelled && !isPaused) {
            finalResult.hashListPath = path
            finalResult.hashRoots = []
        }
        if let warning = hashListWarning {
            if let existing = finalResult.warningMessage, !existing.isEmpty {
                finalResult.warningMessage = existing + " " + warning
            } else {
                finalResult.warningMessage = warning
            }
        }

        finalResult.endTime = finalResult.endTime ?? Date()
        if !isPaused {
            if progress.phase == .copying { progress.copyingDone = true }
            progress.phase = .finished
        }
        progress.isRunning = false
        return finalResult
    }

    // MARK: - Cancel

    func cancel() {
        isCancelled = true
        currentProcess?.terminate()
        progress.isCancelled = true
        progress.isRunning = false
    }

    // MARK: - rsync path

    private func bundledRsyncURL() -> URL? {
        let fm = FileManager.default
        if let base = Bundle.main.resourceURL?.appendingPathComponent("rsync") {
            #if arch(arm64)
            let archPath = base.appendingPathComponent("rsync-arm64")
            #else
            let archPath = base.appendingPathComponent("rsync-x86_64")
            #endif
            if fm.isExecutableFile(atPath: archPath.path) {
                return archPath
            }
        }
        guard let bundled = Bundle.main.url(forResource: "rsync", withExtension: nil) else {
            return nil
        }
        return fm.isExecutableFile(atPath: bundled.path) ? bundled : nil
    }

    private func resolveRsyncURL() -> URL? {
        let fm = FileManager.default
        if let bundled = bundledRsyncURL() {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/rsync",
            "/usr/local/bin/rsync",
            "/usr/bin/rsync"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func rsyncPathString() -> String {
        rsyncURL?.path ?? "rsync"
    }

    private func clearQuarantineIfNeeded(for rsyncURL: URL) {
        if didClearQuarantine { return }
        let bundlePath = Bundle.main.bundlePath
        guard rsyncURL.path.hasPrefix(bundlePath) else { return }
        guard let resourceRoot = Bundle.main.resourceURL?.appendingPathComponent("rsync") else { return }
        let rootPath = resourceRoot.path
        removeQuarantine(at: rootPath)
        let fm = FileManager.default
        if let enumerator = fm.enumerator(atPath: rootPath) {
            for case let item as String in enumerator {
                let path = (rootPath as NSString).appendingPathComponent(item)
                removeQuarantine(at: path)
            }
        }
        didClearQuarantine = true
    }

    private func removeQuarantine(at path: String) {
        path.withCString { cPath in
            _ = removexattr(cPath, "com.apple.quarantine", 0)
        }
    }

    private func appendVerificationLog(logFile: String?, title: String, lines: [String]) {
        guard let logFile, !logFile.isEmpty else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: logFile) {
            fm.createFile(atPath: logFile, contents: nil)
        }
        let header = "\n[\(title)]\n"
        let body = lines.joined(separator: "\n")
        let text = header + body + "\n"
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: logFile)) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        }
    }

    // MARK: - Pause

    func pause() {
        isPaused = true
        currentProcess?.terminate()
        progress.isPaused = true
        progress.isRunning = false
    }

    // MARK: - Output parsing

    /// Parse a chunk of rsync stdout.
    ///
    /// rsync --progress emits three kinds of lines:
    ///   1. Filename (no leading space):            "path/to/file.mov"
    ///   2. Intermediate per-file progress (space): "      524,288,000  38%   52.3MB/s    0:03:12"
    ///   3. Per-file completion (space + to-chk):   "  1,374,389,248 100%   54.1MB/s    0:00:24 (xfr#1, to-chk=0/1)"
    ///
    /// The byte count on lines 2 and 3 is the running total for the *current* file.
    /// totalBytes is pre-seeded from the source size so the bar fills in real time.
    private func parseRsyncOutput(_ output: String) {
        let lines = output.components(separatedBy: CharacterSet.newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()

            if parseStatsLine(trimmed, lower: lower) { continue }

            if let itemizedPath = parseItemizedLine(trimmed) {
                if !itemizedPath.isEmpty {
                    progress.currentFile = itemizedPath
                }
                continue
            }

            // Skip summary / status lines
            let skipPrefixes = [
                "total file", "total transferred", "total bytes",
                "literal data", "matched data", "file list size",
                "file list generation", "file list transfer",
                "sent ", "received ", "total size", "speedup",
                "delta-transmission", "sending incremental file list",
                "building file list"
            ]
            if skipPrefixes.contains(where: { lower.hasPrefix($0) }) { continue }

            // Progress lines start with a space
            if line.first == " " {
                if !hasStartedCopying,
                   (trimmed.contains("%") || trimmed.contains("xfr#")) {
                    hasStartedCopying = true
                    if expectsChecksumPhase && progress.phase == .checksumming {
                        progress.phase = .copying
                    }
                }
                // First token is the current-file byte count (comma-formatted), e.g. "524,288,000"
                let tokens = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if let firstToken = tokens.first {
                    let digits = firstToken.replacingOccurrences(of: ",", with: "")
                    if let bytes = Int64(digits) {
                        progress.bytesCompleted = bytes
                    }
                }

                // Per-file completion: "... (xfr#N, to-chk=X/Y)"
                if trimmed.contains("to-chk="),
                   let range = trimmed.range(of: #"to-chk=(\d+)/(\d+)"#, options: .regularExpression) {
                    let sub = String(trimmed[range])
                    let after = sub.dropFirst("to-chk=".count)
                    let parts = after.components(separatedBy: "/")
                        if parts.count == 2,
                       let remaining = Int(parts[0]),
                       let total = Int(parts[1]) {
                        progress.filesCompleted = total - remaining
                        progress.filesTotal = total

                        if !progress.currentFile.isEmpty {
                            progress.completedFiles.insert(progress.currentFile, at: 0)
                            if progress.completedFiles.count > 50 { progress.completedFiles.removeLast() }
                        }
                    }
                }

                parseSpeedAndETA(from: trimmed)
                continue
            }

            // Skip directory entries
            if trimmed == "./" || trimmed == "." || trimmed.hasSuffix("/") { continue }

            // Everything else is a filename
            progress.currentFile = trimmed
        }
        
        // Detect critical errors in real-time
        let lower = output.lowercased()
        if !progress.hasError {  // Only set once
            let hasPermissionDenied = lower.contains("permission denied") || lower.contains("operation not permitted")
            let ignorePermissionDenied = hasPermissionDenied && isIgnorablePermissionDeniedOutput(output)
            if lower.contains("no such file or directory") ||
               lower.contains("input/output error") ||
               lower.contains("i/o error") ||
               lower.contains("no space left on device") ||
               lower.contains("disk full") ||
               (!ignorePermissionDenied && hasPermissionDenied) ||
               lower.contains("connection reset") ||
               lower.contains("host is down") ||
               lower.contains("device not configured") ||
               lower.contains("volume not online") {
                progress.hasError = true
                // Extract the most relevant error line
                let lines = output.components(separatedBy: .newlines)
                if let errorLine = lines.first(where: { line in
                    let l = line.lowercased()
                    return l.contains("error") || l.contains("denied") || l.contains("no space")
                }) {
                    progress.currentError = errorLine.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }

    private func parseItemizedLine(_ line: String) -> String? {
        if line.hasPrefix("FILMCAN\t") {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 3 else { return nil }
            let code = parts[1]
            guard isItemizeCode(code) else { return nil }
            sawItemizeOutput = true
            var path = parts.dropFirst(2).joined(separator: "\t")
            if let arrowRange = path.range(of: " -> ") {
                path = String(path[..<arrowRange.lowerBound])
            }
            if path.hasPrefix("./") {
                path = String(path.dropFirst(2))
            }
            if path.isEmpty || path == "." { return nil }
            if shouldRecordItemizedFile(code) {
                recordTransferredPath(path)
            }
            return path
        }

        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let code = String(parts[0])
        guard isItemizeCode(code) else { return nil }
        sawItemizeOutput = true
        var path = String(parts[1])
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[..<arrowRange.lowerBound])
        }
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        if path.isEmpty || path == "." { return nil }
        if shouldRecordItemizedFile(code) {
            recordTransferredPath(path)
        }
        return path
    }

    private func isItemizeCode(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        let prefixes: Set<Character> = [">", "<", "c", "h", ".", "*"]
        let types: Set<Character> = ["f", "d", "L", "D", "S", "."]
        return prefixes.contains(chars[0]) && types.contains(chars[1])
    }

    private func shouldRecordItemizedFile(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        guard chars[1] == "f" else { return false }
        return chars[0] == ">" || chars[0] == "c"
    }

    private func recordTransferredPath(_ path: String) {
        let cleaned = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        let resolved: String
        if cleaned.hasPrefix("/") {
            resolved = cleaned
        } else {
            resolved = (currentOutputRoot as NSString).appendingPathComponent(cleaned)
        }
        if FilmCanPaths.isHidden(resolved) { return }
        if resolved.hasSuffix("/") { return }
        let inserted = transferredFilePaths.insert(resolved).inserted
        if inserted {
            enqueueHashListPath(resolved)
        }
    }

    /// Extract speed and ETA from a progress line.
    private func parseSpeedAndETA(from line: String) {
        // Speed: "52.3MB/s"
        if let match = line.range(of: #"([\d.]+)(B|kB|MB|GB|TB)/s"#, options: .regularExpression) {
            let raw = String(line[match])
            let noUnit = String(raw.dropLast(2))
            var numStr = ""
            var unit = ""
            for ch in noUnit {
                if ch.isNumber || ch == "." { numStr.append(ch) } else { unit.append(ch) }
            }
            if let num = Double(numStr) {
                let factor: Double
                switch unit {
                case "B":  factor = 1
                case "kB": factor = 1_024
                case "MB": factor = 1_024 * 1_024
                case "GB": factor = 1_024 * 1_024 * 1_024
                case "TB": factor = 1_024 * 1_024 * 1_024 * 1_024
                default:   factor = 1
                }
                lastInstantSpeedBytesPerSecond = num * factor
            }
        }
    }

    private func parseStatsLine(_ line: String, lower: String) -> Bool {
        if lower.hasPrefix("number of files:") {
            sawStatsLines = true
            if let range = line.range(of: #"reg:\s*([\d,]+)"#, options: .regularExpression) {
                let matched = String(line[range])
                let digits = matched.replacingOccurrences(of: "reg:", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let value = Int(digits) { totalRegularFiles = value }
            }
            return true
        }

        if lower.hasPrefix("number of regular files transferred:") {
            sawStatsLines = true
            let parts = line.components(separatedBy: ":")
            if let last = parts.last {
                let digits = last.replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let value = Int(digits) { transferredRegularFiles = value }
            }
            return true
        }

        return false
    }

    private func loadStatsFromLogIfNeeded(logFile: String?) {
        guard totalRegularFiles == 0, transferredRegularFiles == 0 else { return }
        guard let logFile, let content = try? String(contentsOfFile: logFile, encoding: .utf8) else {
            return
        }
        for rawLine in content.split(separator: "\n") {
            let line = String(rawLine)
            if line.contains("Number of files:") {
                sawStatsLines = true
                if let range = line.range(
                    of: #"reg:\s*([\d,]+)"#,
                    options: .regularExpression
                ) {
                    let matched = String(line[range])
                    let digits = matched.replacingOccurrences(of: "reg:", with: "")
                        .replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let value = Int(digits) { totalRegularFiles = value }
                }
            } else if line.contains("Number of regular files transferred:") {
                sawStatsLines = true
                let parts = line.components(separatedBy: ":")
                if let last = parts.last {
                    let digits = last.replacingOccurrences(of: ",", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if let value = Int(digits) { transferredRegularFiles = value }
                }
            }

            if totalRegularFiles > 0 && transferredRegularFiles > 0 {
                break
            }
        }
    }

    private func buildFilterArgs(_ preset: OrganizationPreset) -> [String] {
        var args: [String] = []

        let include = preset.includePatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let exclude = preset.excludePatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let copyOnly = preset.copyOnlyPatterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !copyOnly.isEmpty {
            args.append("--include=*/")
            for pattern in copyOnly {
                args.append("--include=\(pattern)")
            }
            for pattern in exclude {
                args.append("--exclude=\(pattern)")
            }
            args.append("--exclude=*")
            return args
        }

        for pattern in include {
            args.append("--include=\(pattern)")
        }
        for pattern in exclude {
            args.append("--exclude=\(pattern)")
        }

        return args
    }

    private func uniqueFilePath(_ path: String, template: String) -> String {
        let base = (path as NSString).deletingPathExtension
        let ext = (path as NSString).pathExtension
        var counter = 1
        var candidate = path
        while FileManager.default.fileExists(atPath: candidate) {
            let suffix = duplicateSuffix(template: template, counter: counter)
            candidate = ext.isEmpty
                ? base + suffix
                : base + suffix + "." + ext
            counter += 1
        }
        return candidate
    }

    private func uniqueFolderPath(_ path: String, template: String) -> String {
        var counter = 1
        var candidate = path
        while FileManager.default.fileExists(atPath: candidate) {
            let suffix = duplicateSuffix(template: template, counter: counter)
            candidate = path + suffix
            counter += 1
        }
        return candidate
    }

    private func duplicateSuffix(template: String, counter: Int) -> String {
        let chars = Array(template)
        guard let start = chars.firstIndex(where: { $0.isNumber }) else {
            return "_\(counter)"
        }
        var end = start
        while end < chars.count, chars[end].isNumber {
            end += 1
        }
        let prefix = String(chars[..<start])
        let digits = String(chars[start..<end])
        let suffix = String(chars[end...])
        let width = digits.count
        let padWithZeros = digits.first == "0" && width > 1
        let number = padWithZeros ? String(format: "%0*d", width, counter) : String(counter)
        return prefix + number + suffix
    }

    private func reuseRootPath(
        for source: String,
        destinationRoot: String,
        preset: OrganizationPreset,
        reuseInfo: OrganizationReuseInfo?,
        options: RsyncOptions
    ) -> String? {
        guard options.reuseOrganizedFiles, !options.inplace else { return nil }
        guard let reuseInfo, reuseInfo.presetId == preset.id else { return nil }
        guard let root = reuseInfo.sourceRoots[source] else { return nil }
        guard FileManager.default.fileExists(atPath: root) else { return nil }
        return root
    }

    private func reuseArgs(reuseRoot: String?, destinationRoot: String) -> [String] {
        guard let reuseRoot else { return [] }
        let reuseDrive = DriveUtilities.driveId(for: reuseRoot)
        let destinationDrive = DriveUtilities.driveId(for: destinationRoot)
        guard reuseDrive == destinationDrive else { return [] }
        return ["--link-dest=\(reuseRoot)"]
    }
    
    // MARK: - Error Parsing

    private let ignorablePermissionDeniedDirectories = [
        ".documentrevisions-v100",
        ".spotlight-v100",
        ".fseventsd",
        ".trashes",
        ".temporaryitems"
    ]

    private func isIgnorablePermissionDeniedLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        guard lower.contains("permission denied") || lower.contains("operation not permitted") else { return false }
        return ignorablePermissionDeniedDirectories.contains { lower.contains("/\($0)") }
    }

    private func isIgnorablePermissionDeniedOutput(_ output: String) -> Bool {
        let lines = output.split(separator: "\n").map { String($0) }
        let permLines = lines.filter {
            let lower = $0.lowercased()
            return lower.contains("permission denied") || lower.contains("operation not permitted")
        }
        guard !permLines.isEmpty else { return false }
        return permLines.allSatisfy { isIgnorablePermissionDeniedLine($0) }
    }

    private func isIgnorablePermissionDenied(_ stderr: String) -> Bool {
        let lines = stderr.split(separator: "\n").map { String($0) }
        let permLines = lines.filter {
            let lower = $0.lowercased()
            return lower.contains("permission denied") || lower.contains("operation not permitted")
        }
        guard !permLines.isEmpty else { return false }
        return permLines.allSatisfy { isIgnorablePermissionDeniedLine($0) }
    }
    
    /// Parse rsync exit codes and error messages to provide user-friendly explanations
    private func parseRsyncError(exitCode: Int32, stderr: String, logFile: String?) -> String {
        let lowerStderr = stderr.lowercased()
        
        // Check for specific error patterns in stderr first (most informative)
        if lowerStderr.contains("no space left on device") || lowerStderr.contains("disk full") {
            return "Destination drive is full. Free up space and try again."
        }
        
        if lowerStderr.contains("read-only file system") || lowerStderr.contains("read-only") {
            return "Destination is read-only. Remount with write access or choose another drive."
        }

        if lowerStderr.contains("permission denied") || lowerStderr.contains("operation not permitted") {
            if isIgnorablePermissionDenied(stderr) {
                return "Protected macOS system folders were skipped (expected)."
            }
            if lowerStderr.contains("open") || lowerStderr.contains("read") {
                return "Permission denied: Cannot read some source files. Check file permissions."
            } else {
                return "Permission denied: Cannot write to destination. Check folder permissions."
            }
        }
        
        if lowerStderr.contains("no such file or directory") {
            if lowerStderr.contains("source") || lowerStderr.range(of: "cannot stat") != nil {
                return "Source file or folder no longer exists. It may have been moved or unmounted."
            } else {
                return "Destination path no longer exists. The drive may have been disconnected."
            }
        }
        
        if lowerStderr.contains("input/output error") || lowerStderr.contains("i/o error") {
            return "Drive error: Unable to read or write files. The drive may be failing or was disconnected."
        }
        
        if lowerStderr.contains("file has vanished") {
            return "Source files changed during transfer. Some files were modified or deleted while copying."
        }
        
        if lowerStderr.contains("resource busy") || lowerStderr.contains("file is busy") {
            return "Some files are in use and cannot be copied. Close applications using these files and try again."
        }
        
        if lowerStderr.contains("connection refused") || lowerStderr.contains("network") {
            return "Network error: Cannot connect to destination. Check network connection."
        }
        
        if lowerStderr.contains("timeout") {
            return "Connection timeout: Destination is not responding. Check if the drive is still connected."
        }
        
        // Interpret exit codes (rsync standard exit codes)
        switch exitCode {
        case 1:
            return "Syntax or usage error in rsync command"
        case 2:
            return "Protocol incompatibility or version mismatch"
        case 3:
            return "Error selecting input/output files or directories"
        case 4:
            return "Unsupported action requested"
        case 5:
            return "Error starting client-server protocol"
        case 9:
            if lastTerminationReason == .uncaughtSignal {
                return "Rsync was killed by the system (signal 9). Common causes include macOS quarantine/Gatekeeper, low memory, or security software. Move FilmCan to /Applications and open it once, or remove quarantine, then retry."
            }
            return "Rsync error (code 9). The process was terminated unexpectedly (possible causes: quarantine, low memory, or security software)."
        case 6:
            let firstLine = stderr
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }

            if let firstLine, !firstLine.isEmpty {
                return "Rsync error: \(firstLine)"
            }

            let appSupportPath = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first?.path ?? "~/Library/Application Support"

            return """
            Rsync error (code 6): Permission denied writing to log file or system directories.

            To fix:
            1. Open Terminal
            2. Run: sudo chmod -R 755 '\(appSupportPath)/FilmCan'
            3. Run: chown -R $(whoami) '\(appSupportPath)/FilmCan'
            4. Or disable logs in FilmCan settings
            """
        case 10:
            return "Error in socket I/O"
        case 11:
            return "Error in file I/O (may indicate drive disconnection)"
        case 12:
            return "Error in rsync protocol data stream"
        case 13:
            return "Error with program diagnostics"
        case 14:
            return "Error in IPC code"
        case 20:
            return "Received SIGUSR1 or SIGINT"
        case 21:
            return "Some error returned by waitpid()"
        case 22:
            return "Error allocating core memory buffers"
        case 23:
            if let logFile, !logFile.isEmpty {
                return "Partial transfer: Some files were successfully transferred, but some failed. Check the log for failed files: \(logFile)"
            }
            return "Partial transfer: Some files were successfully transferred, but some failed. Enable logs to see which files failed."
        case 24:
            if let logFile, !logFile.isEmpty {
                return "Partial transfer: Some files were not transferred (vanished before transfer). Check the log for failed files: \(logFile)"
            }
            return "Partial transfer: Some files were not transferred (vanished before transfer). Enable logs to see which files failed."
        case 25:
            return "Maximum number of file deletions limit reached"
        case 30:
            return "Timeout waiting for data"
        case 35:
            return "Timeout in data send/receive"
        default:
            break
        }
        
        // Fallback: show exit code and truncated stderr
        let truncated = stderr.prefix(500)
        return "Transfer failed (exit code \(exitCode))\n\(truncated)"
    }

    private func loadLatestHashIndex(destinationRoot: String) -> [String: String] {
        let fm = FileManager.default
        let dirPath = FilmCanPaths.hashListPath(for: destinationRoot)
        let dirURL = URL(fileURLWithPath: dirPath)
        guard let urls = try? fm.contentsOfDirectory(
            at: dirURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        let candidates = urls.filter { $0.pathExtension.lowercased() == "xxh128" }
        guard let latest = candidates.max(by: { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }) else {
            return [:]
        }

        guard let data = try? Data(contentsOf: latest),
              let content = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var index: [String: String] = [:]
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let separatorRange = trimmed.range(of: "  ") else { continue }
            let hash = String(trimmed[..<separatorRange.lowerBound]).lowercased()
            var pathPart = String(trimmed[separatorRange.upperBound...])
            if pathPart.hasPrefix("./") { pathPart = String(pathPart.dropFirst(2)) }
            let resolved = pathPart.hasPrefix("/")
                ? pathPart
                : (destinationRoot as NSString).appendingPathComponent(pathPart)
            let normalized = URL(fileURLWithPath: resolved).standardizedFileURL.path
            index[normalized] = hash
        }
        return index
    }
}

extension RsyncService: TransferService {}
