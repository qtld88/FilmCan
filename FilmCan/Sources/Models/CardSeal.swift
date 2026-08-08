import Foundation

/// On-card record of a verified backup. Serialized to `<source>/.filmcan/seal.json`.
/// Self-contained: stores the filter patterns used so evaluation needs no live preset.
struct CardSeal: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let volumeUUID: String
    let sealDate: Date
    let appVersion: String
    let entries: [Entry]
    let includePatterns: [String]
    let excludePatterns: [String]
    let copyOnlyPatterns: [String]
    let destinationsVerified: [String]
    let mhlRef: String?

    struct Entry: Codable {
        let relPath: String
        let size: Int64
    }
}

/// Current seal status of a source, read by every surface (badge, eject guard).
enum SealState: Equatable {
    /// No marker, unreadable, foreign volume, or unknown schema.
    case none
    /// Card contents match the marker exactly.
    case sealed
    /// Card changed since the seal. Lists are relative paths.
    case broken(added: [String], missing: [String], modified: [String])
}
