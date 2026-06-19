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
