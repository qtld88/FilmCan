import Foundation

/// Reads and writes the on-card backup seal. Signal-only: never blocks or mutates
/// card data beyond writing its own marker under `.filmcan/`.
enum CardSealService {

    static func markerURL(for source: URL) -> URL {
        source
            .appendingPathComponent(FilmCanPaths.hidden, isDirectory: true)
            .appendingPathComponent("seal.json")
    }

    /// Entries of one source from the plan the engine copied and checked — the list
    /// the seal covers. The card is never walked again after the copy.
    static func entries(of plan: RunPlan, source: String) -> [CardSeal.Entry] {
        plan.files(inRoot: source).map {
            CardSeal.Entry(relPath: $0.relPath, size: $0.size, modified: $0.modified)
        }
    }

    /// Write a seal for a fully-verified source. Best-effort: throws only on write
    /// failure so the caller can log and continue — it must never fail a backup.
    static func seal(source: URL,
                     entries: [CardSeal.Entry],
                     preset: OrganizationPreset?,
                     destinationsVerified: [String],
                     mhlRef: String?) async throws {
        let seal = CardSeal(
            schemaVersion: CardSeal.currentSchemaVersion,
            volumeUUID: volumeUUID(for: source) ?? "",
            sealDate: Date(),
            appVersion: appVersion(),
            entries: entries.sorted { $0.relPath < $1.relPath },
            includePatterns: preset?.includePatterns ?? [],
            excludePatterns: preset?.excludePatterns ?? [],
            copyOnlyPatterns: preset?.copyOnlyPatterns ?? [],
            destinationsVerified: destinationsVerified,
            mhlRef: mhlRef
        )
        let marker = markerURL(for: source)
        try FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(seal)
        try data.write(to: marker, options: .atomic)
    }

    /// Current seal status of a source. Never throws; unreadable → `.none`.
    static func evaluate(source: URL) async -> SealState {
        guard let data = try? Data(contentsOf: markerURL(for: source)),
              let seal = try? JSONDecoder().decode(CardSeal.self, from: data),
              seal.schemaVersion == CardSeal.currentSchemaVersion
        else { return .none }

        // Reject a marker physically copied onto a different card.
        if let current = volumeUUID(for: source),
           !current.isEmpty, !seal.volumeUUID.isEmpty,
           current != seal.volumeUUID {
            return .none
        }

        // Rebuild the exact backup-time filter so enumeration matches.
        var filter = OrganizationPreset()
        filter.includePatterns = seal.includePatterns
        filter.excludePatterns = seal.excludePatterns
        filter.copyOnlyPatterns = seal.copyOnlyPatterns

        let current = await enumerate(source: source, preset: filter)
        struct Stamp: Equatable { let size: Int64; let modified: Int64 }
        let currentByRel = Dictionary(current.map { ($0.relPath, Stamp(size: $0.size, modified: $0.modified)) },
                                      uniquingKeysWith: { a, _ in a })
        let sealByRel = Dictionary(seal.entries.map { ($0.relPath, Stamp(size: $0.size, modified: $0.modified)) },
                                   uniquingKeysWith: { a, _ in a })

        var added: [String] = []
        var missing: [String] = []
        var modified: [String] = []
        for (rel, stamp) in currentByRel {
            if let old = sealByRel[rel] {
                if old != stamp { modified.append(rel) }
            } else {
                added.append(rel)
            }
        }
        for rel in sealByRel.keys where currentByRel[rel] == nil {
            missing.append(rel)
        }

        if added.isEmpty, missing.isEmpty, modified.isEmpty {
            return .sealed
        }
        return .broken(added: added.sorted(), missing: missing.sorted(), modified: modified.sorted())
    }

    /// A card is safe to seal only if the run saw the whole card and every planned
    /// destination holds a hash-compared copy of EVERY file the engine planned:
    /// checked this run (Fast or Paranoid), or already there and re-hashed or recorded
    /// by an earlier checked run. Verification Off proves nothing, so it never seals.
    /// A run that ignored unreadable items never seals either.
    static func shouldSeal(plannedDestinations: [String], results: [TransferResult],
                           plan: RunPlan?) -> Bool {
        guard let plan, plan.ignoredUnreadable.isEmpty,
              !plan.files.isEmpty, !plannedDestinations.isEmpty else { return false }
        return Set(plannedDestinations).isSubset(of: provenDestinations(results, plan: plan))
    }

    /// Destinations whose successful result proves every planned file.
    static func provenDestinations(_ results: [TransferResult], plan: RunPlan) -> Set<String> {
        let needed = Set(plan.files.map(\.sourcePath))
        var proven: [String: Set<String>] = [:]
        for result in results where result.success {
            for dr in result.destinationResults where dr.success {
                proven[dr.destinationPath, default: []].formUnion(dr.verifiedSourcePaths)
            }
        }
        return Set(proven.filter { needed.isSubset(of: $0.value) }.keys)
    }

    /// The demo movie is a normal movie the user may add a real card to; its cards are
    /// made-up folders. Never seal anything for it.
    static func isSealable(configId: UUID, defaults: UserDefaults = .standard) -> Bool {
        !DemoSession.isDemo(configId, defaults: defaults)
    }

    // MARK: - Helpers

    private static func enumerate(source: URL, preset: OrganizationPreset?) async -> [CardSeal.Entry] {
        let result = await FileEnumerator.enumerateFiles(sources: [source.path], preset: preset)
        return result.entries.map {
            CardSeal.Entry(relPath: $0.relativePath, size: $0.logicalSize, modified: $0.modified)
        }
    }

    private static func volumeUUID(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    private static func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
