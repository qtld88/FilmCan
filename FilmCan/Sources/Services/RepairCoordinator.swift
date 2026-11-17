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

    /// Sibling branch: for EVERY roll of the sibling (one manifest per roll), copy each
    /// listed file from the sibling into the failed dest, hash-checked while writing and
    /// read back from disk. Seals a fresh ASC MHL generation for each roll that fully
    /// lands. The outcome is a success only when every roll was read and every file of
    /// every roll repaired.
    static func repairFromSibling(
        failed: DestResult,
        sibling: DestResult
    ) async -> SiblingRepairOutcome {
        var manifests = sibling.mhlPaths
        if manifests.isEmpty, let single = sibling.mhlPath { manifests = [single] }
        guard !manifests.isEmpty else { return SiblingRepairOutcome(perFile: []) }

        // exFAT/USB destinations (often the very drive that failed) need F_FULLFSYNC.
        let requiresFullFsync = DriveSpeedClassifier.requiresFullFsync(
            DriveSpeedClassifier.info(for: failed.destinationPath))
        let source = SiblingDestSource()
        var perFile: [(fileName: String, success: Bool)] = []
        for manifest in manifests {
            perFile += await repairRoll(manifestPath: manifest, failed: failed, sibling: sibling,
                                        source: source, requiresFullFsync: requiresFullFsync)
        }
        return SiblingRepairOutcome(perFile: perFile)
    }

    /// The roll's entries: the given manifest when it is on disk and readable, else the
    /// newest readable generation of the same `ascmhl/` folder (a run that copied nothing
    /// new to a roll writes no generation). Nil when nothing readable lists the roll.
    static func rollEntries(manifestPath: String) -> [ASCMHLReader.Entry]? {
        let url = URL(fileURLWithPath: manifestPath)
        if let entries = try? ASCMHLReader.read(url: url), !entries.isEmpty { return entries }
        for candidate in ASCMHLChain.manifestFilesNewestFirst(ascmhlDir: url.deletingLastPathComponent()) {
            if let entries = try? ASCMHLReader.read(url: candidate), !entries.isEmpty { return entries }
        }
        return nil
    }

    private static func repairRoll(
        manifestPath: String, failed: DestResult, sibling: DestResult,
        source: SiblingDestSource, requiresFullFsync: Bool
    ) async -> [(fileName: String, success: Bool)] {
        let mhlURL = URL(fileURLWithPath: manifestPath)
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

        // A roll whose list cannot be read cannot be repaired: one failed line.
        guard let entries = rollEntries(manifestPath: manifestPath) else {
            return [((relRoll.isEmpty ? mhlURL.lastPathComponent : relRoll), false)]
        }

        var perFile: [(fileName: String, success: Bool)] = []
        var copied: [MHLEntry] = []
        for entry in entries {
            let label = relRoll.isEmpty ? entry.relPath : "\(relRoll)/\(entry.relPath)"
            // Only an xxh128 checksum with a size proves the bytes we copy.
            guard entry.algorithm == nil || entry.algorithm == "xxh128" else {
                perFile.append((label, false))
                continue
            }
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
                perFile.append((label, true))
                copied.append(MHLEntry(relPath: entry.relPath, size: entry.size ?? 0,
                                       hash: entry.hash, mtime: entry.mtime))
            } catch {
                perFile.append((label, false))
            }
        }

        // Chain of custody: seal a fresh ASC MHL generation for the repaired roll so
        // it isn't left certified-but-manifestless. Only when EVERY file of the roll
        // landed and hash-verified — a partial repair must never seal a manifest.
        if !copied.isEmpty, perFile.allSatisfy({ $0.success }) {
            let ascDir = URL(fileURLWithPath: failedRoll).appendingPathComponent("ascmhl")
            let rollName = (failedRoll as NSString).lastPathComponent
            if let writer = try? ASCMHLWriter(ascmhlDir: ascDir, rollName: rollName) {
                // Each file was hash-checked by this repair: fresh entries, not carried.
                for e in copied {
                    try? await writer.append(relPath: e.relPath, size: e.size, hash: e.hash, mtime: e.mtime)
                }
                try? await writer.seal()
            }
        }
        return perFile
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
        hashListStyle: HashListStyle,
        rollNames: [String: String] = [:],
        shootMetadata: ShootMetadata = .empty
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
                duplicatePolicy: duplicatePolicy,
                duplicateCounterTemplate: "",
                duplicateResolver: nil,
                verifyMode: failed.verifyMode,
                dryRun: false,
                shootMetadata: shootMetadata,
                sourceMediaKinds: sourceMediaKinds,
                rollNames: rollNames,
                hashListStyle: hashListStyle,
                progressHandler: nil
            )
            return SourceRepairOutcome(recovered: recovered)
        } catch {
            return SourceRepairOutcome(recovered: nil)
        }
    }
}
