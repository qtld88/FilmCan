import Foundation

struct CatalogFile: Codable, Equatable {
    var relPath: String      // relative to the roll folder
    var size: Int64
}

struct CatalogCopy: Codable, Equatable {
    var destVolumeUUID: String?   // nil for network shares / unknown
    var destVolumeName: String
    var rollFolderPath: String    // absolute path at the time of the copy
    var verified: Bool            // paranoid verify passed
    var date: Date

    /// Two copies are the same drive when their UUIDs match; without UUIDs fall back to
    /// the volume root of the path. Never compare by volume name ("Untitled" × 2).
    var driveKey: String { destVolumeUUID ?? CatalogCopy.volumeRoot(of: rollFolderPath) }

    static func volumeRoot(of path: String) -> String {
        let comps = (path as NSString).pathComponents
        if comps.count >= 3, comps[1] == "Volumes" { return "/Volumes/" + comps[2] }
        return "/"
    }
}

enum CatalogCoverage: Equatable {
    case safe(drives: Int)    // >= 2 distinct verified drives
    case single               // exactly 1 verified drive
    case unverified           // copies exist but none verified
}

struct CatalogRoll: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var configId: UUID?
    var projectName: String        // BackupConfiguration.name at record time
    var shootDay: String           // config.day if non-empty, else "yyyy-MM-dd" of the run
    var rollName: String           // last path component of the roll folder
    var mediaKind: SourceMediaKind
    var sourceVolumeUUID: String?
    var sourcePath: String         // standardized
    var firstBackedUp: Date
    var files: [CatalogFile]
    var copies: [CatalogCopy]
    /// `CardFingerprint` keys of the source card's clips, sorted. Nil for rolls recorded
    /// before they existed (old catalog.json entries decode without them).
    var clipKeys: [String]? = nil

    /// Identity used to merge a new run into an existing roll.
    var identityKey: String {
        "\(configId?.uuidString ?? projectName)|\(rollName)|\(sourceVolumeUUID ?? sourcePath)"
    }

    var verifiedDriveCount: Int { Set(copies.filter(\.verified).map(\.driveKey)).count }

    var coverage: CatalogCoverage {
        let n = verifiedDriveCount
        if n >= 2 { return .safe(drives: n) }
        if n == 1 { return .single }
        return .unverified
    }

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    /// Name and size of each large file, for rolls without clip keys.
    var legacyClipKeys: Set<String> {
        Set(files.filter { $0.size >= CardFingerprint.minimumClipBytes }
            .map { CardFingerprint.legacyKey(relPath: $0.relPath, size: $0.size) })
    }

    /// Same film (same config, else same project name).
    func isSameProject(as other: CatalogRoll) -> Bool {
        if let a = configId, let b = other.configId { return a == b }
        return projectName == other.projectName
    }
}

/// An earlier roll holding some of a card's clips.
struct CatalogEarlierCopy: Equatable {
    var roll: CatalogRoll
    var matchingClips: Int
    var cardClips: Int
}

struct CatalogClipHit: Identifiable, Equatable {
    var id: String { "\(rollId.uuidString)|\(file.relPath)" }
    var rollId: UUID
    var rollName: String
    var projectName: String
    var shootDay: String
    var file: CatalogFile
    var copies: [CatalogCopy]
}

enum MediaCatalog {
    /// Merge `incoming` into `rolls`. Same `identityKey` ⇒ union files (by relPath, newest
    /// size wins) and upsert copies by `driveKey` (newest wins). Otherwise append.
    /// A roll of the same project holding the very same clips (another roll name, another
    /// drive, folder or content copy) is the same card and merges too.
    static func merge(_ incoming: CatalogRoll, into rolls: [CatalogRoll]) -> [CatalogRoll] {
        var result = rolls
        guard let idx = result.firstIndex(where: { $0.identityKey == incoming.identityKey })
                ?? result.firstIndex(where: { $0.isSameProject(as: incoming) && sameCard($0, incoming) })
        else {
            result.append(incoming)
            return result
        }
        var roll = result[idx]
        if roll.clipKeys?.isEmpty ?? true { roll.clipKeys = incoming.clipKeys }
        var byPath: [String: CatalogFile] = [:]
        for f in roll.files { byPath[f.relPath] = f }
        for f in incoming.files { byPath[f.relPath] = f }
        roll.files = byPath.values.sorted { $0.relPath < $1.relPath }
        for copy in incoming.copies {
            if let ci = roll.copies.firstIndex(where: { $0.driveKey == copy.driveKey }) {
                roll.copies[ci] = copy
            } else {
                roll.copies.append(copy)
            }
        }
        roll.firstBackedUp = min(roll.firstBackedUp, incoming.firstBackedUp)
        result[idx] = roll
        return result
    }

