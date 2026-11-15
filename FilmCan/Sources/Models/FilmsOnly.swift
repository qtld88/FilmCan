import Foundation

// A movie is the only kind of settings. Everything here is pure (no storage, no UI)
// so the rules are testable: the one-time migration, the starting points of a new
// movie, and the `.filmcan-movie` settings file.

extension FilmPresetOwnership {
    /// One-time migration at load: every movie gets its own copy of the shared preset
    /// it pointed at, then every shared record goes, then own copies whose movie no
    /// longer exists. Running it again on its own result changes nothing.
    static func migrateToFilmsOnly(configurations: [BackupConfiguration],
                                   presets: [OrganizationPreset]) -> Adoption {
        let adopted = adopt(configurations: configurations, presets: presets)
        let movieIds = Set(adopted.configurations.map(\.id))
        let kept = adopted.presets.filter { preset in
            guard let owner = preset.ownerFilmId else { return false }
            return movieIds.contains(owner)
        }
        return Adoption(configurations: adopted.configurations, presets: kept,
                        changed: adopted.changed || kept.count != adopted.presets.count)
    }
}

/// What a new movie can start from.
enum FilmStarter {
    struct Result: Equatable {
        var config: BackupConfiguration
        /// The movie's own settings record (`ownerFilmId == config.id`), if it has one.
        var preset: OrganizationPreset?
    }

    /// Today's first-run defaults, no settings record.
    static func blank(name: String) -> Result {
        Result(config: BackupConfiguration.newFilm(name: name), preset: nil)
    }

    /// A blank movie with the built-in Netflix Ingest folder settings, `Reports` log
    /// folder included. Same values as the old built-in preset.
    static func netflixIngest(name: String) -> Result {
        var config = BackupConfiguration.newFilm(name: name)
        let model = OrganizationPreset.netflixIngest()
        config.takeSettings(from: model)
        var copy = FilmPresetOwnership.ownCopy(of: model, for: config.id)
        // Same log folder in the record as in the movie (Netflix pre-fills "Reports").
        copy.logLocation = config.logLocation
        copy.customLogPath = config.customLogPath
        config.selectedOrganizationPresetId = copy.id
        return Result(config: config, preset: copy)
    }

    /// A copy of `source`'s settings (see `BackupConfiguration.newFilm(name:like:)`)
    /// with its own settings record when the source has one.
    static func like(_ source: BackupConfiguration, name: String,
                     presets: [OrganizationPreset]) -> Result {
        var config = BackupConfiguration.newFilm(name: name, like: source)
        guard let id = source.selectedOrganizationPresetId,
              let preset = presets.first(where: { $0.id == id }) else {
            return Result(config: config, preset: nil)
        }
        let copy = FilmPresetOwnership.ownCopy(
            of: FilmTemplate.replacingLeadingFilmFolder(in: preset, filmName: source.name),
            for: config.id)
        config.selectedOrganizationPresetId = copy.id
        config.mirrorOrganization(from: copy)
        return Result(config: config, preset: copy)
    }

    /// "Movie 3": numbered after the existing ones, skipping names already taken.
    static func nextName(existing: [String]) -> String {
        let taken = Set(existing)
        var number = existing.count + 1
        while taken.contains("Movie \(number)") { number += 1 }
        return "Movie \(number)"
    }
}

/// The `.filmcan-movie` file: one movie's settings, to start another movie from.
struct MovieSettingsFile: Codable, Equatable {
    static let formatName = "filmcan-movie"
    static let currentVersion = 1
    static let fileExtension = "filmcan-movie"

    var format: String
    var version: Int
    var movie: BackupConfiguration
    var folderSettings: OrganizationPreset?

    enum ImportError: LocalizedError, Equatable {
        case presetsFile
        case notAMovieFile
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .presetsFile:
                return "Presets no longer exist. Create a movie and export its settings instead."
            case .notAMovieFile:
                return "This is not a FilmCan movie settings file."
            case .unsupportedVersion(let version):
                return "This settings file is version \(version). Update FilmCan to open it."
            }
        }
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// True for a JSON array: what the removed preset export wrote.
    static func looksLikeOldPresetsFile(_ data: Data) -> Bool {
        guard let first = data.first(where: { !" \n\r\t".utf8.contains($0) }) else { return false }
        return first == UInt8(ascii: "[")
    }

    /// The movie as `newFilm(name:like:)` would leave it (no drives, sources,
    /// destinations, card names, day, episode, run roll names) with its own settings
    /// record. The id is not written (all zeros).
    static func export(movie: BackupConfiguration, presets: [OrganizationPreset]) throws -> Data {
        var stripped = BackupConfiguration.newFilm(name: movie.name, like: movie)
        var folderSettings: OrganizationPreset?
        if let id = movie.selectedOrganizationPresetId,
           let own = presets.first(where: { $0.id == id }) {
            folderSettings = FilmTemplate.replacingLeadingFilmFolder(in: own, filmName: movie.name)
            folderSettings?.ownerFilmId = nil
            folderSettings?.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        }
        stripped.id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let file = MovieSettingsFile(format: formatName, version: currentVersion,
                                     movie: stripped, folderSettings: folderSettings)
        return try encoder().encode(file)
    }

    /// A new movie (new id) with its own copy of the folder settings. `name` is the
    /// file's name; it becomes "<name> 2" (then 3, ...) when a movie already has it.
    static func makeMovie(from data: Data, name: String?,
                          existingNames: [String]) throws -> FilmStarter.Result {
        if looksLikeOldPresetsFile(data) { throw ImportError.presetsFile }
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? decoder().decode(Header.self, from: data),
              header.format == formatName, let version = header.version else {
            throw ImportError.notAMovieFile
        }
        guard version <= currentVersion else { throw ImportError.unsupportedVersion(version) }
        let file = try decoder().decode(MovieSettingsFile.self, from: data)

        var config = file.movie
        config.id = UUID()
        config.createdAt = Date()
        config.lastUsedAt = nil
        config.selectedOrganizationPresetId = nil
        let base = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        config.name = uniqueName(base.isEmpty ? file.movie.name : base, existing: existingNames)

        var copy: OrganizationPreset?
        if let settings = file.folderSettings {
            let own = FilmPresetOwnership.ownCopy(of: settings, for: config.id)
            config.selectedOrganizationPresetId = own.id
            config.mirrorOrganization(from: own)
            copy = own
        }
        return FilmStarter.Result(config: config, preset: copy)
    }

    static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
