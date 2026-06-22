import Foundation
import Combine
import SwiftUI

@MainActor
class TransferViewModel: ObservableObject {
    static let shared = TransferViewModel()

    @AppStorage("notifyOnComplete") private var notifyOnComplete: Bool = true
    @AppStorage("notifyOnError") private var notifyOnError: Bool = true
    @AppStorage("ntfyEnabled") private var ntfyEnabled: Bool = false
    @AppStorage("ntfyURL") private var ntfyURL: String = ""
    @AppStorage("ntfyTitleTemplate") private var ntfyTitleTemplate: String = "{source}'s backup to {destinations} for {movie} : {backupStatus}"
    @AppStorage("ntfyMessageTemplate") private var ntfyMessageTemplate: String = "{bytes} ({files} files) from {source} has been {backupAction} to {destination} in {duration}.\n{backupDetails}"
    @AppStorage("webhookEnabled") private var webhookEnabled: Bool = false
    @AppStorage("webhookURL") private var webhookURL: String = ""
    @AppStorage("webhookIncludeFullPaths") private var webhookIncludeFullPaths: Bool = false
    @AppStorage("historyRetentionLimit") private var historyRetentionLimit: Int = 200
    
    @Published var isTransferring: Bool = false
    @Published var activeConfigId: UUID? = nil
    @Published var progress = TransferProgress()
    @Published var results: [TransferResult] = []
    @Published var currentDestinationIndex: Int = 0
    @Published var shouldCancelCurrentOnly: Bool = false
    @Published var isCancellingAll: Bool = false
    @Published var currentSources: [String] = []
    @Published var currentDestination: String = ""
    @Published var allDestinations: [String] = []
    @Published var isParallelRun: Bool = false
    @Published var cancelledDestinations: Set<String> = []
    /// Set when a Run found everything already backed up (nothing to copy). The
    /// UI shows an "already backed up" popup instead of adding a history card.
    @Published var alreadyBackedUp: AlreadyBackedUpInfo? = nil
    @Published var verifiedDestinationsByConfig: [UUID: Set<String>] = [:]
    @Published var destinationProgress: [String: Double] = [:]
    @Published var pathProgress: [String: Double] = [:]
    @Published var destinationLiveProgress: [String: DestinationLiveProgress] = [:]
    @Published var activeSourceByDestination: [String: String] = [:]
    @Published var driveCapacitySnapshot: [String: DriveCapacitySnapshot] = [:]
    @Published private(set) var activeTransferConfigIds: Set<UUID> = []
    @Published private(set) var tabProgressByConfig: [UUID: Double] = [:]

    struct DriveCapacitySnapshot {
        let totalBytes: Int64?
        let availableBytes: Int64?
    }

    struct DestinationLiveProgress {
        let isRunning: Bool
        let isCancelled: Bool
        let isPaused: Bool
        let phase: TransferPhase
        let copyingDone: Bool
        let filesCompleted: Int
        let filesTotal: Int
        let bytesCompleted: Int64
        let cumulativeBytes: Int64
        let totalBytes: Int64
        let speedBytesPerSecond: Double
        let estimatedTimeRemaining: TimeInterval?
        let verificationHasStarted: Bool
        let verificationIsActive: Bool
        let verificationPhase: VerificationPhase
        let verificationFilesCompleted: Int
        let verificationFilesTotal: Int
        let verificationBytesCompleted: Int64
        let verificationBytesTotal: Int64
        let verificationWeightedProgress: Double
    }
    
    @Published var duplicates = DuplicatePromptCoordinator()
    private var duplicatesObserver: AnyCancellable?

    private let historyRecorder = HistoryRecorder()
    private var config: BackupConfiguration?
    private var transferStartTime: Date?
    private var lastRunContext: RunContext?
    private var isPausingAll: Bool = false
    private var activeServices: [TransferService] = []
    private var duplicatePromptCancelled: Bool = false
    private var destinationProgressCancellables: [String: AnyCancellable] = [:]
    private var progressBinding: AnyCancellable? = nil
    private var currentService: TransferService? = nil
    private let isBackgroundWorker: Bool
    private var concurrentWorkers: [UUID: TransferViewModel] = [:]
    private var concurrentWorkerCancellables: [UUID: Set<AnyCancellable>] = [:]

