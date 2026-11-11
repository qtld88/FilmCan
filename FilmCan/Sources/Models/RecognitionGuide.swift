import Foundation

/// What the Recognition page of the Settings window says: how FilmCan recognises a
/// card, the card families it knows, and what it remembers. Text and lists only;
/// the page changes nothing about detection.
enum RecognitionGuide {

    /// One sentence per thing FilmCan looks at.
    static let signals: [String] = [
        "FilmCan reads the names of the folders and files a camera writes on its card. It never opens the clips.",
        "It looks at external drives only, three folder levels deep, and skips hidden files.",
        "A drive with WAV files and no video is taken for a sound recorder.",
        "A recognised card is added to Copy From. Nothing is copied until you start the backup.",
        "When you correct a card (right-click it in Copy From), FilmCan remembers your answer for that drive.",
        "Backup drives are not guessed. They come from the drive-name rules of each movie."
    ]

    static let whereToSwitch = "Card detection is switched on or off for each movie: Movie settings › Source."

    struct Family: Identifiable, Equatable {
        let id: String
        let name: String
        let recognisedBy: String
        let isSound: Bool
    }

    /// Every family the detector knows, straight from its enum: a family added to the
    /// detector appears here without any other change.
    static var families: [Family] {
        CameraBrand.allCases.map {
            Family(id: $0.rawValue, name: $0.displayName, recognisedBy: $0.recognisedBy, isSound: $0.isSound)
        }
    }
}

/// What FilmCan has remembered about cards, shown on the Recognition page.
enum RecognitionMemory {

    /// A drive whose role the user corrected by hand.
    struct Correction: Identifiable, Equatable {
        let volumeUUID: String
        let role: CardRole
        /// Name of the drive: as it is mounted now, else as it was when corrected.
        let driveName: String?
        let date: Date?
        let isConnected: Bool

        var id: String { volumeUUID }

        var title: String { driveName ?? "Drive not connected (\(volumeUUID.prefix(8)))" }

        var roleLabel: String {
            switch role {
            case .camera: return "Camera card"
            case .sound: return "Sound card"
            case .notACard: return "Not a card"
            }
        }
    }

    /// A card that received a roll name in a movie.
    struct Roll: Identifiable, Equatable {
        let configId: String
        let cardKey: String
        let rollName: String
        let driveName: String?
        /// Folder inside the drive, when the card is not the whole drive.
        let folder: String

        var id: String { configId + "|" + cardKey }
    }

    struct MovieRolls: Identifiable, Equatable {
        let configId: String
        /// Nil: the movie no longer exists.
        let movieName: String?
        let lastRun: Date?
        let rolls: [Roll]

        var id: String { configId }
        var title: String { movieName ?? "Deleted movie" }
    }

    /// Connected drives first, then by name.
    static func corrections(overrides: [String: CardRole],
                            details: [String: CardRoleOverrides.Detail],
                            mountedNames: [String: String]) -> [Correction] {
        overrides.map { uuid, role in
            Correction(volumeUUID: uuid, role: role,
                       driveName: mountedNames[uuid] ?? details[uuid]?.name,
                       date: details[uuid]?.date,
                       isConnected: mountedNames[uuid] != nil)
        }
        .sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            return $0.volumeUUID < $1.volumeUUID
        }
    }

    /// Movies in the order given, then movies that no longer exist; movies without a
    /// remembered card are left out. Rolls sorted by name.
    static func rolls(states: [String: RollNumberingStore.ConfigState],
                      movies: [(id: UUID, name: String)],
                      mountedNames: [String: String]) -> [MovieRolls] {
        func group(_ id: String, name: String?) -> MovieRolls? {
            guard let state = states[id], !state.assignments.isEmpty else { return nil }
            let rolls = state.assignments.map { key, rollName -> Roll in
                let parts = splitCardKey(key)
                return Roll(configId: id, cardKey: key, rollName: rollName,
                            driveName: parts.uuid.flatMap { mountedNames[$0] }, folder: parts.folder)
            }
            .sorted {
                if $0.rollName != $1.rollName {
                    return $0.rollName.localizedStandardCompare($1.rollName) == .orderedAscending
                }
                return $0.cardKey < $1.cardKey
            }
            return MovieRolls(configId: id, movieName: name, lastRun: state.lastRunDate, rolls: rolls)
        }
        var out: [MovieRolls] = []
        var seen = Set<String>()
        for movie in movies where seen.insert(movie.id.uuidString).inserted {
            if let item = group(movie.id.uuidString, name: movie.name) { out.append(item) }
        }
        for id in states.keys.sorted() where !seen.contains(id) {
            if let item = group(id, name: nil) { out.append(item) }
        }
        return out
    }

    /// A card key is "<volume UUID>|<folder inside the drive>" (`RollNumberer.cardKey`);
    /// a drive without a UUID is stored as "nouuid".
    static func splitCardKey(_ key: String) -> (uuid: String?, folder: String) {
        guard let bar = key.firstIndex(of: "|") else { return (nil, key) }
        let uuid = String(key[..<bar])
        return (uuid == "nouuid" ? nil : uuid, String(key[key.index(after: bar)...]))
    }
}
