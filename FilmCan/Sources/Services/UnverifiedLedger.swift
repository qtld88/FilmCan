import Foundation

/// Names a run with Verification Off wrote into a roll's manifest without comparing
/// a single hash. The manifest itself carries no such marker (and ASC MHL has no place
/// for one), yet a later Fast/Paranoid run skips every file the manifest lists. It
/// consults this ledger first: a listed file is not trusted — it is re-hashed against
/// the manifest entry, and recopied if that does not match.
///
/// Stored at `<roll folder>/.filmcan/unverified.json`. An Off run writes the
/// `allUnverified` wildcard before its first byte, then the precise list at the end, so
/// a crash in between can only make the next verified run slower, never trust more.
struct UnverifiedLedger: Equatable {
    var allUnverified = false
    var names: Set<String> = []

    var isEmpty: Bool { !allUnverified && names.isEmpty }

    func contains(_ name: String) -> Bool { allUnverified || names.contains(name) }

    private struct Stored: Codable {
        var schemaVersion: Int
        var allUnverified: Bool
        var names: [String]
    }

    static let schemaVersion = 1

    static func url(rollFolder: String) -> URL {
        URL(fileURLWithPath: rollFolder, isDirectory: true)
            .appendingPathComponent(FilmCanPaths.hidden, isDirectory: true)
            .appendingPathComponent("unverified.json")
    }

    /// Missing file: nothing unverified. Unreadable or unknown file: everything is.
    static func load(rollFolder: String) -> UnverifiedLedger {
        let url = url(rollFolder: rollFolder)
        guard FileManager.default.fileExists(atPath: url.path) else { return UnverifiedLedger() }
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.schemaVersion == schemaVersion
        else { return UnverifiedLedger(allUnverified: true, names: []) }
        return UnverifiedLedger(allUnverified: stored.allUnverified, names: Set(stored.names))
    }

    /// An empty ledger removes the file.
    static func save(_ ledger: UnverifiedLedger, rollFolder: String) throws {
        let url = url(rollFolder: rollFolder)
        if ledger.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stored = Stored(schemaVersion: schemaVersion,
                            allUnverified: ledger.allUnverified,
                            names: ledger.names.sorted())
        try JSONEncoder().encode(stored).write(to: url, options: .atomic)
    }
}
