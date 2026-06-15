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
    @AppStorage("ntfyBearerToken") private var ntfyBearerToken: String = ""
    @AppStorage("ntfyTitleTemplate") private var ntfyTitleTemplate: String = "{source}'s backup to {destinations} for {movie} : {backupStatus}"
    @AppStorage("ntfyMessageTemplate") private var ntfyMessageTemplate: String = "{bytes} ({files} files) from {source} has been {backupAction} to {destination} in {duration}.\n{backupDetails}"
    @AppStorage("webhookEnabled") private var webhookEnabled: Bool = false
    @AppStorage("webhookURL") private var webhookURL: String = ""
    @AppStorage("webhookHeaders") private var webhookHeaders: String = ""
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
    @Published var activeDuplicatePrompt: DuplicatePrompt? = nil
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
    
    private let rsyncService = AppState.shared.rsyncService
    private var config: BackupConfiguration?
    private var transferStartTime: Date?
    private var isPausingAll: Bool = false
    private var activeServices: [TransferService] = []
    private var cachedDuplicateResolution: DuplicateResolution? = nil
    private var pendingDuplicatePrompts: [PendingDuplicatePrompt] = []
    private var activeDuplicateContinuation: CheckedContinuation<DuplicateResolution, Never>? = nil
    private var isShowingDuplicatePrompt: Bool = false
    private var duplicatePromptCancelled: Bool = false
    private var destinationProgressCancellables: [String: AnyCancellable] = [:]
    private var progressBinding: AnyCancellable? = nil
    private var currentService: TransferService? = nil
    private let isBackgroundWorker: Bool
    private var concurrentWorkers: [UUID: TransferViewModel] = [:]
    private var concurrentWorkerCancellables: [UUID: Set<AnyCancellable>] = [:]

    private struct PendingDuplicatePrompt {
        let prompt: DuplicatePrompt
        let continuation: CheckedContinuation<DuplicateResolution, Never>
    }
    
    init(isBackgroundWorker: Bool = false) {
        self.isBackgroundWorker = isBackgroundWorker
        bindProgress(to: rsyncService)
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
        resetDuplicatePromptState()
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
                writeFanOutLogs(
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
                await sendSourceNotifications(
                    source: sources.first ?? "",
                    config: activeConfig,
                    results: perDestResults
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

    private func bindProgress(to service: TransferService) {
        progressBinding?.cancel()
        if let rsync = service as? RsyncService {
            progressBinding = rsync.$progress
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    guard let self else { return }
                    self.progress = value
                    if !self.isBackgroundWorker, let configId = self.activeConfigId {
                        self.tabProgressByConfig[configId] = value.overallProgress
                    }
                }
        } else if let custom = service as? CustomCopierService {
            progressBinding = custom.$progress
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    guard let self else { return }
                    self.progress = value
                    if !self.isBackgroundWorker, let configId = self.activeConfigId {
                        self.tabProgressByConfig[configId] = value.overallProgress
                    }
                }
        } else {
            progressBinding = nil
        }
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

    func resolveDuplicate(prompt: DuplicatePrompt) async -> DuplicateResolution {
        if let cached = cachedDuplicateResolution {
            return cached
        }
        return await withCheckedContinuation { continuation in
            let pending = PendingDuplicatePrompt(prompt: prompt, continuation: continuation)
            pendingDuplicatePrompts.append(pending)
            if !isShowingDuplicatePrompt {
                presentNextDuplicatePrompt()
            }
        }
    }

    @MainActor
    func submitDuplicateResolution(
        action: OrganizationPreset.DuplicatePolicy,
        applyToAll: Bool,
        counterTemplate: String? = nil
    ) {
        let resolution = DuplicateResolution(
            action: action,
            applyToAll: applyToAll,
            counterTemplate: counterTemplate
        )
        if applyToAll {
            cachedDuplicateResolution = resolution
        }

        activeDuplicatePrompt = nil
        activeDuplicateContinuation?.resume(returning: resolution)
        activeDuplicateContinuation = nil

        if applyToAll {
            let pending = pendingDuplicatePrompts
            pendingDuplicatePrompts.removeAll()
            isShowingDuplicatePrompt = false
            pending.forEach { $0.continuation.resume(returning: resolution) }
            return
        }

        if pendingDuplicatePrompts.isEmpty {
            isShowingDuplicatePrompt = false
            return
        }
        presentNextDuplicatePrompt()
    }

    private func presentNextDuplicatePrompt() {
        guard !pendingDuplicatePrompts.isEmpty else {
            isShowingDuplicatePrompt = false
            return
        }
        let next = pendingDuplicatePrompts.removeFirst()
        activeDuplicateContinuation = next.continuation
        activeDuplicatePrompt = next.prompt
        isShowingDuplicatePrompt = true
    }

    private func resetDuplicatePromptState() {
        activeDuplicatePrompt = nil
        cachedDuplicateResolution = nil
        pendingDuplicatePrompts = []
        activeDuplicateContinuation = nil
        isShowingDuplicatePrompt = false
    }

    private func resolveOrganizationPreset(for config: BackupConfiguration) -> OrganizationPreset? {
        if let id = config.selectedOrganizationPresetId,
           let preset = AppState.shared.storage.organizationPresets.first(where: { $0.id == id }) {
            return preset
        }
        let hasTemplate = config.offOrganizationUseFolderTemplate
            && !config.offOrganizationFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRename = config.offOrganizationUseRenameTemplate
            && !config.offOrganizationRenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPatterns = hasCustomFilterPatterns(
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

    private func hasCustomFilterPatterns(
        include: [String],
        exclude: [String],
        copyOnly: [String]
    ) -> Bool {
        let normalizedInclude = normalizedPatterns(include)
        let normalizedCopyOnly = normalizedPatterns(copyOnly)
        if !normalizedInclude.isEmpty || !normalizedCopyOnly.isEmpty {
            return true
        }
        let normalizedExclude = normalizedPatterns(exclude)
        let defaultSet = Set(RsyncOptions.defaultExcludedPatterns)
        let nonDefaultExcludes = normalizedExclude.filter { !defaultSet.contains($0) }
        return !nonDefaultExcludes.isEmpty
    }

    private func normalizedPatterns(_ patterns: [String]) -> [String] {
        patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func sendSourceNotifications(
        source: String,
        config: BackupConfiguration,
        results: [TransferResult]
    ) async {
        if config.webhookTemplateFormatVersion >= 2 {
            await sendAggregatedNotifications(source: source, config: config, results: results)
            return
        }
        for result in results {
            let summary = await destinationNotificationSummary(
                source: source,
                config: config,
                result: result
            )
            guard !summary.wasPaused else { continue }

            if summary.allSuccess && notifyOnComplete {
                NotificationService.shared.notify(
                    title: summary.title,
                    body: summary.body
                )
            } else if !summary.allSuccess && notifyOnError {
                NotificationService.shared.notify(
                    title: summary.title,
                    body: summary.body
                )
            }

            if ntfyEnabled, !ntfyURL.isEmpty {
                sendNtfySummary(summary: summary)
            }
            if webhookEnabled, !webhookURL.isEmpty {
                sendWebhookSummary(summary: summary)
            }
        }
    }

    /// v2: one aggregated event per backup-run covering ALL destinations.
    private func sendAggregatedNotifications(
        source: String,
        config: BackupConfiguration,
        results: [TransferResult]
    ) async {
        guard !results.isEmpty else { return }
        let wasPaused = results.contains { $0.wasPaused }
        if wasPaused { return }

        let anyFailed = results.contains { !$0.success }
        let allSuccess = !anyFailed
        let sourceName = (source as NSString).lastPathComponent
        let totalBytes = results.reduce(Int64(0)) { $0 + $1.bytesTransferred }
        let bytesText = FilmCanFormatters.bytes(totalBytes, style: .decimal)
        let destSummary = results.map { r in
            let mark = r.success ? "✓" : "✗"
            let name = (r.destination as NSString).lastPathComponent
            return "\(name) \(mark)"
        }.joined(separator: ", ")
        let status = anyFailed ? "Done with failures" : "Done"
        let title = "\(sourceName) → \(config.name): \(status)"
        let body = "\(destSummary) — \(bytesText)"

        if allSuccess && notifyOnComplete {
            NotificationService.shared.notify(title: title, body: body)
        } else if !allSuccess && notifyOnError {
            NotificationService.shared.notify(title: title, body: body)
        }
        if ntfyEnabled, !ntfyURL.isEmpty {
            WebhookService.sendNtfy(
                urlString: ntfyURL,
                bearerToken: ntfyBearerToken,
                title: title,
                message: body,
                fields: [
                    "Source": sourceName,
                    "Config": config.name,
                    "DestinationsSummary": destSummary,
                    "AnyFailed": anyFailed ? "true" : "false",
                    "AllSucceeded": allSuccess ? "true" : "false",
                    "TotalBytes": bytesText,
                    "DestinationCount": "\(results.count)"
                ]
            )
        }
        if webhookEnabled, !webhookURL.isEmpty {
            WebhookService.sendJSON(
                urlString: webhookURL,
                headers: WebhookService.parseHeaders(from: webhookHeaders),
                payload: [
                    "title": title,
                    "message": body,
                    "templateFormatVersion": 2,
                    "source": sourceName,
                    "config": config.name,
                    "destinationCount": results.count,
                    "anyFailed": anyFailed,
                    "allSucceeded": allSuccess,
                    "totalBytes": totalBytes,
                    "destinations": results.map { r in
                        [
                            "name": (r.destination as NSString).lastPathComponent,
                            "path": r.destination,
                            "success": r.success,
                            "bytesTransferred": r.bytesTransferred,
                            "filesTransferred": r.filesTransferred,
                            "errorMessage": r.errorMessage ?? "",
                            "wasVerified": r.wasVerified
                        ] as [String: Any]
                    }
                ]
            )
        }
    }

    private struct DestinationNotificationSummary {
        let title: String
        let body: String
        let messageTitle: String
        let messageBody: String
        let fields: [String: String]
        let allSuccess: Bool
        let wasPaused: Bool
    }

    private func destinationNotificationSummary(
        source: String,
        config: BackupConfiguration,
        result: TransferResult
    ) async -> DestinationNotificationSummary {
        let wasPaused = result.wasPaused
        let isCancelled = (result.errorMessage ?? "").lowercased().contains("cancelled")
        let allSuccess = result.success && !isCancelled
        let sourceName = (source as NSString).lastPathComponent
        let destinationName = (result.destination as NSString).lastPathComponent
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
        let bytesText = FilmCanFormatters.bytes(totalBytes, style: .decimal)
        let durationText = durationString(for: [result]) ?? "0s"

        let backupAction: String
        if !result.success || isCancelled {
            backupAction = "failed to back up"
        } else if result.isAlreadyAtDestination {
            backupAction = "already in place"
        } else {
            backupAction = "backed up"
        }

        let backupStatus: String
        let backupDetails: String
        if result.success && !isCancelled {
            backupStatus = "Done."
            backupDetails = "No backup failed."
        } else if isCancelled {
            backupStatus = "Cancelled by user."
            backupDetails = "1 destination(s) failed. 1 cancelled by user."
        } else {
            backupStatus = "Failed."
            backupDetails = result.errorMessage ?? "Backup failed."
        }

        let title = "\(sourceName)'s backup for \(config.name): \(backupStatus)"
        let body = "\(bytesText) (\(totalFiles) files) from \(sourceName) has been \(backupAction) to \(destinationName) in \(durationText)."

        let sourcesText = formatQuotedList([source])
        let destinationsText = formatQuotedList(config.destinationPaths)
        let template = ntfyMessageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleTemplate = ntfyTitleTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [String: String] = [
            "{movie}": config.name,
            "{source}": sourceName,
            "{destination}": destinationName,
            "{sources}": sourcesText,
            "{destinations}": destinationsText,
            "{backupAction}": backupAction,
            "{bytes}": bytesText,
            "{files}": "\(totalFiles)",
            "{duration}": durationText,
            "{backupStatus}": backupStatus,
            "{backupDetails}": backupDetails
        ]

        let messageTitle = titleTemplate.isEmpty
            ? title
            : applyTemplate(titleTemplate, replacements: replacements)

        let messageBody = template.isEmpty
            ? body
            : applyTemplate(template, replacements: replacements)

        return DestinationNotificationSummary(
            title: title,
            body: body,
            messageTitle: messageTitle,
            messageBody: messageBody,
            fields: replacements,
            allSuccess: allSuccess,
            wasPaused: wasPaused
        )
    }

    private func sendNtfySummary(summary: DestinationNotificationSummary) {
        WebhookService.sendNtfy(
            urlString: ntfyURL,
            bearerToken: ntfyBearerToken,
            title: summary.messageTitle,
            message: summary.messageBody,
            fields: [:]
        )
    }

    private func sendWebhookSummary(summary: DestinationNotificationSummary) {
        WebhookService.sendJSON(
            urlString: webhookURL,
            headers: WebhookService.parseHeaders(from: webhookHeaders),
            payload: [
                "title": summary.messageTitle,
                "message": summary.messageBody,
                "fields": summary.fields
            ]
        )
    }

    private func formatQuotedList(_ paths: [String]) -> String {
        let names = paths.map { "\"\(($0 as NSString).lastPathComponent)\"" }
        if names.isEmpty { return "No items" }
        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) and \(names[1])" }
        let head = names.prefix(3).joined(separator: ", ")
        let remaining = names.count - 3
        if remaining > 0 {
            return "\(head), and \(remaining) others"
        }
        return head
    }

    private func durationString(for results: [TransferResult]) -> String? {
        let durations = results.compactMap { $0.duration }
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        if hours > 0 { return String(format: "%dh %dm %ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    private func applyTemplate(_ template: String, replacements: [String: String]) -> String {
        var result = template
        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }
        return result
    }

    func cancelRunFromDuplicatePrompt() {
        duplicatePromptCancelled = true
        cancelAll()
        submitDuplicateResolution(action: .skip, applyToAll: true, counterTemplate: nil)
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

    func explodeFanOutResult(_ fanOut: TransferResult, configName: String) -> [TransferResult] {
        fanOut.destinationResults.map { dr in
            var r = TransferResult(
                configurationName: configName,
                destination: dr.destinationPath,
                startTime: fanOut.startTime,
                endTime: fanOut.endTime,
                success: dr.success,
                errorMessage: dr.success ? nil : dr.failureReason?.displayMessage,
                warningMessage: nil,
                filesTransferred: dr.filesTransferred,
                bytesTransferred: dr.bytesTransferred,
                totalBytes: dr.bytesTransferred,
                filesSkipped: dr.filesSkipped,
                errors: dr.success ? [] : [dr.failureReason?.displayMessage ?? "Failed"],
                hashListPath: dr.mhlPath,
                wasVerified: dr.success && dr.verifyMode == .paranoid
            )
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

        let verifyMode = config.rsyncOptions.verificationMode
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
                useHashListPrecheck: config.rsyncOptions.customVerifyEnabled,
                hashListPath: nil,
                fileOrdering: config.rsyncOptions.fileOrdering,
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

    private func transferredPathsFromLog(
        logFile: String,
        roots: [String],
        fallbackRoot: String
    ) -> (paths: [String], sawItemize: Bool) {
        guard let content = try? String(contentsOfFile: logFile, encoding: .utf8) else {
            return ([], false)
        }
        var results: [String] = []
        var sawItemize = false

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (code, path) = extractItemizedPath(from: trimmed) else { continue }
            sawItemize = true
            guard shouldRecordItemizedFile(code) else { continue }
            let cleaned = cleanItemizedPath(path)
            guard !cleaned.isEmpty else { continue }
            let resolved = resolveLoggedPath(cleaned, roots: roots, fallbackRoot: fallbackRoot)
            if FilmCanPaths.isHidden(resolved) { continue }
            if resolved.hasSuffix("/") { continue }
            results.append(resolved)
        }

        return (Array(Set(results)), sawItemize)
    }

    private func resolveLoggedPath(_ raw: String, roots: [String], fallbackRoot: String) -> String {
        if raw.hasPrefix("/") { return raw }
        if roots.count == 1, let root = roots.first {
            return (root as NSString).appendingPathComponent(raw)
        }
        if roots.count > 1 {
            let components = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            if components.count == 2 {
                let label = String(components[0])
                let rest = String(components[1])
                if let root = roots.first(where: { ($0 as NSString).lastPathComponent == label }) {
                    return (root as NSString).appendingPathComponent(rest)
                }
            }
        }
        return (fallbackRoot as NSString).appendingPathComponent(raw)
    }

    private func extractItemizedPath(from line: String) -> (code: String, path: String)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        var cursor = line.startIndex
        for (index, token) in tokens.enumerated() {
            guard let range = line.range(of: token, range: cursor..<line.endIndex) else { continue }
            if isItemizeCode(String(token)) {
                let code = String(token)
                let pathStart = line.index(range.upperBound, offsetBy: 1, limitedBy: line.endIndex) ?? line.endIndex
                let path = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
                return (code, path)
            }
            cursor = range.upperBound
            if index == tokens.count - 1 { break }
        }
        return nil
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

    private func cleanItemizedPath(_ raw: String) -> String {
        var path = raw
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[..<arrowRange.lowerBound])
        }
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleTransferredCount(from paths: [String]) -> Int {
        paths.reduce(0) { count, path in
            Self.isHiddenPath(path) ? count : count + 1
        }
    }

    private func countVisibleFiles(sources: [String]) async -> Int {
        await Task.detached(priority: .utility) {
            var total = 0
            let fm = FileManager.default
            for source in sources {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }
                if !isDir.boolValue {
                    if !Self.isHiddenPath(source) { total += 1 }
                    continue
                }
                let rootURL = URL(fileURLWithPath: source)
                let enumerator = fm.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsPackageDescendants]
                )
                while let fileURL = enumerator?.nextObject() as? URL {
                    if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                       values.isDirectory == true {
                        continue
                    }
                    let path = fileURL.standardizedFileURL.path
                    if Self.isHiddenPath(path) { continue }
                    if fileURL.lastPathComponent == ".DS_Store" { continue }
                    total += 1
                }
            }
            return total
        }.value
    }

    private nonisolated static func isHiddenPath(_ path: String) -> Bool {
        if FilmCanPaths.isHidden(path) { return true }
        let components = path.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }

    private func resolvedLogFilePath(
        logEnabled: Bool,
        logLocation: BackupConfiguration.LogLocation,
        customLogPath: String,
        logFileNameTemplate: String,
        configName: String,
        destination: String,
        sources: [String],
        customDate: Date?
    ) -> (path: String?, warning: String?) {
        guard logEnabled else { return (nil, nil) }
        let effectiveDate = customDate ?? Date()
        let logName = LogFileNamer.makeFileName(
            template: logFileNameTemplate,
            configName: configName,
            destination: destination,
            sources: sources,
            date: effectiveDate
        )

        let preferredBase: String
        if logLocation == .custom && !customLogPath.isEmpty {
            let resolved = LogFolderNamer.resolveFolderPath(
                template: customLogPath,
                destination: destination,
                sources: sources,
                date: effectiveDate
            )
            preferredBase = resolved.isEmpty ? customLogPath : resolved
        } else {
            preferredBase = destination
        }

        let preferredPath = (preferredBase as NSString).appendingPathComponent(logName)
        if ensureWritableLogPath(preferredPath) {
            return (preferredPath, nil)
        }

        let fallbackDir = appSupportLogDirectory()
        let fallbackPath = (fallbackDir as NSString).appendingPathComponent(logName)
        if ensureWritableLogPath(fallbackPath) {
            return (
                fallbackPath,
                "Log file could not be created at the destination. Using the app log folder instead."
            )
        }

        return (nil, "Log file could not be created. Continuing without a log file.")
    }

    /// Write a per-destination log for the fan-out engine. The single-transfer path
    /// (`runSingleTransfer`) writes its own log; the fan-out path did not, so logs
    /// never got created for the (only) FilmCan Engine. Mirrors that behavior:
    /// resolve the log path (same-as-destination or custom folder template) and
    /// write it, recording the path / any warning back onto each result.
    private func writeFanOutLogs(
        config: BackupConfiguration,
        sources: [String],
        results: inout [TransferResult],
        preset: OrganizationPreset?
    ) {
        guard config.logEnabled else { return }
        let engine = config.rsyncOptions.copyEngine
        let customDate = preset?.useCustomDate == true ? preset?.customDate : nil
        for index in results.indices {
            let destination = results[index].destination
            let resolution = resolvedLogFilePath(
                logEnabled: true,
                logLocation: config.logLocation,
                customLogPath: config.customLogPath,
                logFileNameTemplate: config.logFileNameTemplate,
                configName: config.name,
                destination: destination,
                sources: sources,
                customDate: customDate
            )
            guard let logFile = resolution.path else {
                results[index].logFilePath = nil
                if let warning = resolution.warning {
                    results[index].warningMessage = mergeWarning(results[index].warningMessage, warning)
                }
                continue
            }
            // Derive the transferred-file list from the destination's sealed hash
            // list (MHL). Available only when verification wrote one (Fast/Paranoid);
            // in Off mode there is no MHL, so the log lists status + counts only.
            if results[index].transferredPaths.isEmpty,
               let mhl = results[index].hashListPath, !mhl.isEmpty,
               let entries = try? MHLReader.read(url: URL(fileURLWithPath: mhl)) {
                results[index].transferredPaths = entries.map { $0.fileName }
            }
            if let writeWarning = writeCustomLog(
                result: results[index],
                logFile: logFile,
                sources: sources,
                destination: destination,
                engine: engine
            ) {
                results[index].logFilePath = nil
                results[index].warningMessage = mergeWarning(results[index].warningMessage, writeWarning)
            } else {
                results[index].logFilePath = logFile
                if let warning = resolution.warning {
                    results[index].warningMessage = mergeWarning(results[index].warningMessage, warning)
                }
            }
        }
    }

    private func mergeWarning(_ existing: String?, _ new: String) -> String {
        guard let existing, !existing.isEmpty else { return new }
        return existing.contains(new) ? existing : "\(existing)\n\(new)"
    }

    private func writeCustomLog(
        result: TransferResult,
        logFile: String,
        sources: [String],
        destination: String,
        engine: CopyEngine
    ) -> String? {
        let start = result.startTime
        let end = result.endTime ?? Date()
        let duration = FilmCanFormatters.durationCompact(end.timeIntervalSince(start))
        let status = result.success ? "SUCCESS" : "FAILED"
        let bytes = FilmCanFormatters.bytes(result.bytesTransferred, style: .file)
        let totalBytes = FilmCanFormatters.bytes(result.totalBytes, style: .file)
        let filesTransferred = result.filesTransferred
        let filesSkipped = result.filesSkipped
        let sourcesList = sources.map { "- \($0)" }.joined(separator: "\n")
        let transferredList = result.transferredPaths.isEmpty
            ? "  (none)"
            : result.transferredPaths.map { "  \($0)" }.joined(separator: "\n")

        var lines: [String] = []
        lines.append("FilmCan Copy Log")
        lines.append("Backup: \(result.configurationName)")
        lines.append("Engine: \(engine.displayName)")
        lines.append("Status: \(status)")
        if let message = result.errorMessage, !message.isEmpty {
            lines.append("Error: \(message)")
        }
        if let warning = result.warningMessage, !warning.isEmpty {
            lines.append("Warning: \(warning)")
        }
        lines.append("Start: \(start)")
        lines.append("End: \(end)")
        lines.append("Duration: \(duration)")
        lines.append("Destination: \(destination)")
        lines.append("Sources:\n\(sourcesList)")
        lines.append("Bytes: \(bytes) of \(totalBytes)")
        lines.append("Files: \(filesTransferred) transferred, \(filesSkipped) skipped")
        lines.append("")
        lines.append("Transferred items:")
        lines.append(transferredList)
        lines.append("")

        if !result.errors.isEmpty {
            lines.append("Verification issues:")
            lines.append(result.errors.map { "  \($0)" }.joined(separator: "\n"))
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        do {
            try content.write(toFile: logFile, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Log file could not be written at \(logFile). Transfer completed without a log file."
        }
    }

    private func appSupportLogDirectory() -> String {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let base else { return NSTemporaryDirectory() }
        let dir = base.appendingPathComponent("FilmCan/logs", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.path
    }

    private func ensureWritableLogPath(_ path: String) -> Bool {
        let dir = (path as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            do {
                try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            } catch {
                return false
            }
        }

        if !fm.fileExists(atPath: path) {
            let created = fm.createFile(atPath: path, contents: nil)
            if !created { return false }
        }

        if !fm.isWritableFile(atPath: path) {
            return false
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            try? handle.close()
            return true
        }
        return false
    }

    private func generateHashList(
        result: TransferResult,
        sources: [String],
        destination: String,
        algorithm: FilmCanHashAlgorithm
    ) async -> (String, [String])? {
        let roots = hashRoots(result: result, sources: sources, destination: destination)
        let hasTransfers = !result.transferredPaths.isEmpty
        if !hasTransfers && result.usedItemizedOutput {
            return nil
        }
        if !hasTransfers && roots.isEmpty {
            return nil
        }
        let fileName = HashListNamer.makeFileName(
            configName: result.configurationName,
            destination: destination,
            sources: sources,
            algorithm: algorithm
        )
        let outputDir = FilmCanPaths.hashListPath(for: destination)
        let outputPath = (outputDir as NSString).appendingPathComponent(fileName)
        let created = await Task.detached(priority: .utility) {
            if hasTransfers {
                return HashListBuilder.generateHashList(
                    files: result.transferredPaths,
                    outputPath: outputPath,
                    useAbsolutePaths: true,
                    algorithm: algorithm
                )?.outputPath
            }
            return HashListBuilder.generateHashList(
                roots: roots,
                outputPath: outputPath,
                useAbsolutePaths: true,
                algorithm: algorithm
            )?.outputPath
        }.value
        guard let path = created else { return nil }
        return (path, hasTransfers ? [] : roots)
    }

    private func hashRoots(result: TransferResult, sources: [String], destination: String) -> [String] {
        var roots: [String] = []
        for source in sources {
            if let root = result.organizationRoots[source], !roots.contains(root) {
                roots.append(root)
            }
        }
        if roots.isEmpty {
            roots = [destination]
        }
        return roots
    }

    private func recordOrganizationReuseIfNeeded(
        result: TransferResult,
        destination: String,
        configId: UUID,
        preset: OrganizationPreset?
    ) {
        guard result.success, let preset, !result.organizationRoots.isEmpty else { return }
        let storage = AppState.shared.storage
        guard var updated = storage.configurations.first(where: { $0.id == configId }) else { return }
        var info = updated.organizationReuseByDestination[destination]
        if info?.presetId != preset.id {
            info = OrganizationReuseInfo(presetId: preset.id, sourceRoots: [:])
        }
        if info == nil {
            info = OrganizationReuseInfo(presetId: preset.id, sourceRoots: [:])
        }
        for (source, root) in result.organizationRoots {
            info?.sourceRoots[source] = root
        }
        updated.organizationReuseByDestination[destination] = info
        storage.update(updated)
    }

    private func recordHistory(
        config: BackupConfiguration,
        sources: [String],
        results: [TransferResult],
        preset: OrganizationPreset?
    ) async {
        guard !results.isEmpty else { return }
        let storage = AppState.shared.storage
        let start = results.map { $0.startTime }.min() ?? (transferStartTime ?? Date())
        let end = results.compactMap { $0.endTime }.max() ?? Date()
        let success = results.allSatisfy { $0.success }
        let presetName = preset?.name
        let backupHashPath: String? = nil
        let backupHashRoots: [String] = []
        var recordedResults = results
        for index in recordedResults.indices {
            if recordedResults[index].visibleFilesTransferred != nil
                && recordedResults[index].visibleFilesSkipped != nil {
                continue
            }
            if let logFile = recordedResults[index].logFilePath {
                let rootsForLog = hashRoots(
                    result: recordedResults[index],
                    sources: sources,
                    destination: recordedResults[index].destination
                )
                let parsed = transferredPathsFromLog(
                    logFile: logFile,
                    roots: rootsForLog,
                    fallbackRoot: recordedResults[index].destination
                )
                if parsed.sawItemize {
                    recordedResults[index].transferredPaths = parsed.paths
                    recordedResults[index].usedItemizedOutput = true
                }
            }
            if recordedResults[index].success, !recordedResults[index].transferredPaths.isEmpty {
                let visibleTransferred = visibleTransferredCount(from: recordedResults[index].transferredPaths)
                let visibleTotal = await countVisibleFiles(sources: sources)
                recordedResults[index].visibleFilesTransferred = visibleTransferred
                recordedResults[index].visibleFilesSkipped = max(0, visibleTotal - visibleTransferred)
            }
        }
        let entry = TransferHistoryEntry(
            configId: config.id,
            configName: config.name,
            startedAt: start,
            endedAt: end,
            success: success,
            sources: sources,
            destinations: config.destinationPaths,
            results: recordedResults.map { TransferResultRecord(from: $0) },
            options: TransferOptionsSnapshot(config: config, presetName: presetName),
            hashListPath: backupHashPath,
            hashRoots: backupHashRoots
        )
        storage.appendHistory(entry, retentionLimit: historyRetentionLimit)
    }

    private func generateBackupHashList(
        config: BackupConfiguration,
        sources: [String],
        results: [TransferResult]
    ) async -> (path: String, roots: [String])? {
        let transferredFiles = results.flatMap { $0.transferredPaths }
        if transferredFiles.isEmpty && results.contains(where: { $0.usedItemizedOutput }) {
            return nil
        }
        var roots: [String] = []
        for result in results {
            for source in sources {
                if let root = result.organizationRoots[source], !roots.contains(root) {
                    roots.append(root)
                }
            }
            if roots.isEmpty {
                if !roots.contains(result.destination) {
                    roots.append(result.destination)
                }
            }
        }
        guard !roots.isEmpty || !transferredFiles.isEmpty else { return nil }
        let fileName = HashListNamer.makeFileName(
            configName: config.name,
            destination: "AllDestinations",
            sources: sources,
            algorithm: .xxh128
        )
        let baseDir = config.destinationPaths.first ?? FileManager.default.homeDirectoryForCurrentUser.path
        let outputDir = FilmCanPaths.hashListPath(for: baseDir)
        let outputPath = (outputDir as NSString).appendingPathComponent(fileName)
        let task = Task.detached(priority: .utility) {
            if !transferredFiles.isEmpty {
                return HashListBuilder.generateHashList(
                    files: transferredFiles,
                    outputPath: outputPath,
                    useAbsolutePaths: true,
                    algorithm: .xxh128
                )?.outputPath
            }
            return HashListBuilder.generateHashList(
                roots: roots,
                outputPath: outputPath,
                useAbsolutePaths: true,
                algorithm: .xxh128
            )?.outputPath
        }
        let created = await task.value
        guard let path = created else { return nil }
        return (path, transferredFiles.isEmpty ? roots : [])
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
        let siblingRoot = sibling.destinationPath
        let failedRoot = failed.destinationPath

        let entries: [MHLReader.Entry]
        do {
            entries = try MHLReader.read(url: mhlURL)
        } catch {
            return []
        }

        let source = SiblingDestSource()
        var results: [(fileName: String, success: Bool)] = []
        for entry in entries {
            let siblingFilePath = (siblingRoot as NSString).appendingPathComponent(entry.fileName)
            let failedFilePath = (failedRoot as NSString).appendingPathComponent(entry.fileName)
            do {
                try await source.copyFromSibling(
                    fileName: entry.fileName,
                    from: siblingFilePath,
                    to: failedFilePath,
                    expectedHash: entry.hash
                )
                results.append((entry.fileName, true))
            } catch {
                results.append((entry.fileName, false))
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
            let service = CustomCopierService()
            let recovered: TransferResult
            do {
                recovered = try await service.runCopyFanOut(
                    sources: sources,
                    fanOutDestinations: [destCfg],
                    configName: "repair",
                    organizationPreset: nil,
                    copyFolderContents: false,
                    useHashListPrecheck: false,
                    hashListPath: nil,
                    fileOrdering: .defaultOrder,
                    duplicatePolicy: .ask,
                    duplicateCounterTemplate: "",
                    duplicateResolver: nil,
                    verifyMode: failed.verifyMode,
                    dryRun: false,
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