    init(isBackgroundWorker: Bool = false) {
        self.isBackgroundWorker = isBackgroundWorker
        duplicatesObserver = duplicates.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    
    func startTransfer(config: BackupConfiguration) async {
        if !isBackgroundWorker, isTransferring, activeConfigId != config.id {
            startConcurrentTransfer(config: config)
            return
        }
        if !isBackgroundWorker, concurrentWorkers[config.id] != nil {
            return
        }
        let activeConfig = AppState.shared.storage.configurations
            .first(where: { $0.id == config.id }) ?? config
        self.config = activeConfig
        activeConfigId = activeConfig.id
        if !isBackgroundWorker {
            activeTransferConfigIds.insert(activeConfig.id)
            tabProgressByConfig[activeConfig.id] = 0
        }
        captureDriveSnapshot(paths: activeConfig.sourcePaths + activeConfig.destinationPaths)
        verifiedDestinationsByConfig.removeValue(forKey: activeConfig.id)
        transferStartTime = Date()
        // Reset progress before starting new transfer
        progress.resetProgress()
        isTransferring = true
        results = []
        destinationProgress.removeAll()
        pathProgress.removeAll()
        destinationLiveProgress.removeAll()
        activeSourceByDestination.removeAll()
        clearProgressObservers()
        currentDestinationIndex = 0
        isCancellingAll = false
        isPausingAll = false
        shouldCancelCurrentOnly = false
        cancelledDestinations = []
        currentSources = activeConfig.sourcePaths
        currentDestination = ""
        allDestinations = activeConfig.destinationPaths
        isParallelRun = activeConfig.runInParallel
        activeServices = []
        currentService = nil
        duplicates.reset()
        duplicatePromptCancelled = false
        
        // Mark as used
        AppState.shared.storage.markAsUsed(activeConfig)
        
        let destinations = activeConfig.destinationPaths
        let organizationPreset = resolveOrganizationPreset(for: activeConfig)
        let sources = activeConfig.sourcePaths

        do {
            currentSources = sources

            // Decide whether to fan out to all destinations at once or copy them
            // one at a time, per the configured destination copy mode.
            let copySequentially = shouldCopyDestinationsSequentially(
                mode: activeConfig.destinationCopyMode,
                destinations: destinations
            )

            // Run the fan-out engine either once (all dests) or once per dest.
            let destinationGroups: [[String]] = copySequentially
                ? destinations.map { [$0] }
                : [destinations]

            var perDestResults: [TransferResult] = []
            for group in destinationGroups {
                if isCancellingAll { break }
                let fanOutResult = await runFanOut(
                    destinations: group,
                    sources: sources,
                    config: activeConfig,
                    organizationPreset: organizationPreset
                )
                let exploded = explodeFanOutResult(fanOutResult, configName: activeConfig.name)
                // If exploded is empty the fan-out threw before producing per-dest
                // results (e.g. insufficient disk space). Fall back to the aggregate
                // result so the error surfaces in history and triggers a notification.
                let groupResults: [TransferResult] = exploded.isEmpty ? [fanOutResult] : exploded
                results.removeAll(where: { $0.id == fanOutResult.id })
                results.append(contentsOf: groupResults)
                perDestResults.append(contentsOf: groupResults)
            }

            // Re-run of an already-complete backup: every destination skipped
            // every file (nothing copied). Don't add a history card — show an
            // "already backed up" popup instead.
            let nothingCopied = !perDestResults.isEmpty
                && perDestResults.allSatisfy { $0.success && $0.filesTransferred == 0 && $0.filesSkipped > 0 }
            if nothingCopied {
                let ids = Set(perDestResults.map { $0.id })
                results.removeAll { ids.contains($0.id) }
                alreadyBackedUp = AlreadyBackedUpInfo(
                    sources: sources,
                    destinations: perDestResults.map { $0.destination },
                    fileCount: perDestResults.map { $0.filesSkipped }.max() ?? 0
                )
            } else {
                BackupLogWriter.writeFanOutLogs(
                    config: activeConfig,
                    sources: sources,
                    results: &perDestResults,
                    preset: organizationPreset
                )
                await recordHistory(
                    config: activeConfig,
                    sources: sources,
                    results: perDestResults,
                    preset: organizationPreset
                )
                await NotificationDispatcher.sendSource(
                    source: sources.first ?? "",
                    config: activeConfig,
                    results: perDestResults,
                    settings: makeNotificationSettings(),
                    summaryFor: { [self] result in
                        await self.destinationNotificationSummary(
                            source: sources.first ?? "",
                            config: activeConfig,
                            result: result
                        )
                    }
                )
            }
        }

        isTransferring = false
        driveCapacitySnapshot.removeAll()
        currentService = nil
        if !isBackgroundWorker {
            activeTransferConfigIds.remove(activeConfig.id)
        }
    }

    func clearLastRun(for configId: UUID?) {
        guard !isTransferring else { return }
        if let configId, activeTransferConfigIds.contains(configId) {
            return
        }
        if let configId, activeConfigId != configId {
            return
        }
        let targetId = configId ?? activeConfigId
        results = []
        cancelledDestinations = []
        currentDestination = ""
        allDestinations = []
        progress.resetProgress()
        activeConfigId = nil
        destinationProgress.removeAll()
        pathProgress.removeAll()
        destinationLiveProgress.removeAll()
        activeSourceByDestination.removeAll()
        driveCapacitySnapshot.removeAll()
        clearProgressObservers()
        progressBinding?.cancel()
        currentService = nil
        if let targetId {
            verifiedDestinationsByConfig.removeValue(forKey: targetId)
            tabProgressByConfig.removeValue(forKey: targetId)
        }
    }

    func isTransferActive(for configId: UUID) -> Bool {
        if activeConfigId == configId, isTransferring {
            return true
        }
        if activeTransferConfigIds.contains(configId) {
            return true
        }
        if let worker = concurrentWorkers[configId], worker.isTransferring {
            return true
        }
        return false
    }

    func tabProgress(for configId: UUID) -> Double {
        if activeConfigId == configId, isTransferring {
            return progress.overallProgress
        }
        return tabProgressByConfig[configId] ?? 0
    }

    func hasActiveTransfers() -> Bool {
        if isTransferring { return true }
        if !activeTransferConfigIds.isEmpty { return true }
        return concurrentWorkers.values.contains(where: { $0.isTransferring })
    }

    private func startConcurrentTransfer(config: BackupConfiguration) {
        let activeConfig = AppState.shared.storage.configurations
            .first(where: { $0.id == config.id }) ?? config
        let configId = activeConfig.id
        guard concurrentWorkers[configId] == nil else { return }

        let worker = TransferViewModel(isBackgroundWorker: true)
        concurrentWorkers[configId] = worker
        activeTransferConfigIds.insert(configId)
        tabProgressByConfig[configId] = 0

        var cancellables = Set<AnyCancellable>()
        worker.$progress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] progress in
                self?.tabProgressByConfig[configId] = progress.overallProgress
            }
            .store(in: &cancellables)

