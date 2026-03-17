import Foundation

@MainActor
class CustomCopierService: ObservableObject, TransferService {
    @Published var progress = TransferProgress()

    private var isCancelled = false
    private var isPaused = false
    private let verifyWorker = FileStreamCopier()
    private var transferStartTime: Date?
    private var firstCopyByteTime: Date?
    private var lastEtaUpdate: Date = .distantPast
    private var smoothedEta: TimeInterval? = nil
    private let cancellationState = CancellationState()
    private var creationDateCache: [String: Date] = [:]

    func resetProgress() {
        progress.resetProgress()
        isCancelled = false
        isPaused = false
        transferStartTime = nil
        firstCopyByteTime = nil
        lastEtaUpdate = .distantPast
        smoothedEta = nil
        creationDateCache.removeAll()
        cancellationState.update(isCancelled: false, isPaused: false)
    }

    func cancel() {
        isCancelled = true
        progress.isCancelled = true
        progress.isRunning = false
        cancellationState.update(isCancelled: true, isPaused: isPaused)
    }

    func pause() {
        isPaused = true
        progress.isPaused = true
        progress.isRunning = false
        cancellationState.update(isCancelled: isCancelled, isPaused: true)
    }

    func runCopy(
        sources: [String],
        destination: String,
        configName: String,
        organizationPreset: OrganizationPreset?,
        copyFolderContents: Bool,
        useHashListPrecheck: Bool,
        hashListPath: String?,
        fileOrdering: FileOrdering,
        parallelCopyEnabled: Bool,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        duplicateCounterTemplate: String,
        duplicateResolver: (@Sendable (DuplicatePrompt) async -> DuplicateResolution)?,
        verificationEnabled: Bool
    ) async throws -> TransferResult {
        isCancelled = false
        isPaused = false
        resetProgress()
        progress.isRunning = true
        progress.phase = .copying
        transferStartTime = Date()

        let fm = FileManager.default
        for source in sources {
            guard fm.fileExists(atPath: source) else {
                progress.isRunning = false
                throw RsyncError.sourceNotFound(source)
            }
        }

        var finalResult = TransferResult(
            configurationName: configName,
            destination: destination,
            startTime: Date()
        )

        let destinationRoot = destination.hasSuffix("/") ? String(destination.dropLast()) : destination
        let hashAlgorithm: FilmCanHashAlgorithm = .xxh128
        let entries = await FileEnumerator.enumerateFiles(sources: sources, preset: organizationPreset)
        let entriesBySource = Dictionary(grouping: entries, by: { $0.sourceRoot })
        let totalBytes = entries.reduce(Int64(0)) { $0 + $1.size }
        let shouldLoadHashIndex = useHashListPrecheck || duplicatePolicy == .verify || duplicatePolicy == .ask
        let hashIndex = shouldLoadHashIndex
            ? await loadLatestHashIndex(destinationRoot: destinationRoot, algorithm: hashAlgorithm)
            : [:]
        let hasHashIndex = !hashIndex.isEmpty
        let shouldPrecheck = useHashListPrecheck && hasHashIndex
        let verificationReadMultiplier: Int64 = verificationEnabled ? 1 : 0

        func mergeWarning(_ existing: String?, _ extra: String) -> String {
            if let existing, !existing.isEmpty {
                return existing + " " + extra
            }
            return extra
        }

        func hashSourceAsync(_ path: String) async -> String? {
            await Task.detached(priority: .utility) {
                Hashing.hash(for: URL(fileURLWithPath: path), algorithm: hashAlgorithm)
            }.value
        }

        progress.totalBytes = totalBytes
        progress.filesTotal = entries.count
        progress.verificationPhase = .idle
        progress.verificationFilesTotal = verificationEnabled ? entries.count : 0
        progress.verificationFilesCompleted = 0
        progress.verificationBytesTotal = verificationEnabled ? totalBytes * verificationReadMultiplier : 0
        progress.verificationBytesCompleted = 0
        progress.verificationHasStarted = false
        progress.verificationIsActive = false
        let progressThrottle = ProgressThrottle(interval: 0.1)
        let verificationByteThrottle = ProgressThrottle(interval: 0.1)
        let cancellationState = self.cancellationState
        let shouldCancel: @Sendable () -> Bool = {
            cancellationState.shouldCancel()
        }

        var filesSkipped = 0
        var skippedWithoutVerification = false
        let copyProgress = CopyProgressTracker(startingBytes: 0)
        let copyFileCounter = CopyFileCounter(startingFiles: 0)
        let transferredPaths = PathCollector()
        let abortState = CopyAbortState()
        var abortDueToError = false
        var abortMessage: String? = nil
        let verificationProgress = VerificationProgressCounter()
        let verificationActivity = VerificationActivityCounter()
        let failureCollector = FailureCollector()
        let warningCollector = WarningCollector()
        var duplicateHits = 0
        var activeDuplicatePolicy = duplicatePolicy
        var activeDuplicateCounterTemplate = duplicateCounterTemplate
        var organizationRoots: [String: String] = [:]
        var verificationContinuation: AsyncStream<FileCopyResult>.Continuation? = nil
        let verificationStream: AsyncStream<FileCopyResult>? = verificationEnabled
            ? AsyncStream<FileCopyResult> { continuation in
                verificationContinuation = continuation
            }
            : nil
        let copier = verifyWorker
        let averageFileSize = entries.isEmpty ? 0 : totalBytes / Int64(entries.count)
        let sourceDriveIds = Set(sources.map { DriveUtilities.driveId(for: $0) })
        let destinationDriveId = DriveUtilities.driveId(for: destination)
        let sameVolume = sourceDriveIds.contains(destinationDriveId)
        let workerCount = await detectOptimalVerificationWorkers(
            destination: destination,
            averageFileSize: averageFileSize,
            sameVolume: sameVolume
        )
        #if DEBUG
        let driveType = workerCount > 1 ? "SSD" : "HDD/Unknown"
        DebugLog.info("🔧 Verification workers: \(workerCount) (detected \(driveType))")
        #endif
        let verificationWorkerCount = workerCount
        let verificationBytes = VerificationByteCounter()
        let hashListWriter: HashListWriter?
        if verificationEnabled, let hashListPath {
            do {
                hashListWriter = try HashListWriter(outputPath: hashListPath, algorithm: hashAlgorithm)
            } catch {
                await warningCollector.append("Hash list could not be created: \(error.localizedDescription)")
                hashListWriter = nil
            }
        } else {
            hashListWriter = nil
        }
        let verificationTask: Task<Void, Never>? = verificationEnabled
            ? Task.detached(priority: .utility) {
                guard let verificationStream else { return }
                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<verificationWorkerCount {
                        group.addTask {
                            for await result in verificationStream {
                            if shouldCancel() || Task.isCancelled { break }
                            let fileName = (result.destinationPath as NSString).lastPathComponent
                            let activeCount = await verificationActivity.increment()
                            await MainActor.run {
                                self.progress.verificationIsActive = activeCount > 0
                            }
                            defer {
                                Task {
                                    let remaining = await verificationActivity.decrement()
                                    await MainActor.run {
                                        self.progress.verificationIsActive = remaining > 0
                                    }
                                }
                            }
                            do {
                                await MainActor.run {
                                    if !self.progress.verificationHasStarted {
                                        self.progress.verificationHasStarted = true
                                        self.progress.verificationPhase = .verifying
                                        if self.progress.verificationStartTime == nil {
                                            self.progress.verificationStartTime = Date()
                                        }
                                    }
                                    self.progress.verificationCurrentFile = fileName
                                }
                                let sourceHash: Data
                                if let existingHash = result.sourceHash {
                                    sourceHash = existingHash
                                } else {
                                    sourceHash = try await copier.computeFileHash(
                                        path: result.sourcePath,
                                        algorithm: hashAlgorithm,
                                        shouldCancel: shouldCancel
                                    ) { bytesRead in
                                        Task {
                                            let total = await verificationBytes.add(bytesRead)
                                            let now = Date()
                                            if verificationByteThrottle.shouldEmit(now: now) {
                                                await MainActor.run {
                                                    self.progress.verificationBytesCompleted = total
                                                    self.updateSpeedAndEta()
                                                }
                                            }
                                        }
                                    }
                                }

                                let destHash: Data
                                if let existingHash = result.destinationHash {
                                    destHash = existingHash
                                } else {
                                    destHash = try await copier.computeFileHash(
                                        path: result.destinationPath,
                                        algorithm: hashAlgorithm,
                                        shouldCancel: shouldCancel
                                    ) { bytesRead in
                                        Task {
                                            let total = await verificationBytes.add(bytesRead)
                                            let now = Date()
                                            if verificationByteThrottle.shouldEmit(now: now) {
                                                await MainActor.run {
                                                    self.progress.verificationBytesCompleted = total
                                                    self.updateSpeedAndEta()
                                                }
                                            }
                                        }
                                    }
                                }
                                let count = await verificationProgress.increment()
                                await MainActor.run {
                                    self.progress.verificationFilesCompleted = count
                                }
                                if destHash != sourceHash {
                                    let mismatch = "\(result.sourcePath): source=\(sourceHash.hexString) dest=\(destHash.hexString)"
                                    await failureCollector.append(mismatch)
                                    #if DEBUG
                                    DebugLog.warn("⚠️ VERIFICATION FAILED: \(mismatch)")
                                    #endif
                                } else {
                                    await hashListWriter?.append(hash: destHash, path: result.destinationPath)
                                }
                            } catch {
                                let count = await verificationProgress.increment()
                                await MainActor.run {
                                    self.progress.verificationFilesCompleted = count
                                    self.progress.verificationCurrentFile = fileName
                                }
                                let message = "\(result.sourcePath): \(error.localizedDescription)"
                                await failureCollector.append(message)
                                #if DEBUG
                                DebugLog.warn("⚠️ VERIFICATION FAILED: \(message)")
                                #endif
                            }
                        }
                    }
                }
            }
        }
        : nil

