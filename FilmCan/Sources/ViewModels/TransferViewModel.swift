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
    @Published var verifiedDestinationsByConfig: [UUID: Set<String>] = [:]
    @Published var destinationProgress: [String: Double] = [:]
    @Published var pathProgress: [String: Double] = [:]
    @Published var driveCapacitySnapshot: [String: DriveCapacitySnapshot] = [:]

    struct DriveCapacitySnapshot {
        let totalBytes: Int64?
        let availableBytes: Int64?
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

    private struct PendingDuplicatePrompt {
        let prompt: DuplicatePrompt
        let continuation: CheckedContinuation<DuplicateResolution, Never>
    }
    
    init() {
        bindProgress(to: rsyncService)
    }
    
    func startTransfer(config: BackupConfiguration) async {
        let activeConfig = AppState.shared.storage.configurations
            .first(where: { $0.id == config.id }) ?? config
        self.config = activeConfig
        activeConfigId = activeConfig.id
        captureDriveSnapshot(paths: activeConfig.sourcePaths + activeConfig.destinationPaths)
        verifiedDestinationsByConfig.removeValue(forKey: activeConfig.id)
        transferStartTime = Date()
        // Reset progress before starting new transfer
        progress.resetProgress()
        isTransferring = true
        results = []
        destinationProgress.removeAll()
        pathProgress.removeAll()
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
        
        for source in sources {
            if isCancellingAll || isPausingAll { break }
            currentDestinationIndex = 0
            let sourceList = [source]
            currentSources = sourceList
            let sourceResults: [TransferResult]
            if activeConfig.runInParallel {
                sourceResults = await runParallel(
                    destinations: destinations,
                    sources: sourceList,
                    config: activeConfig,
                    organizationPreset: organizationPreset
                )
            } else {
                sourceResults = await runSequential(
                    destinations: destinations,
                    sources: sourceList,
                    config: activeConfig,
                    organizationPreset: organizationPreset
                )
            }
            if duplicatePromptCancelled {
                isTransferring = false
                driveCapacitySnapshot.removeAll()
                currentService = nil
                resetDuplicatePromptState()
                clearLastRun(for: activeConfig.id)
                return
            }
            await recordHistory(
                config: activeConfig,
                sources: sourceList,
                results: sourceResults,
                preset: organizationPreset
            )
            await sendSourceNotifications(
                source: source,
                config: activeConfig,
                results: sourceResults
            )
        }
        
        isTransferring = false
        driveCapacitySnapshot.removeAll()
        currentService = nil
    }

    func clearLastRun(for configId: UUID?) {
        guard !isTransferring else { return }
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
        driveCapacitySnapshot.removeAll()
        clearProgressObservers()
        progressBinding?.cancel()
        currentService = nil
        if let targetId {
            verifiedDestinationsByConfig.removeValue(forKey: targetId)
        }
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

    func progressForPath(destination: String, source: String) -> Double {
        let key = progressKey(destination: destination, source: source)
        return pathProgress[key] ?? 0
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
                    self?.progress = value
                }
        } else if let custom = service as? CustomCopierService {
            progressBinding = custom.$progress
                .receive(on: DispatchQueue.main)
                .sink { [weak self] value in
                    self?.progress = value
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
        let key = progressKey(destination: destination, source: source)
        pathProgress[key] = 0
        destinationProgressCancellables[destination] = service.progress.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let value = service.progress.overallProgress
                self.destinationProgress[destination] = value
                self.pathProgress[key] = value
            }
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
        }
    }

    private struct DestinationNotificationSummary {
        let title: String
        let body: String
        let messageTitle: String
        let messageBody: String
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
        let messageTitle = titleTemplate.isEmpty
            ? title
            : applyTemplate(
                titleTemplate,
                replacements: [
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
            )

        let messageBody = template.isEmpty
            ? body
            : applyTemplate(
                template,
                replacements: [
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
            )

        return DestinationNotificationSummary(
            title: title,
            body: body,
            messageTitle: messageTitle,
            messageBody: messageBody,
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
    
    private func runSequential(
        destinations: [String],
        sources: [String],
        config: BackupConfiguration,
        organizationPreset: OrganizationPreset?
    ) async -> [TransferResult] {
        var sourceResults: [TransferResult] = []
        for (index, dest) in destinations.enumerated() {
            if isCancellingAll || isPausingAll { break }

            if cancelledDestinations.contains(dest) {
                let now = Date()
                let skipped = TransferResult(
                    configurationName: config.name,
                    destination: dest,
                    startTime: now,
                    endTime: now,
                    success: false,
                    errorMessage: "Cancelled by user"
                )
                results.append(skipped)
                sourceResults.append(skipped)
                if let source = sources.first {
                    let key = progressKey(destination: dest, source: source)
                    pathProgress[key] = 0
                }
                continue
            }
            
            // Reset the per-destination cancel flag before each transfer
            shouldCancelCurrentOnly = false
            currentDestinationIndex = index
            currentSources = sources
            currentDestination = dest
            if let source = sources.first {
                let key = progressKey(destination: dest, source: source)
                pathProgress[key] = 0
            }
            
            let result = await runSingleTransfer(
                sources: sources,
                destination: dest,
                options: config.rsyncOptions,
                configName: config.name,
                logFileNameTemplate: config.logFileNameTemplate,
                copyFolderContents: config.copyFolderContents,
                duplicatePolicy: config.duplicatePolicy,
                duplicateCounterTemplate: config.duplicateCounterTemplate,
                logEnabled: config.logEnabled,
                logLocation: config.logLocation,
                customLogPath: config.customLogPath,
                organizationPreset: organizationPreset,
                reuseInfo: config.organizationReuseByDestination[dest]
            )
            if duplicatePromptCancelled {
                results.removeAll()
                sourceResults.removeAll()
                break
            }
            results.append(result)
            sourceResults.append(result)
            if let source = sources.first {
                let key = progressKey(destination: dest, source: source)
                if result.success {
                    destinationProgress[dest] = 1.0
                    pathProgress[key] = 1.0
                }
            }

            // Next destination state handled after cleanup

            recordOrganizationReuseIfNeeded(
                result: result,
                destination: dest,
                configId: config.id,
                preset: organizationPreset
            )
            
            // If "cancel current only" was triggered during the transfer, the result
            // is already recorded as cancelled — continue to next destination.
            // If cancel all was requested mid-transfer, stop here.
            if isCancellingAll || isPausingAll { break }

            let nextIndex = index + 1
            if nextIndex < destinations.count {
                let nextDest = destinations[nextIndex]
                if !cancelledDestinations.contains(nextDest) {
                    currentDestinationIndex = nextIndex
                    currentDestination = nextDest
                }
            }
        }
        return sourceResults
    }
    
    private func runParallel(
        destinations: [String],
        sources: [String],
        config: BackupConfiguration,
        organizationPreset: OrganizationPreset?
    ) async -> [TransferResult] {
        activeServices = []
        var sourceResults: [TransferResult] = []
        await withTaskGroup(of: TransferResult.self) { group in
            for dest in destinations {
                currentSources = sources
                currentDestination = dest
                // Each parallel transfer gets its own service so progress state doesn't collide
                let service: TransferService = config.rsyncOptions.copyEngine == .custom
                    ? CustomCopierService()
                    : RsyncService()
                activeServices.append(service)
                let reuseInfo = config.organizationReuseByDestination[dest]
                group.addTask {
                    await self.runSingleTransfer(
                        sources: sources,
                        destination: dest,
                        options: config.rsyncOptions,
                        configName: config.name,
                        logFileNameTemplate: config.logFileNameTemplate,
                        copyFolderContents: config.copyFolderContents,
                        duplicatePolicy: config.duplicatePolicy,
                        duplicateCounterTemplate: config.duplicateCounterTemplate,
                        logEnabled: config.logEnabled,
                        logLocation: config.logLocation,
                        customLogPath: config.customLogPath,
                        organizationPreset: organizationPreset,
                        reuseInfo: reuseInfo,
                        service: service
                    )
                }
                if let source = sources.first {
                    trackProgress(service: service, destination: dest, source: source)
                }
            }
            
            for await result in group {
                if duplicatePromptCancelled { continue }
                results.append(result)
                sourceResults.append(result)
                if let source = sources.first {
                    let key = progressKey(destination: result.destination, source: source)
                    if result.success {
                        destinationProgress[result.destination] = 1.0
                        pathProgress[key] = 1.0
                    }
                }
                recordOrganizationReuseIfNeeded(
                    result: result,
                    destination: result.destination,
                    configId: config.id,
                    preset: organizationPreset
                )
            }
        }
        activeServices = []
        if duplicatePromptCancelled {
            results.removeAll()
            sourceResults.removeAll()
        }
        return sourceResults
    }

    func cancelRunFromDuplicatePrompt() {
        duplicatePromptCancelled = true
        cancelAll()
        submitDuplicateResolution(action: .skip, applyToAll: true, counterTemplate: nil)
    }
    
    private func runSingleTransfer(
        sources: [String],
        destination: String,
        options: RsyncOptions,
        configName: String,
        logFileNameTemplate: String,
        copyFolderContents: Bool,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        duplicateCounterTemplate: String,
        logEnabled: Bool,
        logLocation: BackupConfiguration.LogLocation,
        customLogPath: String,
        organizationPreset: OrganizationPreset?,
        reuseInfo: OrganizationReuseInfo?,
        service: TransferService? = nil
    ) async -> TransferResult {
        let activeService: TransferService
        if let service {
            activeService = service
        } else if options.copyEngine == .custom {
            activeService = CustomCopierService()
        } else {
            activeService = rsyncService
        }
        currentService = activeService
        if !isParallelRun {
            activeServices = [activeService]
            if let source = sources.first {
                trackProgress(service: activeService, destination: destination, source: source)
            }
            bindProgress(to: activeService)
        }
        activeService.resetProgress()

        var normalizedOptions = options
        normalizedOptions.reuseOrganizedFiles = false
        
        var effectiveLogFile: String? = nil
        var logWarning: String? = nil
        let shouldUseLogs = logEnabled
        if shouldUseLogs {
            let logResolution = resolvedLogFilePath(
                logEnabled: true,
                logLocation: logLocation,
                customLogPath: customLogPath,
                logFileNameTemplate: logFileNameTemplate,
                configName: configName,
                destination: destination,
                sources: sources,
                customDate: organizationPreset?.useCustomDate == true ? organizationPreset?.customDate : nil
            )
            effectiveLogFile = logResolution.path
            logWarning = logResolution.warning
        }
        
        let duplicateResolver: (@Sendable (DuplicatePrompt) async -> DuplicateResolution)?
        if duplicatePolicy == .ask || duplicatePolicy == .verify {
            duplicateResolver = { [weak self] prompt async -> DuplicateResolution in
                guard let self = self else {
                    return DuplicateResolution(action: .skip, applyToAll: false, counterTemplate: nil)
                }
                return await self.resolveDuplicate(prompt: prompt)
            }
        } else {
            duplicateResolver = nil
        }

        func shouldRetryWithoutLog(_ result: TransferResult, logFile: String?) -> Bool {
            guard let logFile, !logFile.isEmpty else { return false }
            guard result.success == false else { return false }
            let lower = (result.errorMessage ?? "").lowercased()
            let isLogError = lower.contains("log file") || lower.contains("logfile") || lower.contains("append to log")
            let noBytes = result.bytesTransferred == 0
            let noFiles = (result.filesTransferred == 0)
            return isLogError && noBytes && noFiles
        }

        func mergedWarning(_ existing: String?, _ extra: String) -> String {
            if let existing, !existing.isEmpty {
                return existing + " " + extra
            }
            return extra
        }

        do {
            var result: TransferResult
            let fileManager = FileManager.default
            if let rsync = activeService as? RsyncService {
                let fileName = HashListNamer.makeFileName(
                    configName: configName,
                    destination: destination,
                    sources: sources,
                    algorithm: .xxh128
                )
                let outputDir = FilmCanPaths.hashListPath(for: destination)
                let rsyncHashListPath = (outputDir as NSString).appendingPathComponent(fileName)
                result = try await rsync.runRsync(
                    sources: sources,
                    destination: destination,
                    options: normalizedOptions,
                    logFile: effectiveLogFile,
                    hashListPath: rsyncHashListPath,
                    organizationPreset: organizationPreset,
                    copyFolderContents: copyFolderContents,
                    duplicatePolicy: duplicatePolicy,
                    duplicateCounterTemplate: duplicateCounterTemplate,
                    reuseInfo: reuseInfo,
                    duplicateResolver: duplicateResolver
                )
                if duplicatePromptCancelled {
                    if let logFile = effectiveLogFile {
                        try? fileManager.removeItem(atPath: logFile)
                    }
                    if let hashList = result.hashListPath {
                        try? fileManager.removeItem(atPath: hashList)
                        result.hashListPath = nil
                    }
                    result.logFilePath = nil
                    result.warningMessage = nil
                    return result
                }
                if shouldRetryWithoutLog(result, logFile: effectiveLogFile) {
                    rsync.resetProgress()
                    var retry = try await rsync.runRsync(
                        sources: sources,
                        destination: destination,
                        options: normalizedOptions,
                        logFile: nil,
                        hashListPath: rsyncHashListPath,
                        organizationPreset: organizationPreset,
                        copyFolderContents: copyFolderContents,
                        duplicatePolicy: duplicatePolicy,
                        duplicateCounterTemplate: duplicateCounterTemplate,
                        reuseInfo: reuseInfo,
                        duplicateResolver: duplicateResolver
                    )
                    let logPathHint = effectiveLogFile ?? "the chosen log location"
                    retry.warningMessage = mergedWarning(
                        logWarning,
                        "Log file could not be written at \(logPathHint). Transfer continued without a log file."
                    )
                    retry.configurationName = configName
                    retry.logFilePath = nil
                    effectiveLogFile = nil
                    result = retry
                } else {
                    result.configurationName = configName
                    result.logFilePath = effectiveLogFile
                    if let logWarning {
                        result.warningMessage = mergedWarning(result.warningMessage, logWarning)
                    }
                }
                let rootsForLog = hashRoots(result: result, sources: sources, destination: destination)
                if let logFile = effectiveLogFile {
                    let parsed = transferredPathsFromLog(
                        logFile: logFile,
                        roots: rootsForLog,
                        fallbackRoot: destination
                    )
                    if parsed.sawItemize {
                        result.transferredPaths = parsed.paths
                        result.usedItemizedOutput = true
                    }
                }
            } else if let custom = activeService as? CustomCopierService {
                let fileName = HashListNamer.makeFileName(
                    configName: configName,
                    destination: destination,
                    sources: sources,
                    algorithm: .xxh128
                )
                let outputDir = FilmCanPaths.hashListPath(for: destination)
                let customHashListPath = (outputDir as NSString).appendingPathComponent(fileName)
                result = try await custom.runCopy(
                    sources: sources,
                    destination: destination,
                    configName: configName,
                    organizationPreset: organizationPreset,
                    copyFolderContents: copyFolderContents,
                    useHashListPrecheck: options.useHashListPrecheck,
                    hashListPath: customHashListPath,
                    fileOrdering: options.fileOrdering,
                    parallelCopyEnabled: options.parallelCopyEnabled,
                    duplicatePolicy: duplicatePolicy,
                    duplicateCounterTemplate: duplicateCounterTemplate,
                    duplicateResolver: duplicateResolver
                )
                if duplicatePromptCancelled {
                    if let logFile = effectiveLogFile {
                        try? fileManager.removeItem(atPath: logFile)
                    }
                    if let hashList = result.hashListPath {
                        try? fileManager.removeItem(atPath: hashList)
                        result.hashListPath = nil
                    }
                    result.logFilePath = nil
                    result.warningMessage = nil
                    return result
                }
                result.configurationName = configName
                if let logFile = effectiveLogFile, shouldUseLogs {
                    if let writeWarning = writeCustomLog(
                        result: result,
                        logFile: logFile,
                        sources: sources,
                        destination: destination,
                        engine: options.copyEngine
                    ) {
                        result.warningMessage = mergedWarning(result.warningMessage, writeWarning)
                        if let logWarning {
                            result.warningMessage = mergedWarning(result.warningMessage, logWarning)
                        }
                        result.logFilePath = nil
                    } else {
                        if let logWarning {
                            result.warningMessage = mergedWarning(result.warningMessage, logWarning)
                        }
                        result.logFilePath = logFile
                    }
                } else {
                    result.logFilePath = nil
                    if let logWarning {
                        result.warningMessage = mergedWarning(result.warningMessage, logWarning)
                    }
                }
            } else {
                result = TransferResult(
                    configurationName: configName,
                    destination: destination,
                    startTime: Date(),
                    endTime: Date(),
                    success: false,
                    errorMessage: "Unsupported transfer service.",
                    warningMessage: logWarning,
                    logFilePath: effectiveLogFile
                )
            }
            if result.success, !result.transferredPaths.isEmpty {
                let visibleTransferred = visibleTransferredCount(from: result.transferredPaths)
                let visibleTotal = await countVisibleFiles(sources: sources)
                result.visibleFilesTransferred = visibleTransferred
                result.visibleFilesSkipped = max(0, visibleTotal - visibleTransferred)
            }
            if result.success && result.hashListPath == nil {
                await MainActor.run {
                    self.progress.verificationPhase = .generatingHashList
                }
                if let (hashPath, roots) = await generateHashList(
                    result: result,
                    sources: sources,
                    destination: destination,
                    algorithm: .xxh128
                ) {
                    result.hashListPath = hashPath
                    result.hashRoots = roots
                }
                await MainActor.run {
                    self.progress.verificationPhase = .complete
                }
            }
            return result
        } catch {
            return TransferResult(
                configurationName: configName,
                destination: destination,
                startTime: Date(),
                endTime: Date(),
                success: false,
                errorMessage: error.localizedDescription,
                warningMessage: logWarning,
                logFilePath: effectiveLogFile
            )
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
        shouldCancelCurrentOnly = true
        currentService?.cancel()
    }
    
    func cancelAll() {
        isCancellingAll = true
        shouldCancelCurrentOnly = true
        if isParallelRun {
            activeServices.forEach { $0.cancel() }
        } else {
            currentService?.cancel()
        }
    }
}
