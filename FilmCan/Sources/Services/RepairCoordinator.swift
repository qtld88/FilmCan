import Foundation

/// Outcome of a sibling-repair run: per-file results + count for the patch call.
struct SiblingRepairOutcome {
    let perFile: [(fileName: String, success: Bool)]
    var allOK: Bool { !perFile.isEmpty && perFile.allSatisfy { $0.success } }
    var fileCount: Int { perFile.count }
}

/// Outcome of a source-repair run.
struct SourceRepairOutcome {
    let recovered: TransferResult?
    var allOK: Bool { recovered?.destinationResults.allSatisfy { $0.success } ?? false }
    var filesTransferred: Int { recovered?.filesTransferred ?? 0 }
}

/// Performs the copy/verify work for failed-destination repair without touching
/// any @Published VM state. The VM calls these methods, receives the outcome,
/// then applies it to `results` / `patchDestResultToSuccess` itself.
enum RepairCoordinator {

    /// Sibling branch: read the sibling's MHL manifest and copy every listed file
    /// from the sibling dest into the failed dest, verifying each hash. Seals a
    /// fresh ASC MHL generation for the repaired dest when every file lands.
    static func repairFromSibling(
        failed: DestResult,
        sibling: DestResult
    ) async -> SiblingRepairOutcome {
        guard let siblingMHL = sibling.mhlPath else { return SiblingRepairOutcome(perFile: []) }
        let mhlURL = URL(fileURLWithPath: siblingMHL)

        let entries: [ASCMHLReader.Entry]
        do {
            entries = try ASCMHLReader.read(url: mhlURL)
        } catch {
            return SiblingRepairOutcome(perFile: [])
        }
        guard !entries.isEmpty else { return SiblingRepairOutcome(perFile: []) }

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
        var perFile: [(fileName: String, success: Bool)] = []
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
                perFile.append((entry.relPath, true))
                copied.append(MHLEntry(relPath: entry.relPath, size: entry.size ?? 0,
                                       hash: entry.hash, mtime: entry.mtime))
            } catch {
                perFile.append((entry.relPath, false))
            }
        }

        // Chain of custody: seal a fresh ASC MHL generation for the repaired
        // destination so it isn't left certified-but-manifestless (its prior run
        // wrote only a partial, un-chained generation). Only when EVERY file landed
        // and hash-verified — a partial repair must never seal a manifest.
        if !copied.isEmpty, perFile.allSatisfy({ $0.success }) {
            let ascDir = URL(fileURLWithPath: failedRoll).appendingPathComponent("ascmhl")
            let rollName = (failedRoll as NSString).lastPathComponent
            if let writer = try? ASCMHLWriter(ascmhlDir: ascDir, rollName: rollName) {
                await writer.seed(copied)
                try? await writer.seal()
            }
        }
        return SiblingRepairOutcome(perFile: perFile)
    }

    /// Source branch: re-copy the original sources into the failed dest using the
    /// fan-out engine. Returns the recovered TransferResult on success, nil on error.
    @MainActor
    static func repairFromSource(
        failed: DestResult,
        sources: [String],
        organizationPreset: OrganizationPreset?,
        copyFolderContents: Bool,
        duplicatePolicy: OrganizationPreset.DuplicatePolicy,
        sourceMediaKinds: [String: SourceMediaKind],
        hashListStyle: HashListStyle
    ) async -> SourceRepairOutcome {
        // Sanity check: every source path must still exist on disk before we attempt re-copy.
        let fm = FileManager.default
        for path in sources {
            if !fm.fileExists(atPath: path) { return SourceRepairOutcome(recovered: nil) }
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
        do {
            let recovered = try await service.runCopyFanOut(
                sources: sources,
                fanOutDestinations: [destCfg],
                configName: "repair",
                organizationPreset: organizationPreset,
                copyFolderContents: copyFolderContents,
                useHashListPrecheck: false,
                hashListPath: nil,
                fileOrdering: .defaultOrder,
                duplicatePolicy: duplicatePolicy,
                duplicateCounterTemplate: "",
                duplicateResolver: nil,
                verifyMode: failed.verifyMode,
                dryRun: false,
                sourceMediaKinds: sourceMediaKinds,
                hashListStyle: hashListStyle,
                progressHandler: nil
            )
            return SourceRepairOutcome(recovered: recovered)
        } catch {
            return SourceRepairOutcome(recovered: nil)
        }
    }
}
