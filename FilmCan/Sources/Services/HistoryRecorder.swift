import Foundation

/// Persists a completed transfer run to history.
///
/// Injected with `ConfigurationStorage` so the VM doesn't need to reach
/// into `AppState.shared` from this code path; the VM holds the instance.
/// All VM `@Published` state is passed as parameters; `record(...)` returns
/// the `RunContext` it builds so the VM can store it.
@MainActor
final class HistoryRecorder {

    private let storage: ConfigurationStorage

    init(storage: ConfigurationStorage = ConfigurationStorage.shared) {
        self.storage = storage
    }

    // MARK: - Public API

    @discardableResult
    func record(
        config: BackupConfiguration,
        sources: [String],
        results: [TransferResult],
        preset: OrganizationPreset?,
        transferStartTime: Date?,
        retentionLimit: Int
    ) async -> RunContext {
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
                let rootsForLog = Self.hashRoots(
                    result: recordedResults[index],
                    sources: sources,
                    destination: recordedResults[index].destination
                )
                let parsed = LogItemizeParser.parseTransferredPaths(
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
                let visibleTransferred = Self.visibleTransferredCount(from: recordedResults[index].transferredPaths)
                let visibleTotal = await Self.countVisibleFiles(sources: sources)
                recordedResults[index].visibleFilesTransferred = visibleTransferred
                recordedResults[index].visibleFilesSkipped = max(0, visibleTotal - visibleTransferred)
            }
        }
        var entry = TransferHistoryEntry(
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
        let ctx = RunContext(
            organizationPresetId: config.selectedOrganizationPresetId,
            cameraFolderTemplate: config.cameraFolderTemplate,
            soundFolderTemplate: config.soundFolderTemplate,
            copyFolderContents: config.copyFolderContents,
            sourceMediaKinds: config.sourceMediaKinds,
            duplicatePolicy: config.duplicatePolicy,
            hashListStyle: config.hashListStyle
        )
        entry.runContext = ctx
        storage.appendHistory(entry, retentionLimit: retentionLimit)
        return ctx
    }

    // MARK: - Static helpers (pure)

    static func hashRoots(result: TransferResult, sources: [String], destination: String) -> [String] {
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

    /// User-facing warning for a destination that copied and verified cleanly but
    /// whose ASC MHL manifest could not be sealed. Reassures that the footage is
    /// safe and points at the fix (re-run regenerates the manifest only).
    static func manifestUnsealedWarning(_ reason: String?) -> String? {
        guard let reason, !reason.isEmpty else { return nil }
        return "Files copied and verified, but the ASC MHL manifest couldn't be written "
            + "(\(reason)). Your footage is safe and hash-verified — only the "
            + "chain-of-custody manifest is incomplete. Re-run the backup for this "
            + "destination to regenerate it."
    }

    // MARK: - File-counting helpers (internal so VM can reuse for notification summaries)

    nonisolated static func visibleTransferredCount(from paths: [String]) -> Int {
        paths.reduce(0) { count, path in
            isHiddenPath(path) ? count : count + 1
        }
    }

    nonisolated static func countVisibleFiles(sources: [String]) async -> Int {
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

    nonisolated static func isHiddenPath(_ path: String) -> Bool {
        if FilmCanPaths.isHidden(path) { return true }
        let components = path.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }
}