    /// The same card: identical clip keys, or — when either roll predates clip keys —
    /// identical names and sizes of at least two large files. A formatted and refilled
    /// card never matches: its clips differ in size and modification time.
    static func sameCard(_ a: CatalogRoll, _ b: CatalogRoll) -> Bool {
        guard a.mediaKind == b.mediaKind else { return false }
        if let ka = a.clipKeys, let kb = b.clipKeys, !ka.isEmpty, !kb.isEmpty {
            return Set(ka) == Set(kb)
        }
        let la = a.legacyClipKeys
        return la.count >= 2 && la == b.legacyClipKeys
    }

    /// Folds rolls already split in the catalog (same card, different roll names) into
    /// the oldest one. Applied on load, so earlier runs count right away.
    static func mergingSameCards(_ rolls: [CatalogRoll]) -> [CatalogRoll] {
        var result: [CatalogRoll] = []
        for roll in rolls.sorted(by: { $0.firstBackedUp < $1.firstBackedUp }) {
            result = merge(roll, into: result)
        }
        // Keep the original order of the rolls that remain.
        let kept = Set(result.map(\.id))
        let order = rolls.map(\.id).filter { kept.contains($0) }
        let byId = Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
        return order.compactMap { byId[$0] }
    }

    /// Earlier rolls (any project) holding clips of the card with `clipKeys`, most
    /// matching clips first. Legacy rolls count only on a whole-set name+size match.
    static func earlierCopies(ofClipKeys clipKeys: [String], mediaKind: SourceMediaKind,
                              in rolls: [CatalogRoll]) -> [CatalogEarlierCopy] {
        let card = Set(clipKeys)
        guard !card.isEmpty else { return [] }
        let cardLegacy = Set(clipKeys.compactMap { key -> String? in
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            return "\(parts[0])|\(parts[1])"
        })
        var hits: [CatalogEarlierCopy] = []
        for roll in rolls where roll.mediaKind == mediaKind && !roll.copies.isEmpty {
            let matching: Int
            if let keys = roll.clipKeys, !keys.isEmpty {
                matching = card.intersection(keys).count
            } else {
                let legacy = roll.legacyClipKeys
                matching = (legacy.count >= 2 && legacy == cardLegacy) ? legacy.count : 0
            }
            if matching > 0 {
                hits.append(CatalogEarlierCopy(roll: roll, matchingClips: matching, cardClips: card.count))
            }
        }
        return hits.sorted { $0.matchingClips > $1.matchingClips }
    }

    /// Case-insensitive substring match on the file's basename. Results sorted by
    /// projectName, shootDay, rollName, relPath. Capped at `limit`.
    static func search(_ query: String, in rolls: [CatalogRoll], limit: Int = 200) -> [CatalogClipHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        var hits: [CatalogClipHit] = []
        for roll in rolls {
            for file in roll.files {
                let base = (file.relPath as NSString).lastPathComponent
                if base.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    hits.append(CatalogClipHit(rollId: roll.id, rollName: roll.rollName,
                                               projectName: roll.projectName, shootDay: roll.shootDay,
                                               file: file, copies: roll.copies))
                }
            }
        }
        hits.sort {
            ($0.projectName, $0.shootDay, $0.rollName, $0.file.relPath)
                < ($1.projectName, $1.shootDay, $1.rollName, $1.file.relPath)
        }
        return Array(hits.prefix(limit))
    }

    /// Rolls with coverage != .safe, newest first.
    static func atRisk(_ rolls: [CatalogRoll]) -> [CatalogRoll] {
        rolls.filter { if case .safe = $0.coverage { return false } else { return true } }
            .sorted { $0.firstBackedUp > $1.firstBackedUp }
    }
}
