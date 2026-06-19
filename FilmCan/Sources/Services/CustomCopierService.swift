import Foundation

enum CopyError: LocalizedError {
    case sourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let path): return "Source not found: \(path)"
        }
    }
}

@MainActor
class CustomCopierService: ObservableObject, TransferService {
    @Published var progress = TransferProgress()

    private var isCancelled = false
    private var isPaused = false
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


    /// Fan-out copy: copies sources to multiple destinations in parallel
    func runCopyFanOut(
        sources: [String],
        fanOutDestinations: [DestWriter.Config],
        configName: String,
        organizationPreset: OrganizationPreset?,
        copyFolderContents: Bool,
        useHashListPrecheck: Bool,
        hashListPath: String?,
        fileOrdering: FileOrdering,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        duplicateCounterTemplate: String,
        duplicateResolver: (@Sendable (DuplicatePrompt) async -> DuplicateResolution)?,
        verifyMode: VerifyMode,
        dryRun: Bool,
        forceRecopy: Bool = false,
        shootMetadata: ShootMetadata = .empty,
        sourceMediaKinds: [String: SourceMediaKind] = [:],
        hashListStyle: HashListStyle = .ascMHL,
        reVerifyExistingOnResume: Bool = false,
        unreadableHandler: (@Sendable ([String]) async -> Bool)? = nil,
        progressHandler: (@Sendable ([DestProgress]) -> Void)?,
        webhookHandler: (@Sendable (DestResult, String) -> Void)? = nil,
        aggregatedWebhookHandler: (@Sendable ([DestResult], String) -> Void)? = nil
    ) async throws -> TransferResult {
        let startTime = Date()
        let mhlBasePath: String? = nil

        let accumulator = ProgressAccumulator { progresses in
            Task { @MainActor in
                progressHandler?(progresses)
            }
        }

        let cancellationState = self.cancellationState
        var fanOutConfig = FanOutCopier.Configuration(
            sources: sources,
            destinations: fanOutDestinations,
            verifyMode: verifyMode,
            mhlBasePath: mhlBasePath,
            dryRun: dryRun,
            progressHandler: { [accumulator] prog in
                Task { await accumulator.update(prog) }
            },
            organizationPreset: organizationPreset,
            copyFolderContents: copyFolderContents,
            shootMetadata: shootMetadata,
            sourceMediaKinds: sourceMediaKinds,
            hashListStyle: hashListStyle,
            forceRecopy: forceRecopy,
            shouldCancel: { cancellationState.isCancelledNow() },
            reVerifyExistingOnResume: reVerifyExistingOnResume
        )

        fanOutConfig.duplicatePolicy = duplicatePolicy
        fanOutConfig.duplicateCounterTemplate = duplicateCounterTemplate
        fanOutConfig.unreadableHandler = unreadableHandler
        if let duplicateResolver {
            fanOutConfig.duplicateResolver = { @Sendable conflicts in
                guard let first = conflicts.first else { return duplicatePolicy }
                let prompt = DuplicatePrompt(
                    sourcePath: first.fileName,
                    destinationPath: first.resolvedPath,
                    isDirectory: false,
                    counterTemplate: duplicateCounterTemplate,
                    canVerifyWithHashList: false,
                    hashListMissing: false)
                return await duplicateResolver(prompt).action
            }
        }

        let copier = FanOutCopier(config: fanOutConfig)
        let destResults = try await copier.run()

        // Fire per-dest webhooks
        for result in destResults {
            webhookHandler?(result, configName)
        }

        // v2 aggregated event (caller wires either per-dest OR aggregated based on config)
        if let aggregatedWebhookHandler {
            let sourceName = sources.first.map { ($0 as NSString).lastPathComponent } ?? ""
            aggregatedWebhookHandler(destResults, sourceName)
        }

        let totalBytes = destResults.reduce(0) { $0 + $1.bytesTransferred }
        let totalFiles = destResults.reduce(0) { $0 + $1.filesTransferred }
        let failedCount = destResults.filter { !$0.success }.count

        var warnings: [String] = []
        for result in destResults where !result.success {
            if let reason = result.failureReason {
                warnings.append("\(result.displayName): \(reason.displayMessage)")
            }
        }

        var result = TransferResult(
            configurationName: configName,
            destination: fanOutDestinations.first?.destPath ?? "",
            startTime: startTime,
            endTime: Date(),
            success: failedCount == 0,
            errorMessage: failedCount > 0 ? "\(failedCount) destination(s) failed" : nil,
            warningMessage: warnings.isEmpty ? nil : warnings.joined(separator: " | "),
            filesTransferred: totalFiles,
            bytesTransferred: totalBytes,
            totalBytes: totalBytes,
            filesSkipped: 0,
            errors: warnings,
            hashListPath: destResults.compactMap(\.mhlPath).first,
            wasVerified: verifyMode == .paranoid && failedCount == 0
        )
        result.destinationResults = destResults
        return result
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

// MARK: - Fan-out progress accumulator

actor ProgressAccumulator {
    var progresses: [String: DestProgress] = [:]
    let handler: @Sendable ([DestProgress]) -> Void

    init(handler: @escaping @Sendable ([DestProgress]) -> Void) {
        self.handler = handler
    }

    func update(_ prog: DestProgress) {
        progresses[prog.id] = prog
        handler(Array(progresses.values))
    }
}