        func resolveDuplicateAction(
            sourcePath: String,
            destinationPath: String,
            isDirectory: Bool
        ) async -> DuplicateResolution {
            if activeDuplicatePolicy != .ask {
                if activeDuplicatePolicy == .verify && !hasHashIndex {
                    if let duplicateResolver {
                                return await duplicateResolver(
                                    DuplicatePrompt(
                                        sourcePath: sourcePath,
                                        destinationPath: destinationPath,
                                        isDirectory: isDirectory,
                                        counterTemplate: activeDuplicateCounterTemplate,
                                        canVerifyWithHashList: false,
                                        hashListMissing: true
                                    )
                                )
                    }
                    return DuplicateResolution(action: .overwrite, applyToAll: false, counterTemplate: nil)
                }
                return DuplicateResolution(action: activeDuplicatePolicy, applyToAll: false, counterTemplate: nil)
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
                if resolution.action == .increment,
                   let template = resolution.counterTemplate,
                   !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    activeDuplicateCounterTemplate = template
                }
            }
            return resolution
        }

        // ═══════════════════════════════════════════════════════════════
        // PHASE 1: COPY ALL FILES (Non-blocking, no verification yet)
        // ═══════════════════════════════════════════════════════════════
        progress.phase = .copying
        
        for (index, sourceRoot) in sources.enumerated() {
            if abortDueToError { break }
            if shouldCancel() { break }
            let counter = index + 1
            let sourceEntries = orderedEntries(entriesBySource[sourceRoot] ?? [], ordering: fileOrdering)

            let sourceIsDirectory: Bool = {
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: sourceRoot, isDirectory: &isDir)
                return isDir.boolValue
            }()

            var baseTarget = destinationRoot

            if let preset = organizationPreset {
                let resolved = OrganizationTemplate.resolve(
                    preset: preset,
                    sourcePath: sourceRoot,
                    destinationRoot: destinationRoot,
                    counter: counter,
                    date: Date()
                )
                let parentFolder = resolved.folderPath.isEmpty
                    ? destinationRoot
                    : (destinationRoot as NSString).appendingPathComponent(resolved.folderPath)
                if sourceIsDirectory {
                    baseTarget = copyFolderContents
                        ? parentFolder
                        : (parentFolder as NSString).appendingPathComponent(resolved.renamedItem)
                } else {
                    baseTarget = (parentFolder as NSString).appendingPathComponent(resolved.renamedItem)
                }
                organizationRoots[sourceRoot] = sourceIsDirectory ? baseTarget : parentFolder
            } else if sourceIsDirectory {
                if copyFolderContents {
                    baseTarget = destinationRoot
                } else {
                    baseTarget = (destinationRoot as NSString).appendingPathComponent((sourceRoot as NSString).lastPathComponent)
                }
            } else {
                baseTarget = (destinationRoot as NSString).appendingPathComponent((sourceRoot as NSString).lastPathComponent)
            }

            if sourceIsDirectory && !copyFolderContents {
                if fm.fileExists(atPath: baseTarget),
                   destinationFolderHasVisibleContents(baseTarget) {
                    duplicateHits += 1
                    let resolution = await resolveDuplicateAction(
                        sourcePath: sourceRoot,
                        destinationPath: baseTarget,
                        isDirectory: true
                    )
                    switch resolution.action {
                    case .skip:
                        let skippedBytes = sourceEntries.reduce(Int64(0)) { $0 + $1.size }
                        skippedWithoutVerification = true
                        if verificationEnabled {
                            let completedBytes = await verificationBytes.add(skippedBytes * verificationReadMultiplier)
                            progress.verificationBytesCompleted = completedBytes
                            progress.verificationFilesTotal = max(progress.verificationFilesTotal - sourceEntries.count, 0)
                        }
                        filesSkipped += sourceEntries.count
                        let completedCount = await copyFileCounter.increment(by: sourceEntries.count)
                        progress.filesCompleted = completedCount
                        continue
                    case .overwrite:
                        break
                    case .increment:
                        let template = resolution.counterTemplate ?? activeDuplicateCounterTemplate
                        baseTarget = uniqueFolderPath(baseTarget, template: template)
                    case .verify:
                        break
                    case .ask:
                        break
                    }
                }
            }

            if sourceIsDirectory {
                try? fm.createDirectory(atPath: baseTarget, withIntermediateDirectories: true)
            } else {
                let parent = (baseTarget as NSString).deletingLastPathComponent
                try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            }

            let normalizedBaseTarget = URL(fileURLWithPath: baseTarget).standardizedFileURL.path
            var copyJobs: [CopyJob] = []

            for entry in sourceEntries {
                if shouldCancel() { break }

                var destinationPath: String
                if sourceIsDirectory {
                    destinationPath = (baseTarget as NSString).appendingPathComponent(entry.relativePath)
                } else {
                    destinationPath = baseTarget
                }

                func normalizedDestinationPath() -> String {
                    if sourceIsDirectory {
                        return (normalizedBaseTarget as NSString).appendingPathComponent(entry.relativePath)
                    }
                    return normalizedBaseTarget
                }

                if shouldPrecheck {
                    let normalizedDestination = normalizedDestinationPath()
                    if let expectedHash = hashIndex[normalizedDestination],
                       fm.fileExists(atPath: normalizedDestination),
                       let sourceHash = await hashSourceAsync(entry.sourcePath),
                       sourceHash.lowercased() == expectedHash {
                        if verificationEnabled {
                            if !progress.verificationHasStarted {
                                progress.verificationHasStarted = true
                                progress.verificationPhase = .verifying
                                if progress.verificationStartTime == nil {
                                    progress.verificationStartTime = Date()
                                }
                            }
                        }
                        filesSkipped += 1
                        let completedCount = await copyFileCounter.increment()
                        progress.filesCompleted = completedCount
                        if verificationEnabled {
                            let skippedBytes = entry.size * verificationReadMultiplier
                            let completedBytes = await verificationBytes.add(skippedBytes)
                            progress.verificationBytesCompleted = completedBytes
                            let count = await verificationProgress.increment()
                            progress.verificationFilesCompleted = count
                            progress.verificationCurrentFile = (entry.sourcePath as NSString).lastPathComponent
                        }
                        continue
                    }
                }

                if fm.fileExists(atPath: destinationPath) {
                    duplicateHits += 1
                    let resolution = await resolveDuplicateAction(
                        sourcePath: entry.sourcePath,
                        destinationPath: destinationPath,
                        isDirectory: false
                    )
                    switch resolution.action {
                    case .skip:
                        skippedWithoutVerification = true
                        if verificationEnabled {
                            let skippedBytes = entry.size * verificationReadMultiplier
                            let completedBytes = await verificationBytes.add(skippedBytes)
                            progress.verificationBytesCompleted = completedBytes
                            progress.verificationFilesTotal = max(progress.verificationFilesTotal - 1, 0)
                        }
                        filesSkipped += 1
                        let completedCount = await copyFileCounter.increment()
                        progress.filesCompleted = completedCount
                        continue
                    case .overwrite:
                        try? fm.removeItem(atPath: destinationPath)
                    case .increment:
                        let template = resolution.counterTemplate ?? activeDuplicateCounterTemplate
                        destinationPath = uniqueFilePath(destinationPath, template: template)
                    case .verify:
                        if hasHashIndex {
                            let normalizedDestination = normalizedDestinationPath()
                            if let expectedHash = hashIndex[normalizedDestination],
                               fm.fileExists(atPath: normalizedDestination),
                               let sourceHash = await hashSourceAsync(entry.sourcePath),
                               sourceHash.lowercased() == expectedHash {
                                if verificationEnabled {
                                    let skippedBytes = entry.size * verificationReadMultiplier
                                    let completedBytes = await verificationBytes.add(skippedBytes)
                                    progress.verificationBytesCompleted = completedBytes
                                }
                                filesSkipped += 1
                                let completedCount = await copyFileCounter.increment()
                                progress.filesCompleted = completedCount
                                if verificationEnabled {
                                    if !progress.verificationHasStarted {
                                        progress.verificationHasStarted = true
                                        progress.verificationPhase = .verifying
                                        if progress.verificationStartTime == nil {
                                            progress.verificationStartTime = Date()
                                        }
                                    }
                                    let count = await verificationProgress.increment()
                                    progress.verificationFilesCompleted = count
                                    progress.verificationCurrentFile = (entry.sourcePath as NSString).lastPathComponent
                                }
                                continue
                            }
                        }
                        try? fm.removeItem(atPath: destinationPath)
                    case .ask:
                        break
                    }
                }

                copyJobs.append(
                    CopyJob(
                        entry: entry,
                        destinationPath: destinationPath
                    )
                )
            }

            if shouldCancel() { break }
            if await abortState.shouldAbort() { break }

            if copyJobs.isEmpty { continue }

            let jobBatches = bucketCopyJobs(
                copyJobs,
                ordering: fileOrdering,
                parallelCopyEnabled: parallelCopyEnabled
            )

            for batch in jobBatches where !batch.isEmpty {
                let averageSize = batch.reduce(Int64(0)) { $0 + $1.entry.size } / Int64(batch.count)
                let sourceRoots = Array(Set(batch.map { $0.entry.sourceRoot }))
                let sourceIsSSD = parallelCopyEnabled ? await allVolumesAreSolidState(sourceRoots) : false
                let workerCount = parallelCopyEnabled
                    ? await detectOptimalCopyWorkers(
                        destination: baseTarget,
                        sourceIsSSD: sourceIsSSD,
                        averageFileSize: averageSize
                    )
                    : 1
                let activeWorkers = max(1, min(workerCount, batch.count))
                let jobQueue = JobQueue(jobs: batch)

                await withTaskGroup(of: Void.self) { group in
                    for _ in 0..<activeWorkers {
                        let worker = FileStreamCopier()
                        group.addTask {
                            while let job = await jobQueue.next() {
                                if shouldCancel() { break }
                                if await abortState.shouldAbort() { break }

                                await MainActor.run {
                                    self.progress.currentFile = job.fileName
                                }

                                let fileId = job.destinationPath
                                do {
                                    let result = try await worker.copyFile(
                                        source: job.entry.sourcePath,
                                        destination: job.destinationPath,
                                        hashDuringCopy: verificationEnabled,
                                        hashAlgorithm: hashAlgorithm,
                                        shouldCancel: shouldCancel
                                    ) { bytesInFile in
                                        let now = Date()
                                        guard progressThrottle.shouldEmit(now: now) else { return }
                                        Task {
                                            let total = await copyProgress.update(fileId: fileId, bytes: bytesInFile)
                                            await MainActor.run {
                                                self.progress.bytesCompleted = total
                                                self.progress.cumulativeBytes = total
                                                self.updateSpeedAndEta()
                                            }
                                        }
                                    }

                                    let total = await copyProgress.update(fileId: fileId, bytes: result.bytesWritten)
                                    await copyProgress.finish(fileId: fileId)
                                    let completedCount = await copyFileCounter.increment()

                                    await MainActor.run {
                                        self.progress.filesCompleted = completedCount
                                        self.progress.bytesCompleted = total
                                        self.progress.cumulativeBytes = total
                                        self.updateSpeedAndEta()
                                        self.progress.completedFiles.insert(result.destinationPath, at: 0)
                                        if self.progress.completedFiles.count > 50 {
                                            self.progress.completedFiles.removeLast()
                                        }
                                    }

                                    await transferredPaths.append(result.destinationPath)

                                    if verificationEnabled {
                                        if let destHash = result.destinationHash, let sourceHash = result.sourceHash {
                                            await MainActor.run {
                                                if !self.progress.verificationHasStarted {
                                                    self.progress.verificationHasStarted = true
                                                    self.progress.verificationPhase = .verifying
                                                    if self.progress.verificationStartTime == nil {
                                                        self.progress.verificationStartTime = Date()
                                                    }
                                                }
                                                self.progress.verificationCurrentFile = job.fileName
                                            }
                                            let count = await verificationProgress.increment()
                                            await MainActor.run {
                                                self.progress.verificationFilesCompleted = count
                                            }
                                            let bytes = await verificationBytes.add(result.bytesWritten * verificationReadMultiplier)
                                            await MainActor.run {
                                                self.progress.verificationBytesCompleted = bytes
                                            }
                                            if destHash != sourceHash {
                                                let mismatch = "\(result.sourcePath): source=\(sourceHash.hexString) dest=\(destHash.hexString)"
                                                await failureCollector.append(mismatch)
                                                #if DEBUG
                                                DebugLog.warn("⚠️ VERIFICATION FAILED: \(mismatch)")
                                                #endif
                                            } else {
                                                await hashListWriter?.append(hash: destHash, path: result.destinationPath)
                                            }
                                        } else {
                                            verificationContinuation?.yield(result)
                                        }
                                    }
                                } catch {
                                    do {
                                        try fm.removeItem(atPath: job.destinationPath)
                                    } catch {
                                        await warningCollector.append(
                                            "Could not remove partial file at \(job.destinationPath): \(error.localizedDescription)"
                                        )
                                    }
                                    if case FileCopyError.cancelled = error {
                                        break
                                    }
                                    await abortState.setError(error.localizedDescription)
                                    break
                                }
                            }
                        }
                    }
                }
            }

            if await abortState.shouldAbort() {
                abortDueToError = true
                abortMessage = await abortState.message()
                break
            }
        }

        if verificationEnabled {
            verificationContinuation?.finish()
            if shouldCancel() || abortDueToError {
                verificationTask?.cancel()
            }
        }
        progress.copyingDone = true
        if verificationEnabled && progress.verificationFilesTotal > 0 {
            progress.phase = .verifying
        }
        if let verificationTask {
            _ = await verificationTask.value
            let verifiedCount = await verificationProgress.value()
            progress.verificationFilesCompleted = verifiedCount
            progress.verificationBytesCompleted = await verificationBytes.value()
            progress.verificationIsActive = false
            if shouldCancel() || abortDueToError {
                progress.verificationFilesTotal = verifiedCount
            }
        } else {
            progress.verificationFilesCompleted = 0
            progress.verificationBytesCompleted = 0
            progress.verificationIsActive = false
        }
        let bytesCompleted = await copyProgress.value()
        let filesCompleted = await copyFileCounter.value()
        let transferredPathsList = await transferredPaths.all()

        if shouldCancel() {
            await hashListWriter?.removeFile()
            finalResult.organizationRoots = organizationRoots
            finalResult.filesTransferred = filesCompleted
            finalResult.filesSkipped = filesSkipped
            finalResult.bytesTransferred = bytesCompleted
            finalResult.totalBytes = totalBytes
            finalResult.transferredPaths = transferredPathsList
            finalResult.duplicatePolicy = duplicatePolicy
            finalResult.duplicateHits = duplicateHits
            finalResult.wasVerified = false
            finalResult.endTime = Date()
            
            if isPaused {
                finalResult.success = false
                finalResult.wasPaused = true
                finalResult.errorMessage = "Stopped by user"
            } else {
                finalResult.success = false
                finalResult.errorMessage = "Cancelled by user"
            }
            
            progress.isRunning = false
            progress.phase = .finished
            progress.copyingDone = true
            progress.verificationPhase = .idle
            let warnings = await warningCollector.all()
            if !warnings.isEmpty {
                let head = warnings.prefix(3).joined(separator: " | ")
                let extra = warnings.count > 3 ? " (+\(warnings.count - 3) more)" : ""
                finalResult.warningMessage = mergeWarning(finalResult.warningMessage, head + extra)
            }
            
            return finalResult
        }

        // ═══════════════════════════════════════════════════════════════
        // FINALIZE RESULT
        // ═══════════════════════════════════════════════════════════════
        finalResult.organizationRoots = organizationRoots
        finalResult.filesTransferred = filesCompleted
        finalResult.filesSkipped = filesSkipped
        finalResult.bytesTransferred = bytesCompleted
        finalResult.totalBytes = totalBytes
        finalResult.transferredPaths = transferredPathsList
        finalResult.duplicatePolicy = duplicatePolicy
        finalResult.duplicateHits = duplicateHits
        let verificationFailures = await failureCollector.all()
        if !verificationFailures.isEmpty {
            let limit = 50
            let slice = verificationFailures.prefix(limit)
            finalResult.errors = Array(slice)
            if verificationFailures.count > limit {
                finalResult.errors.append("…and \(verificationFailures.count - limit) more")
            }
        }
        if !verificationFailures.isEmpty || isCancelled || isPaused {
            await hashListWriter?.removeFile()
        } else if let hashListWriter {
            if let error = await hashListWriter.errorMessage() {
                await hashListWriter.removeFile()
                finalResult.warningMessage = mergeWarning(finalResult.warningMessage, "Hash list could not be written: \(error)")
            } else {
                let count = await hashListWriter.count()
                if count == 0 {
                    await hashListWriter.removeFile()
                } else {
                    await hashListWriter.close()
                    finalResult.hashListPath = hashListPath
                    finalResult.hashRoots = []
                }
            }
        }
        if abortDueToError {
            finalResult.errorMessage = abortMessage ?? "Copy failed."
        }

        finalResult.wasVerified = verificationEnabled
            && verificationFailures.isEmpty
            && !isCancelled
            && !isPaused
            && !skippedWithoutVerification
            && !abortDueToError
        finalResult.endTime = Date()
        let warnings = await warningCollector.all()
        if !warnings.isEmpty {
            let head = warnings.prefix(3).joined(separator: " | ")
            let extra = warnings.count > 3 ? " (+\(warnings.count - 3) more)" : ""
            finalResult.warningMessage = mergeWarning(finalResult.warningMessage, head + extra)
        }

        if isPaused {
            finalResult.success = false
            finalResult.wasPaused = true
            finalResult.errorMessage = "Stopped by user"
        } else if isCancelled {
            finalResult.success = false
            finalResult.errorMessage = "Cancelled by user"
        } else if abortDueToError {
            finalResult.success = false
        } else if !verificationFailures.isEmpty {
            finalResult.success = false
            finalResult.errorMessage = "Verification failed for \(verificationFailures.count) files"
        } else if finalResult.errorMessage == nil {
            finalResult.success = true
        }

        progress.isRunning = false
        progress.phase = .finished
        progress.verificationPhase = (verificationEnabled && finalResult.success) ? .complete : .idle
        progress.verificationCurrentFile = ""

        #if DEBUG
        let duration = Date().timeIntervalSince(transferStartTime ?? Date())
        let throughput = duration > 0 ? Double(bytesCompleted) / duration : 0
        DebugLog.info("✅ Transfer complete: \(filesCompleted) files, \(FilmCanFormatters.bytes(bytesCompleted, style: .file)) in \(String(format: "%.1f", duration))s (\(FilmCanFormatters.speed(throughput, style: .file)))")
        #endif

        return finalResult
    }

    @MainActor
    private func updateSpeedAndEta() {
        guard let start = transferStartTime else { return }
        let now = Date()
        let minEtaInterval: TimeInterval = 1.0
        if now.timeIntervalSince(lastEtaUpdate) < minEtaInterval {
            return
        }
        lastEtaUpdate = now
        let copyBytes = max(progress.cumulativeBytes, progress.bytesCompleted)
        if copyBytes > 0, firstCopyByteTime == nil {
            firstCopyByteTime = now
            progress.estimatedTimeRemaining = nil
            smoothedEta = nil
            return
        }

        let elapsed = now.timeIntervalSince(firstCopyByteTime ?? start)
        guard elapsed > 0 else { return }

        let totalCopyBytes = progress.totalBytes
        let minWarmupBytes = min(Int64(64 * 1024 * 1024), max(Int64(4 * 1024 * 1024), totalCopyBytes / 50))
        let minWarmupSeconds: TimeInterval = 3.0

        let hasCopyWarmup = copyBytes >= minWarmupBytes && elapsed >= minWarmupSeconds
        let hasVerifyWarmup = progress.verificationBytesCompleted >= minWarmupBytes
            || progress.verificationFilesCompleted >= 10
        if !hasCopyWarmup && !hasVerifyWarmup {
            progress.estimatedTimeRemaining = nil
            smoothedEta = nil
            return
        }

        let copySpeed = copyBytes > 0 ? Double(copyBytes) / elapsed : 0
        if copySpeed > 0 {
            progress.speedBytesPerSecond = copySpeed
        }

        let copyRemaining = max(totalCopyBytes - copyBytes, 0)
        let verifyRemaining = max(progress.verificationBytesTotal - progress.verificationBytesCompleted, 0)
        let copyFilesRemaining = max(progress.filesTotal - progress.filesCompleted, 0)
        let verifyFilesRemaining = max(progress.verificationFilesTotal - progress.verificationFilesCompleted, 0)

        var verifySpeed = copySpeed
        var verifyFileRate: Double = 0
        if progress.verificationHasStarted,
           let verifyStart = progress.verificationStartTime {
            let verifyElapsed = now.timeIntervalSince(verifyStart)
            if verifyElapsed > 0, progress.verificationBytesCompleted > 0 {
                verifySpeed = Double(progress.verificationBytesCompleted) / verifyElapsed
            }
            if verifyElapsed > 0, progress.verificationFilesCompleted > 0 {
                verifyFileRate = Double(progress.verificationFilesCompleted) / verifyElapsed
            }
        }

        let copyTimeBytes = copySpeed > 0 ? Double(copyRemaining) / copySpeed : 0
        let copyFileRate = elapsed > 0 && progress.filesCompleted > 0
            ? Double(progress.filesCompleted) / elapsed
            : 0
        let copyTimeFiles = copyFileRate > 0 ? Double(copyFilesRemaining) / copyFileRate : 0
        let copyTime = max(copyTimeBytes, copyTimeFiles)

        let verifyTimeBytes = verifySpeed > 0 ? Double(verifyRemaining) / verifySpeed : 0
        let verifyTimeFiles = verifyFileRate > 0 ? Double(verifyFilesRemaining) / verifyFileRate : 0
        let verifyTime = max(verifyTimeBytes, verifyTimeFiles)
        let remaining = max(copyTime, verifyTime)
        if remaining <= 0 {
            progress.estimatedTimeRemaining = nil
            smoothedEta = nil
            return
        }
        let alpha = 0.2
        if let current = smoothedEta {
            let smoothed = current * (1 - alpha) + remaining * alpha
            smoothedEta = smoothed
            progress.estimatedTimeRemaining = smoothed
        } else {
            smoothedEta = remaining
            progress.estimatedTimeRemaining = remaining
        }
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

    private func destinationFolderHasVisibleContents(_ path: String) -> Bool {
        let fm = FileManager.default
        let url = URL(fileURLWithPath: path)
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }
        while let fileURL = enumerator.nextObject() as? URL {
            let standardized = fileURL.standardizedFileURL.path
            if FilmCanPaths.isHidden(standardized) { continue }
            return true
        }
        return false
    }

    private func loadLatestHashIndex(destinationRoot: String, algorithm: FilmCanHashAlgorithm) async -> [String: String] {
        await Task.detached(priority: .utility) {
            Self.loadLatestHashIndexSync(destinationRoot: destinationRoot, algorithm: algorithm)
        }.value
    }

    nonisolated private static func loadLatestHashIndexSync(destinationRoot: String, algorithm: FilmCanHashAlgorithm) -> [String: String] {
        let fm = FileManager.default
        let hashListDirs = [
            FilmCanPaths.hashListPath(for: destinationRoot),
            (destinationRoot as NSString).appendingPathComponent(FilmCanPaths.hidden)
        ]
        var urls: [URL] = []
        for dir in hashListDirs {
            let dirURL = URL(fileURLWithPath: dir)
            if let entries = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                urls.append(contentsOf: entries)
            }
        }

        let candidates = urls.filter { $0.pathExtension.lowercased() == algorithm.fileExtension }
        if candidates.isEmpty {
            let hiddenRoot = (destinationRoot as NSString).appendingPathComponent(FilmCanPaths.hidden)
            if let enumerator = fm.enumerator(atPath: hiddenRoot) {
                let suffix = ".\(algorithm.fileExtension)"
                for case let file as String in enumerator where file.lowercased().hasSuffix(suffix) {
                    let fullPath = (hiddenRoot as NSString).appendingPathComponent(file)
                    urls.append(URL(fileURLWithPath: fullPath))
                }
            }
        }
        let allCandidates = (candidates.isEmpty ? urls : candidates).filter { $0.pathExtension.lowercased() == algorithm.fileExtension }
        guard let latest = allCandidates.max(by: { lhs, rhs in
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
            if trimmed.hasPrefix("#") { continue }
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

    private func orderedEntries(_ entries: [SourceFileEntry], ordering: FileOrdering) -> [SourceFileEntry] {
        guard entries.count > 1 else { return entries }
        switch ordering {
        case .defaultOrder:
            return entries
        case .smallFirst:
            return entries.sorted {
                if $0.size != $1.size { return $0.size < $1.size }
                return $0.relativePath < $1.relativePath
            }
        case .largeFirst:
            return entries.sorted {
                if $0.size != $1.size { return $0.size > $1.size }
                return $0.relativePath < $1.relativePath
            }
        case .creationDate:
            let fm = FileManager.default
            func dateFor(_ path: String) -> Date {
                if let cached = creationDateCache[path] { return cached }
                let date = (try? fm.attributesOfItem(atPath: path)[.creationDate] as? Date) ?? .distantPast
                creationDateCache[path] = date
                return date
            }
            return entries.sorted {
                let left = dateFor($0.sourcePath)
                let right = dateFor($1.sourcePath)
                if left != right { return left < right }
                return $0.relativePath < $1.relativePath
            }
        }
    }

    nonisolated private static func volumeIsSolidState(for url: URL) -> Bool? {
        let key = URLResourceKey(rawValue: "NSURLVolumeIsSolidStateKey")
        guard let values = try? url.resourceValues(forKeys: [key]) else {
            return nil
        }
        return values.allValues[key] as? Bool
    }

    private func detectOptimalCopyWorkers(destination: String, sourceIsSSD: Bool, averageFileSize: Int64) async -> Int {
        let url = URL(fileURLWithPath: destination)
        let isSSD = Self.volumeIsSolidState(for: url) ?? false

        let cpuCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let cpuCap = max(1, cpuCount / 2)
        let smallLimit: Int64 = 1 * 1024 * 1024
        let mediumLimit: Int64 = 50 * 1024 * 1024
        let largeLimit: Int64 = 512 * 1024 * 1024

        let base: Int
        if !(isSSD && sourceIsSSD) {
            base = 1
        } else if averageFileSize >= largeLimit {
            base = 1
        } else if averageFileSize < smallLimit {
            base = 4
        } else if averageFileSize < mediumLimit {
            base = 3
        } else {
            base = 2
        }
        return max(1, min(base, cpuCap))
    }

    private func allVolumesAreSolidState(_ paths: [String]) async -> Bool {
        let task = Task.detached(priority: .utility) {
            var sawKnown = false
            for path in paths {
                let url = URL(fileURLWithPath: path)
                if let solid = Self.volumeIsSolidState(for: url) {
                    sawKnown = true
                    if !solid {
                        return false
                    }
                }
            }
            return sawKnown
        }
        return await task.value
    }

    private func bucketCopyJobs(
        _ jobs: [CopyJob],
        ordering: FileOrdering,
        parallelCopyEnabled: Bool
    ) -> [[CopyJob]] {
        guard parallelCopyEnabled else { return [jobs] }
        guard ordering == .largeFirst || ordering == .smallFirst else { return [jobs] }
        let smallLimit: Int64 = 1 * 1024 * 1024
        let mediumLimit: Int64 = 50 * 1024 * 1024
        var small: [CopyJob] = []
        var medium: [CopyJob] = []
        var large: [CopyJob] = []

        for job in jobs {
            let size = job.entry.size
            if size < smallLimit {
                small.append(job)
            } else if size < mediumLimit {
                medium.append(job)
            } else {
                large.append(job)
            }
        }

        let ordered = ordering == .largeFirst
            ? [large, medium, small]
            : [small, medium, large]
        return ordered.filter { !$0.isEmpty }
    }

    private func detectOptimalVerificationWorkers(
        destination: String,
        averageFileSize: Int64,
        sameVolume: Bool
    ) async -> Int {
        let url = URL(fileURLWithPath: destination)
        if let isSSD = Self.volumeIsSolidState(for: url) {
            if !isSSD {
                return 1
            }
            if sameVolume {
                return 1
            }
            let cpuCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
            let scaled = max(1, cpuCount / 2)
            let tinyLimit: Int64 = 1 * 1024 * 1024
            let mediumLimit: Int64 = 50 * 1024 * 1024
            if averageFileSize < tinyLimit {
                return min(8, scaled)
            }
            if averageFileSize < mediumLimit {
                return min(4, scaled)
            }
            return min(2, scaled)
        }
        return 1
    }
}
