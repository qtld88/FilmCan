import Foundation

/// Reads and writes the on-card backup seal. Signal-only: never blocks or mutates
/// card data beyond writing its own marker under `.filmcan/`.
enum CardSealService {

    static func markerURL(for source: URL) -> URL {
        source
            .appendingPathComponent(FilmCanPaths.hidden, isDirectory: true)
            .appendingPathComponent("seal.json")
    }

    /// Write a seal for a fully-verified source. Best-effort: throws only on write
    /// failure so the caller can log and continue — it must never fail a backup.
    static func seal(source: URL,
                     preset: OrganizationPreset?,
                     destinationsVerified: [String],
                     mhlRef: String?) async throws {
        let entries = await enumerate(source: source, preset: preset)
        let seal = CardSeal(
            schemaVersion: CardSeal.currentSchemaVersion,
            volumeUUID: volumeUUID(for: source) ?? "",
            sealDate: Date(),
            appVersion: appVersion(),
            entries: entries,
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
        let currentByRel = Dictionary(current.map { ($0.relPath, $0.size) },
                                      uniquingKeysWith: { a, _ in a })
        let sealByRel = Dictionary(seal.entries.map { ($0.relPath, $0.size) },
                                   uniquingKeysWith: { a, _ in a })

        var added: [String] = []
        var missing: [String] = []
        var modified: [String] = []
        for (rel, size) in currentByRel {
            if let old = sealByRel[rel] {
                if old != size { modified.append(rel) }
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

    // MARK: - Helpers

    private static func enumerate(source: URL, preset: OrganizationPreset?) async -> [CardSeal.Entry] {
        // FileEnumerator only emits regular files, but its `size` is the
        // allocated size (rounded to the filesystem block), which hides
        // sub-block content changes. The seal is about content, so re-read the
        // logical byte size per entry (`.fileSizeKey`), falling back to the
        // enumerator's size if the stat fails.
        let result = await FileEnumerator.enumerateFiles(sources: [source.path], preset: preset)
        return result.entries.map { entry in
            let logical = (try? URL(fileURLWithPath: entry.sourcePath)
                .resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            return CardSeal.Entry(relPath: entry.relativePath,
                                  size: logical.map(Int64.init) ?? entry.size)
        }
    }

    private static func volumeUUID(for url: URL) -> String? {
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    private static func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
