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
        cancellationState.update(isCancelled: false)
    }

    func cancel() {
        isCancelled = true
        progress.isCancelled = true
        progress.isRunning = false
        cancellationState.update(isCancelled: true)
    }

    func pause() {
        isPaused = true
        progress.isPaused = true
        progress.isRunning = false
    }


    /// Fan-out copy: copies sources to multiple destinations in parallel
    func runCopyFanOut(
        sources: [String],
        fanOutDestinations: [DestWriter.Config],
        configName: String,
        organizationPreset: OrganizationPreset?,
        copyFolderContents: Bool,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        duplicateCounterTemplate: String,
        duplicateResolver: (@Sendable (DuplicatePrompt) async -> DuplicateResolution)?,
        verifyMode: VerifyMode,
        dryRun: Bool,
        forceRecopy: Bool = false,
        shootMetadata: ShootMetadata = .empty,
        sourceMediaKinds: [String: SourceMediaKind] = [:],
        rollNames: [String: String] = [:],
        hashListStyle: HashListStyle = .ascMHL,
        reVerifyExistingOnResume: Bool = false,
        unreadableHandler: (@Sendable ([String]) async -> Bool)? = nil,
        rollIdentityHandler: (@Sendable (FanOutCopier.RollIdentityQuery) async -> Bool)? = nil,
        progressHandler: (@Sendable ([DestProgress]) -> Void)?
    ) async throws -> TransferResult {
        let startTime = Date()

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
            mhlBasePath: nil,
            dryRun: dryRun,
            progressHandler: { [accumulator] prog in
                Task { await accumulator.update(prog) }
            },
            organizationPreset: organizationPreset,
            copyFolderContents: copyFolderContents,
            shootMetadata: shootMetadata,
            sourceMediaKinds: sourceMediaKinds,
            rollNames: rollNames,
            hashListStyle: hashListStyle,
            forceRecopy: forceRecopy,
            shouldCancel: { cancellationState.isCancelledNow() },
            reVerifyExistingOnResume: reVerifyExistingOnResume
        )

        fanOutConfig.duplicatePolicy = duplicatePolicy
        fanOutConfig.duplicateCounterTemplate = duplicateCounterTemplate
        fanOutConfig.unreadableHandler = unreadableHandler
        fanOutConfig.rollIdentityHandler = rollIdentityHandler
        if let duplicateResolver {
            fanOutConfig.duplicateResolver = { @Sendable conflicts in
                await CustomCopierService.resolveConflicts(conflicts, counterTemplate: duplicateCounterTemplate,
                                            ask: duplicateResolver)
            }
        }

        let copier = FanOutCopier(config: fanOutConfig)
        let destResults = try await copier.run()

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
        result.runPlan = await copier.runPlan
        return result
    }

}

extension CustomCopierService {
    /// Asks about each conflict in turn. Every prompt carries the full list, so the
    /// user sees how many files are concerned before choosing. "Apply to all" answers
    /// the current file and every remaining one; otherwise the next file is asked.
    nonisolated static func resolveConflicts(
        _ conflicts: [ConflictScanner.Conflict],
        counterTemplate: String,
        ask: @Sendable (DuplicatePrompt) async -> DuplicateResolution
    ) async -> [String: FanOutCopier.ConflictDecision] {
        let names = conflicts.map(\.resolvedPath)
        var decisions: [String: FanOutCopier.ConflictDecision] = [:]
        var index = 0
        while index < conflicts.count {
            let c = conflicts[index]
            let prompt = DuplicatePrompt(
                sourcePath: c.fileName,
                destinationPath: c.resolvedPath,
                isDirectory: false,
                counterTemplate: counterTemplate,
                canVerifyWithHashList: false,
                hashListMissing: false,
                conflictCount: conflicts.count,
                conflictNames: names,
                position: index)
            let answer = await ask(prompt)
            let decision = FanOutCopier.ConflictDecision(
                policy: answer.action, counterTemplate: answer.counterTemplate)
            let answered = answer.applyToAll ? conflicts[index...] : conflicts[index...index]
            for a in answered where decisions[a.resolvedPath] == nil {
                decisions[a.resolvedPath] = decision
            }
            index += answered.count
        }
        return decisions
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
