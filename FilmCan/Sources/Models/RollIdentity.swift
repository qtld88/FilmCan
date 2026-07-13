import Foundation

/// Identity of the source volume that last wrote a given roll folder, stored as a
/// hidden sidecar (`<rollFolder>/.filmcan/roll.json`). A later run uses it to tell
/// whether a same-named source is the SAME card (genuine resume) or a DIFFERENT card
/// that merely shares a volume name and must be saved to its own roll folder.
struct RollIdentity: Codable, Equatable {
    var volumeUUID: String?
    var volumeName: String
    /// Standardized source-root path that last wrote this roll. Distinguishes the SAME
    /// card (same path) from a DIFFERENT staged folder on the SAME drive (same volume
    /// UUID, different path). Optional so pre-existing sidecars decode as nil (legacy).
    var sourcePath: String?
    var lastSeen: Date
}

/// What the engine recommends when a same-named roll already exists at a destination.
enum RollIdentityRecommendation: String, Equatable {
    case resumeSameCard   // recorded UUID == current UUID — same physical card
    case newCard          // recorded UUID != current UUID (both known) — different card
    case unknown          // no prior identity, or a UUID is missing — can't be sure
}

enum RollIdentityResolver {
    /// Compare the recorded identity against the current source. A volume UUID match
    /// alone is NOT enough — two different staged folders on one shuttle drive share a
    /// UUID. Require the source path to match too before declaring the same card. Legacy
    /// sidecars carry no path; fall back to UUID-only so existing rolls still resume.
    static func recommend(recorded: RollIdentity?, currentUUID: String?, currentPath: String?) -> RollIdentityRecommendation {
        guard let recorded else { return .unknown }
        guard let cur = currentUUID, !cur.isEmpty,
              let rec = recorded.volumeUUID, !rec.isEmpty else { return .unknown }
        if cur != rec { return .newCard }
        guard let recPath = recorded.sourcePath, !recPath.isEmpty,
              let curPath = currentPath, !curPath.isEmpty else { return .resumeSameCard }
        return recPath == curPath ? .resumeSameCard : .newCard
    }

    /// Headless default when no UI handler is present: follow the recommendation,
    /// treating `.unknown` as resume (the historical behavior).
    static func defaultDecisionIsResume(_ r: RollIdentityRecommendation) -> Bool {
        switch r {
        case .resumeSameCard, .unknown: return true
        case .newCard: return false
        }
    }
}

/// Reads/writes the per-roll identity sidecar. The sidecar lives under the roll's
/// `.filmcan/` dir so it is never confused with media and never matches OrphanCleaner's
/// `.filmcan-` temp prefix.
enum RollIdentityStore {
    static func sidecarURL(rollFolder: String) -> URL {
        URL(fileURLWithPath: rollFolder)
            .appendingPathComponent(FilmCanPaths.hidden)
            .appendingPathComponent("roll.json")
    }

    static func read(rollFolder: String) -> RollIdentity? {
        guard let data = try? Data(contentsOf: sidecarURL(rollFolder: rollFolder)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RollIdentity.self, from: data)
    }

    static func write(_ identity: RollIdentity, rollFolder: String) {
        let url = sidecarURL(rollFolder: rollFolder)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(identity) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