        worker.$isTransferring
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running in
                guard let self else { return }
                if !running, self.concurrentWorkers[configId] == nil {
                    self.activeTransferConfigIds.remove(configId)
                }
            }
            .store(in: &cancellables)

        concurrentWorkerCancellables[configId] = cancellables

        Task { [weak self, worker] in
            await worker.startTransfer(config: activeConfig)
            await MainActor.run {
                self?.finishConcurrentTransfer(configId: configId, worker: worker)
            }
        }
    }

    private func finishConcurrentTransfer(configId: UUID, worker: TransferViewModel) {
        tabProgressByConfig[configId] = worker.progress.overallProgress
        activeTransferConfigIds.remove(configId)
        concurrentWorkerCancellables[configId]?.forEach { $0.cancel() }
        concurrentWorkerCancellables.removeValue(forKey: configId)
        concurrentWorkers.removeValue(forKey: configId)
    }

    private func captureDriveSnapshot(paths: [String]) {
        var snapshot: [String: DriveCapacitySnapshot] = [:]
        for path in paths {
            let summary = DriveUtilities.summary(for: path)
            if snapshot[summary.id] == nil {
                let capacity = DriveUtilities.capacity(for: path)
                snapshot[summary.id] = DriveCapacitySnapshot(
                    totalBytes: capacity.total,
                    availableBytes: capacity.available
                )
            }
        }
        driveCapacitySnapshot = snapshot
    }

    func setVerifiedDestinations(_ destinations: Set<String>, for configId: UUID) {
        verifiedDestinationsByConfig[configId] = destinations
    }

    func clearVerifiedDestinations(for configId: UUID) {
        verifiedDestinationsByConfig.removeValue(forKey: configId)
    }

    func resetDestinationPresentation(for destination: String) {
        results.removeAll { $0.destination == destination }
        cancelledDestinations.remove(destination)
        destinationProgress.removeValue(forKey: destination)
        destinationLiveProgress.removeValue(forKey: destination)
        activeSourceByDestination.removeValue(forKey: destination)
        let prefix = destination + "||"
        pathProgress = pathProgress.filter { key, _ in !key.hasPrefix(prefix) }
        if currentDestination == destination && !isTransferring {
            currentDestination = ""
        }
    }

    func progressForPath(destination: String, source: String) -> Double {
        let key = progressKey(destination: destination, source: source)
        return pathProgress[key] ?? 0
    }

    func liveProgress(for destination: String) -> DestinationLiveProgress? {
        destinationLiveProgress[destination]
    }

    func activeSource(for destination: String) -> String? {
        activeSourceByDestination[destination]
    }

    private func progressKey(destination: String, source: String) -> String {
        return destination + "||" + source
    }

    private func clearProgressObservers() {
        destinationProgressCancellables.values.forEach { $0.cancel() }
        destinationProgressCancellables.removeAll()
    }

    private func trackProgress(service: TransferService, destination: String, source: String) {
        destinationProgress[destination] = 0
        activeSourceByDestination[destination] = source
        let key = progressKey(destination: destination, source: source)
        pathProgress[key] = 0
        destinationProgressCancellables[destination] = service.progress.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let serviceProgress = service.progress
                let value = serviceProgress.overallProgress
                self.destinationProgress[destination] = value
                self.pathProgress[key] = value
                self.destinationLiveProgress[destination] = Self.snapshot(from: serviceProgress)
            }
    }

    private static func snapshot(from progress: TransferProgress) -> DestinationLiveProgress {
        DestinationLiveProgress(
            isRunning: progress.isRunning,
            isCancelled: progress.isCancelled,
            isPaused: progress.isPaused,
            phase: progress.phase,
            copyingDone: progress.copyingDone,
            filesCompleted: progress.filesCompleted,
            filesTotal: progress.filesTotal,
            bytesCompleted: progress.bytesCompleted,
            cumulativeBytes: progress.cumulativeBytes,
            totalBytes: progress.totalBytes,
            speedBytesPerSecond: progress.speedBytesPerSecond,
            estimatedTimeRemaining: progress.estimatedTimeRemaining,
            verificationHasStarted: progress.verificationHasStarted,
            verificationIsActive: progress.verificationIsActive,
            verificationPhase: progress.verificationPhase,
            verificationFilesCompleted: progress.verificationFilesCompleted,
            verificationFilesTotal: progress.verificationFilesTotal,
            verificationBytesCompleted: progress.verificationBytesCompleted,
            verificationBytesTotal: progress.verificationBytesTotal,
            verificationWeightedProgress: progress.verificationWeightedProgress
        )
    }

    var activeDuplicatePrompt: DuplicatePrompt? {
        get { duplicates.activeDuplicatePrompt }
        set { duplicates.activeDuplicatePrompt = newValue }
    }

    var pendingUnreadableFiles: [String] {
        get { duplicates.pendingUnreadableFiles }
        set { duplicates.pendingUnreadableFiles = newValue }
    }

    func resolveDuplicate(prompt: DuplicatePrompt) async -> DuplicateResolution {
        await duplicates.resolveDuplicate(prompt: prompt)
    }

    @MainActor
    func submitDuplicateResolution(
        action: OrganizationPreset.DuplicatePolicy,
        applyToAll: Bool,
        counterTemplate: String? = nil
    ) {
        duplicates.submitDuplicateResolution(action: action, applyToAll: applyToAll, counterTemplate: counterTemplate)
    }

    private func resolveOrganizationPreset(for config: BackupConfiguration) -> OrganizationPreset? {
        if let id = config.selectedOrganizationPresetId,
           var preset = AppState.shared.storage.organizationPresets.first(where: { $0.id == id }) {
            // The Camera/Sound folder templates are user-editable on the config for the
            // Netflix preset; let them drive routing.
            if preset.name == OrganizationPreset.netflixIngestName {
                let cam = config.cameraFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cam.isEmpty { preset.folderTemplate = config.cameraFolderTemplate }
                let snd = config.soundFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !snd.isEmpty { preset.soundFolderTemplate = config.soundFolderTemplate }
            }
            return preset
        }
        let hasTemplate = config.offOrganizationUseFolderTemplate
            && !config.offOrganizationFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRename = config.offOrganizationUseRenameTemplate
            && !config.offOrganizationRenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPatterns = SourceFilterMatching.hasCustomFilterPatterns(
            include: config.offOrganizationIncludePatterns,
            exclude: config.offOrganizationExcludePatterns,
            copyOnly: config.offOrganizationCopyOnlyPatterns
        )
        let hasCustomDate = config.offOrganizationUseCustomDate
        guard hasTemplate || hasRename || hasPatterns || hasCustomDate else { return nil }
        var preset = OrganizationPreset()
        preset.name = "Custom"
        preset.folderTemplate = config.offOrganizationFolderTemplate
        preset.renameTemplate = config.offOrganizationRenameTemplate
        preset.useFolderTemplate = config.offOrganizationUseFolderTemplate
        preset.useRenameTemplate = config.offOrganizationUseRenameTemplate
        preset.renameOnlyPatterns = config.offOrganizationRenameOnlyPatterns
        preset.includePatterns = config.offOrganizationIncludePatterns
        preset.excludePatterns = config.offOrganizationExcludePatterns
        preset.copyOnlyPatterns = config.offOrganizationCopyOnlyPatterns
        preset.useCustomDate = config.offOrganizationUseCustomDate
        preset.customDate = config.offOrganizationCustomDate
        return preset
    }

    private func resolvedPreset(from ctx: RunContext) -> OrganizationPreset? {
        guard let id = ctx.organizationPresetId,
              var preset = AppState.shared.storage.organizationPresets.first(where: { $0.id == id }) else {
            return nil
        }
        if preset.name == OrganizationPreset.netflixIngestName {
            if let cam = ctx.cameraFolderTemplate, !cam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preset.folderTemplate = cam
            }
            if let snd = ctx.soundFolderTemplate, !snd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preset.soundFolderTemplate = snd
            }
        }
        return preset
    }

    /// Per-source Camera/Sound tags for the run: explicit tags from the config,
    /// plus any source whose volume/folder name matches a Sound auto-detect pattern.
    private func effectiveSourceMediaKinds(
        for config: BackupConfiguration, sources: [String]
    ) -> [String: SourceMediaKind] {
        var kinds = config.sourceMediaKinds
        guard config.soundAutoDetectEnabled else { return kinds }
        let patterns = config.soundAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !patterns.isEmpty else { return kinds }
        for src in sources where kinds[src] == nil {
            let names = [(src as NSString).lastPathComponent, volumeName(forPath: src)]
            if patterns.contains(where: { p in names.contains { SourceFilterMatching.matchesPattern($0, pattern: p) } }) {
                kinds[src] = .sound
            }
        }
        return kinds
    }

    private func volumeName(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let name = values.volumeName, !name.isEmpty {
            return name
        }
        return (path as NSString).lastPathComponent
    }

    private func destinationNotificationSummary(
        source: String,
        config: BackupConfiguration,
        result: TransferResult
    ) async -> NotificationSummaryBuilder.DestinationNotificationSummary {
        let transferred = result.visibleFilesTransferred ?? result.filesTransferred
        let skipped = result.visibleFilesSkipped ?? result.filesSkipped
        var totalFiles = max(transferred + skipped, 0)
        if totalFiles == 0 {
            totalFiles = await countVisibleFiles(sources: [source])
        }
        var totalBytes: Int64 = result.totalBytes > 0 ? result.totalBytes : result.bytesTransferred
        if totalBytes == 0 {
            totalBytes = await Task.detached(priority: .utility) {
                PreviewCalculator.calculateTotalsAndSizes(for: [source]).0
            }.value
        }
        return NotificationSummaryBuilder.destinationSummary(
            source: source,
            config: config,
            result: result,
            totalFiles: totalFiles,
            totalBytes: totalBytes,
            settings: makeNotificationSettings()
        )
    }

    private func makeNotificationSettings() -> NotificationSettings {
        NotificationSettings(
            notifyOnComplete: notifyOnComplete, notifyOnError: notifyOnError,
            ntfyEnabled: ntfyEnabled, ntfyURL: ntfyURL,
            ntfyTitleTemplate: ntfyTitleTemplate, ntfyMessageTemplate: ntfyMessageTemplate,
            webhookEnabled: webhookEnabled, webhookURL: webhookURL,
            webhookIncludeFullPaths: webhookIncludeFullPaths)
    }

    func cancelRunFromDuplicatePrompt() {
        duplicatePromptCancelled = true
        cancelAll()
        duplicates.submitDuplicateResolution(action: .skip, applyToAll: true, counterTemplate: nil)
    }

    @MainActor
    func resolveUnreadable(proceed: Bool) {
        duplicates.resolveUnreadable(proceed: proceed)
    }

    /// Re-verify an already-backed-up config against its hash lists (the same
    /// check as "Check data" in History). Runs off the main thread.
    func verifyAlreadyBackedUp(_ info: AlreadyBackedUpInfo) async -> (total: Int, missing: Int, mismatched: Int) {
        let rootNames = info.sources.map { ($0 as NSString).lastPathComponent }
        let sources = info.sources
        let dests = info.destinations
        return await Task.detached(priority: .utility) {
            var total = 0, missing = 0, mismatched = 0
            for dest in dests {
                for root in rootNames {
                    let mhl = (dest as NSString).appendingPathComponent(".filmcan/hashlists/\(root).mhl")
                    if let r = HashListVerifier.verify(hashListPath: mhl, rootsFallback: sources) {
                        total += r.total; missing += r.missing; mismatched += r.mismatched
                    }
                }
            }
            return (total, missing, mismatched)
        }.value
    }

    static func manifestUnsealedWarning(_ reason: String?) -> String? {
        HistoryRecorder.manifestUnsealedWarning(reason)
    }

    func explodeFanOutResult(_ fanOut: TransferResult, configName: String) -> [TransferResult] {
        fanOut.destinationResults.map { dr in
            var r = TransferResult(
                configurationName: configName,
                destination: dr.destinationPath,
                startTime: fanOut.startTime,
                endTime: fanOut.endTime,
                success: dr.success,
                errorMessage: dr.success ? nil : dr.failureReason?.displayMessage,
                warningMessage: Self.manifestUnsealedWarning(dr.manifestUnsealedReason),
                filesTransferred: dr.filesTransferred,
                bytesTransferred: dr.bytesTransferred,
                totalBytes: dr.bytesTransferred,
                filesSkipped: dr.filesSkipped,
                errors: dr.success ? [] : [dr.failureReason?.displayMessage ?? "Failed"],
                hashListPath: dr.mhlPath,
                wasVerified: dr.success && dr.verifyMode == .paranoid
            )
            // Truthful "transferred items" list: exactly the files copied this run,
            // not the (cumulative) hash list which also carries forward prior entries.
            r.transferredPaths = dr.transferredFileNames
            r.destinationResults = [dr]
            return r
        }
    }

    // MARK: - Fan-out engine

    /// Decide whether destinations are written one at a time.
    ///
    /// `.automatic` defaults to parallel fan-out (the fast path) and only falls
    /// back to sequential for concrete reasons: a network destination, or two
    /// destinations that live on the *same physical volume* (parallel writes to
    /// one drive thrash it). It deliberately does NOT gate on the "solid state"
    /// volume flag — macOS reports that unreliably for external USB/Thunderbolt
    /// SSDs (often false), which previously forced fast SSDs into slow sequential
    /// copies. A single destination is always one group (nothing to serialize).
    private func shouldCopyDestinationsSequentially(
        mode: DestinationCopyMode,
        destinations: [String]
    ) -> Bool {
        guard destinations.count > 1 else { return false }
        switch mode {
        case .parallel:   return false
        case .sequential: return true
        case .automatic:
            let infos = destinations.map { DriveSpeedClassifier.info(for: $0) }
            if infos.contains(where: { $0.isNetwork }) { return true }
            // Two+ destinations sharing one physical volume → serialize.
            let uuids = infos.compactMap { $0.volumeUUID }
            if Set(uuids).count < uuids.count { return true }
            return false
        }
    }

    private func runFanOut(
        destinations: [String],
        sources: [String],
        config: BackupConfiguration,
        organizationPreset: OrganizationPreset?
    ) async -> TransferResult {
        let service = CustomCopierService()
        currentService = service
        activeServices = [service]
        defer { activeServices = [] }

        let verifyMode = config.engineOptions.verificationMode
        let fanOutDests: [DestWriter.Config] = destinations.map { destPath in
            let info = DriveSpeedClassifier.info(for: destPath)
            return DestWriter.Config(
                destPath: destPath,
                displayName: (destPath as NSString).lastPathComponent,
                verifyMode: verifyMode,
                requiresFullFsync: DriveSpeedClassifier.requiresFullFsync(info),
                chunkSize: nil
            )
        }

        do {
            defer {
                self.activeSourceByDestination.removeAll()
            }
            let result = try await service.runCopyFanOut(
                sources: sources,
                fanOutDestinations: fanOutDests,
                configName: config.name,
                organizationPreset: organizationPreset,
                copyFolderContents: config.copyFolderContents,
                useHashListPrecheck: config.engineOptions.customVerifyEnabled,
                hashListPath: nil,
                fileOrdering: config.engineOptions.fileOrdering,
                duplicatePolicy: config.duplicatePolicy,
                duplicateCounterTemplate: config.duplicateCounterTemplate,
                duplicateResolver: (config.duplicatePolicy == .ask || config.duplicatePolicy == .verify)
                    ? { @Sendable [weak self] prompt async -> DuplicateResolution in
                        guard let self else {
                            return DuplicateResolution(action: .skip, applyToAll: false, counterTemplate: nil)
                        }
                        return await self.resolveDuplicate(prompt: prompt)
                    }
                    : nil,
                verifyMode: verifyMode,
                dryRun: false,
                forceRecopy: config.forceRecopy,
                shootMetadata: ShootMetadata(episode: config.episode, day: config.day,
                                             unit: config.unit, cameraFormat: config.cameraFormat),
                sourceMediaKinds: effectiveSourceMediaKinds(for: config, sources: sources),
                hashListStyle: config.hashListStyle,
                reVerifyExistingOnResume: config.reVerifyExistingOnResume,
                unreadableHandler: { [weak self] paths async -> Bool in
                    guard let self else { return false }
                    return await withCheckedContinuation { continuation in
                        Task { @MainActor [weak self] in
                            guard let self else { continuation.resume(returning: false); return }
                            self.duplicates.setUnreadableContinuation(continuation, paths: paths)
                        }
                    }
                },
                progressHandler: { [weak self] progresses in
                    guard let self else { return }
                    Task { @MainActor in
                        // Merge by id rather than replace: in sequential copy mode
                        // each runFanOut call only reports its own destination, and
                        // a wholesale replace would drop the already-finished dests'
                        // rows (losing their completed state in the UI).
                        for incoming in progresses {
                            var prog = incoming
                            if let idx = self.progress.perDestProgress.firstIndex(where: { $0.id == prog.id }) {
                                // Clamp copy/verify bytes to a per-dest running max so the
                                // bars never visibly step backward. With the copy/verify
                                // pipeline, emits arrive from concurrent producers and can
                                // be delivered slightly out of order; a stale copy-phase
                                // emit must not reset the verify bar a completed verify
                                // already advanced. Terminal states (failed) bypass the
                                // clamp so a cancel/verify failure can still surface.
                                let prev = self.progress.perDestProgress[idx]
                                if case .failed = prog.status {} else {
                                    prog.bytesCompleted = max(prog.bytesCompleted, prev.bytesCompleted)
                                    prog.verifyBytesCompleted = max(prog.verifyBytesCompleted, prev.verifyBytesCompleted)
                                }
                                self.progress.perDestProgress[idx] = prog
                            } else {
                                self.progress.perDestProgress.append(prog)
                            }
                        }
                        self.progress.syncFromPerDest()
                        for prog in progresses {
                            let copyFraction = prog.progressFraction
                            let verifyFraction: Double
                            if prog.verifyBytesTotal > 0 {
                                verifyFraction = min(Double(prog.verifyBytesCompleted) / Double(prog.verifyBytesTotal), 1.0)
                            } else {
                                verifyFraction = 0
                            }
                            let blended: Double
                            if prog.verifyBytesTotal > 0 {
                                blended = copyFraction * 0.5 + verifyFraction * 0.5
                            } else {
                                blended = copyFraction
                            }
                            self.destinationProgress[prog.id] = blended
                        }
                    }
                }
            )
            results.append(result)
            return result
        } catch {
            let failed = TransferResult(
                configurationName: config.name,
                destination: destinations.first ?? "",
                startTime: transferStartTime ?? Date(),
                endTime: Date(),
                success: false,
                errorMessage: error.localizedDescription,
                warningMessage: nil,
                filesTransferred: 0,
                bytesTransferred: 0,
                totalBytes: 0,
                filesSkipped: 0,
                errors: [error.localizedDescription],
                hashListPath: nil,
                wasVerified: false
            )
            results.append(failed)
            return failed
        }
    }

    private func visibleTransferredCount(from paths: [String]) -> Int {
        HistoryRecorder.visibleTransferredCount(from: paths)
    }

    private func countVisibleFiles(sources: [String]) async -> Int {
        await HistoryRecorder.countVisibleFiles(sources: sources)
    }

    private nonisolated static func isHiddenPath(_ path: String) -> Bool {
        HistoryRecorder.isHiddenPath(path)
    }

    private func hashRoots(result: TransferResult, sources: [String], destination: String) -> [String] {
        HistoryRecorder.hashRoots(result: result, sources: sources, destination: destination)
    }

    private func recordHistory(
        config: BackupConfiguration,
        sources: [String],
        results: [TransferResult],
        preset: OrganizationPreset?
    ) async {
        guard !results.isEmpty else { return }
        let ctx = await historyRecorder.record(
            config: config,
            sources: sources,
            results: results,
            preset: preset,
            transferStartTime: transferStartTime,
            retentionLimit: historyRetentionLimit
        )
        lastRunContext = ctx
    }

    func cancel() {
        currentService?.cancel()
    }

    func pauseAll() {
        if !isBackgroundWorker {
            if let selectedConfigId = AppState.shared.selectedConfigId,
               let worker = concurrentWorkers[selectedConfigId] {
                worker.pauseAll()
                return
            }
        }
        isPausingAll = true
        if isParallelRun {
            activeServices.forEach { $0.pause() }
            progress.isPaused = true
            progress.isRunning = false
        } else {
            currentService?.pause()
        }
    }

    func cancelDestination(_ destination: String) {
        if !isBackgroundWorker,
           let selectedConfigId = AppState.shared.selectedConfigId,
           let worker = concurrentWorkers[selectedConfigId] {
            worker.cancelDestination(destination)
            return
        }
        if isParallelRun {
            cancelAll()
            return
        }

        if destination == currentDestination {
            cancelCurrentOnly()
        } else {
            cancelledDestinations.insert(destination)
        }
    }
    
    func cancelCurrentOnly() {
        if !isBackgroundWorker,
           let selectedConfigId = AppState.shared.selectedConfigId,
           let worker = concurrentWorkers[selectedConfigId] {
            worker.cancelCurrentOnly()
            return
        }
        shouldCancelCurrentOnly = true
        currentService?.cancel()
    }
    
    func cancelAll() {
        if !isBackgroundWorker {
            // App-level cancel: stop all in-flight transfers across tabs.
            for worker in concurrentWorkers.values {
                worker.cancelAll()
            }
            concurrentWorkers.removeAll()
            concurrentWorkerCancellables.values.forEach { set in
                set.forEach { $0.cancel() }
            }
            concurrentWorkerCancellables.removeAll()
            activeTransferConfigIds.removeAll()
        }
        isCancellingAll = true
        shouldCancelCurrentOnly = true
        if isParallelRun {
            activeServices.forEach { $0.cancel() }
        } else {
            currentService?.cancel()
        }
    }

    func cancelAll(for configId: UUID) {
        if activeConfigId == configId {
            cancelAll()
            return
        }
        if let worker = concurrentWorkers[configId] {
            worker.cancelAll()
            concurrentWorkers.removeValue(forKey: configId)
            concurrentWorkerCancellables[configId]?.forEach { $0.cancel() }
            concurrentWorkerCancellables.removeValue(forKey: configId)
            activeTransferConfigIds.remove(configId)
            tabProgressByConfig.removeValue(forKey: configId)
        }
    }

    /// Repair a failed destination by copying each file from a verified
    /// sibling destination's MHL hash list. Caller picks the sibling
    /// (typically the fastest surviving dest, via FailedDestRetryPanel).
    /// Returns a per-file result: (fileName, success).
    @discardableResult
    func retryFailedDestinationFromSibling(
        failed: DestResult,
        sibling: DestResult
    ) async -> [(fileName: String, success: Bool)] {
        guard let siblingMHL = sibling.mhlPath else { return [] }
        let mhlURL = URL(fileURLWithPath: siblingMHL)

        let entries: [ASCMHLReader.Entry]
        do {
            entries = try ASCMHLReader.read(url: mhlURL)
        } catch {
            return []
        }
        guard !entries.isEmpty else { return [] }

        // The manifest lives at <rollFolder>/ascmhl/<name>.mhl and each entry's
        // relPath is relative to <rollFolder>, NOT the dest root. Derive both roll
        // folders so organized (Netflix) layouts repair into the correct nested
        // path rather than joining relPath onto the bare dest root.
        let siblingRoot = sibling.destinationPath
        let failedRoot = failed.destinationPath
        let siblingRoll = mhlURL.deletingLastPathComponent().deletingLastPathComponent().path
        let relRoll = siblingRoll.hasPrefix(siblingRoot)
            ? String(siblingRoll.dropFirst(siblingRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : ""
        let failedRoll = relRoll.isEmpty
            ? failedRoot
            : (failedRoot as NSString).appendingPathComponent(relRoll)

        // exFAT/USB destinations (often the very drive that failed) need F_FULLFSYNC.
        let requiresFullFsync = DriveSpeedClassifier.requiresFullFsync(
            DriveSpeedClassifier.info(for: failedRoot))

        let source = SiblingDestSource()
        var results: [(fileName: String, success: Bool)] = []
        var copied: [MHLEntry] = []
        for entry in entries {
            let siblingFilePath = (siblingRoll as NSString).appendingPathComponent(entry.relPath)
            let failedFilePath = (failedRoll as NSString).appendingPathComponent(entry.relPath)
            do {
                try await source.copyFromSibling(
                    fileName: entry.relPath,
                    from: siblingFilePath,
                    to: failedFilePath,
                    expectedHash: entry.hash,
                    requiresFullFsync: requiresFullFsync
                )
                results.append((entry.relPath, true))
                copied.append(MHLEntry(relPath: entry.relPath, size: entry.size ?? 0,
                                       hash: entry.hash, mtime: entry.mtime))
            } catch {
                results.append((entry.relPath, false))
            }
        }

        // Chain of custody: seal a fresh ASC MHL generation for the repaired
        // destination so it isn't left certified-but-manifestless (its prior run
        // wrote only a partial, un-chained generation). Only when EVERY file landed
        // and hash-verified — a partial repair must never seal a manifest.
        if !copied.isEmpty, results.allSatisfy({ $0.success }) {
            let ascDir = URL(fileURLWithPath: failedRoll).appendingPathComponent("ascmhl")
            let rollName = (failedRoll as NSString).lastPathComponent
            if let writer = try? ASCMHLWriter(ascmhlDir: ascDir, rollName: rollName) {
                await writer.seed(copied)
                try? await writer.seal()
            }
        }
        return results
    }

    /// User-facing entry-point invoked by `FailedDestRetryPanel`'s onRepair closure.
    /// Branches on the chosen repair source. Mutates `results` so the UI flips the
    /// failed dest entry to `.success == true` when every file lands and verifies.
    /// Returns `true` only when ALL files repaired successfully.
    @discardableResult
    func repairFailedDest(
        failed: DestResult,
        sibling: DestResult,
        choice: RetryRepairSheet.RepairChoice
    ) async -> Bool {
        switch choice {
        case .fromSibling:
            let perFile = await retryFailedDestinationFromSibling(failed: failed, sibling: sibling)
            let allOK = !perFile.isEmpty && perFile.allSatisfy { $0.success }
            if allOK {
                patchDestResultToSuccess(destPath: failed.destinationPath, filesTransferred: perFile.count)
            }
            return allOK
        case .fromSource:
            let sources = currentSources
            guard !sources.isEmpty else { return false }
            // Sanity check: every source path must still exist on disk before we attempt re-copy.
            let fm = FileManager.default
            for path in sources {
                if !fm.fileExists(atPath: path) { return false }
            }
            let info = DriveSpeedClassifier.info(for: failed.destinationPath)
            let destCfg = DestWriter.Config(
                destPath: failed.destinationPath,
                displayName: failed.displayName,
                verifyMode: failed.verifyMode,
                requiresFullFsync: DriveSpeedClassifier.requiresFullFsync(info),
                chunkSize: nil
            )
            let repairCtx = lastRunContext
            let repairPreset = repairCtx.flatMap { resolvedPreset(from: $0) }
            let service = CustomCopierService()
            let recovered: TransferResult
            do {
                recovered = try await service.runCopyFanOut(
                    sources: sources,
                    fanOutDestinations: [destCfg],
                    configName: "repair",
                    organizationPreset: repairPreset,
                    copyFolderContents: repairCtx?.copyFolderContents ?? false,
                    useHashListPrecheck: false,
                    hashListPath: nil,
                    fileOrdering: .defaultOrder,
                    duplicatePolicy: repairCtx?.duplicatePolicy ?? .ask,
                    duplicateCounterTemplate: "",
                    duplicateResolver: nil,
                    verifyMode: failed.verifyMode,
                    dryRun: false,
                    sourceMediaKinds: repairCtx?.sourceMediaKinds ?? [:],
                    hashListStyle: repairCtx?.hashListStyle ?? .ascMHL,
                    progressHandler: nil
                )
            } catch {
                return false
            }
            let allOK = recovered.destinationResults.allSatisfy { $0.success }
            if allOK {
                patchDestResultToSuccess(
                    destPath: failed.destinationPath,
                    filesTransferred: recovered.filesTransferred
                )
            }
            return allOK
        }
    }

    /// Find the most recent TransferResult whose `destinationResults` contains the failed
    /// dest, and flip that DestResult entry's `success` to true. UI re-renders via
    /// @Published `results`.
    private func patchDestResultToSuccess(destPath: String, filesTransferred: Int) {
        for resultIndex in results.indices.reversed() {
            if let destIdx = results[resultIndex].destinationResults.firstIndex(where: { $0.destinationPath == destPath }) {
                results[resultIndex].destinationResults[destIdx].success = true
                results[resultIndex].destinationResults[destIdx].failureReason = nil
                results[resultIndex].destinationResults[destIdx].filesTransferred = filesTransferred
                results[resultIndex].destinationResults[destIdx].filesFailedAfterCopy = 0
                // Recompute parent overall success
                let stillFailing = results[resultIndex].destinationResults.contains(where: { !$0.success })
                results[resultIndex].success = !stillFailing
                if !stillFailing {
                    results[resultIndex].errorMessage = nil
                }
                return
            }
        }
    }
}
