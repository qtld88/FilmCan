import XCTest
@testable import FilmCan

/// Lot 10, "movies only": the migration, the starting points of a new movie, the
/// `.filmcan-movie` file and Quick Copy reading a movie's own settings.
@MainActor
final class FilmsOnlyTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    // MARK: helpers

    private func shared(_ name: String, folder: String = "SHARED/{day}") -> OrganizationPreset {
        var p = OrganizationPreset()
        p.name = name
        p.useFolderTemplate = true
        p.folderTemplate = folder
        p.soundFolderTemplate = folder + "/Sound"
        return p
    }

    private func movie(_ name: String, preset: UUID? = nil) -> BackupConfiguration {
        var c = BackupConfiguration()
        c.name = name
        c.selectedOrganizationPresetId = preset
        c.episode = "EP4"
        c.day = "Day03"
        c.unit = "MU"
        c.cameraFormat = "ARRI"
        return c
    }

    /// Folders a run creates under a destination for one camera and one sound card.
    /// Mirrors `TransferViewModel.resolveOrganizationPreset` (record lookup, Netflix
    /// templates edited on the movie, else the movie's plain "off" fields).
    private func tree(_ film: BackupConfiguration, _ presets: [OrganizationPreset]) -> [String] {
        var preset: OrganizationPreset?
        if let id = film.selectedOrganizationPresetId,
           var found = presets.first(where: { $0.id == id }) {
            if found.name == OrganizationPreset.netflixIngestName {
                if !film.cameraFolderTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
                    found.folderTemplate = film.cameraFolderTemplate
                }
                if !film.soundFolderTemplate.trimmingCharacters(in: .whitespaces).isEmpty {
                    found.soundFolderTemplate = film.soundFolderTemplate
                }
            }
            preset = found
        } else if film.offOrganizationUseFolderTemplate,
                  !film.offOrganizationFolderTemplate.isEmpty {
            var custom = OrganizationPreset()
            custom.name = "Custom"
            custom.useFolderTemplate = true
            custom.folderTemplate = film.offOrganizationFolderTemplate
            preset = custom
        }
        var options = FolderTreeBuilder.Options()
        options.preset = preset
        options.organizationActive = preset?.useFolderTemplate ?? false
        options.date = Date(timeIntervalSince1970: 1_780_000_000)
        options.metadata = ShootMetadata(episode: film.episode, day: film.day, unit: film.unit,
                                         cameraFormat: film.cameraFormat, movie: film.name)
        let sources = [FolderTreeBuilder.Source(path: "/Volumes/A001", isDirectory: true, kind: .camera),
                       FolderTreeBuilder.Source(path: "/Volumes/S001", isDirectory: true, kind: .sound)]
        return FolderTreeBuilder.relativePaths(for: "/Volumes/SSD", sources: sources, options: options)
    }

    /// The four kinds of stored movie the spec lists, plus a shared preset nobody uses.
    private func storedSet() -> (configs: [BackupConfiguration], presets: [OrganizationPreset]) {
        var none = movie("No preset")
        none.offOrganizationUseFolderTemplate = true
        none.offOrganizationFolderTemplate = "OFF/{date}"

        var own = movie("Own copy")
        let ownRecord = FilmPresetOwnership.ownCopy(of: shared("Mine", folder: "{movie}/{day}"), for: own.id)
        own.selectedOrganizationPresetId = ownRecord.id

        let sharedUsed = shared("Alexa35")
        let onShared = movie("On shared", preset: sharedUsed.id)

        var netflix = movie("Netflix edited")
        var netflixRecord = FilmPresetOwnership.ownCopy(of: OrganizationPreset.netflixIngest(), for: netflix.id)
        netflixRecord.folderTemplate = "OLD/{date}"
        netflix.selectedOrganizationPresetId = netflixRecord.id
        netflix.cameraFolderTemplate = "RUSHES/{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"
        netflix.soundFolderTemplate = "RUSHES/{date}_{episode}_{day}_{unit}/Sound_Media"

        let unused = shared("Nobody uses me")
        return ([none, own, onShared, netflix], [ownRecord, sharedUsed, netflixRecord, unused])
    }

    // MARK: Migration

    func test_migration_keepsEveryMoviesResolvedTree() {
        let before = storedSet()
        let treesBefore = before.configs.map { tree($0, before.presets) }
        XCTAssertTrue(treesBefore.allSatisfy { !$0.isEmpty })

        let result = FilmPresetOwnership.migrateToFilmsOnly(
            configurations: before.configs, presets: before.presets)

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.configurations.map { tree($0, result.presets) }, treesBefore)
    }

    func test_migration_deletesSharedPresets_evenUnusedOnes() {
        let before = storedSet()
        let result = FilmPresetOwnership.migrateToFilmsOnly(
            configurations: before.configs, presets: before.presets)
        XCTAssertTrue(FilmPresetOwnership.shared(result.presets).isEmpty)
        XCTAssertFalse(result.presets.contains { $0.name == "Nobody uses me" })
        // One record per movie that uses settings: own copy, adopted copy, Netflix.
        XCTAssertEqual(result.presets.count, 3)
        for config in result.configurations where config.name != "No preset" {
            let id = config.selectedOrganizationPresetId
            XCTAssertEqual(result.presets.first { $0.id == id }?.ownerFilmId, config.id, config.name)
        }
    }

    func test_migration_keepsOwnRecordsUnchanged() {
        let before = storedSet()
        let result = FilmPresetOwnership.migrateToFilmsOnly(
            configurations: before.configs, presets: before.presets)
        for record in before.presets where record.ownerFilmId != nil {
            XCTAssertTrue(result.presets.contains(record), record.name)
        }
    }

    func test_migration_secondRunChangesNothing() {
        let before = storedSet()
        let first = FilmPresetOwnership.migrateToFilmsOnly(
            configurations: before.configs, presets: before.presets)
        let second = FilmPresetOwnership.migrateToFilmsOnly(
            configurations: first.configurations, presets: first.presets)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.configurations, first.configurations)
        XCTAssertEqual(second.presets, first.presets)
    }

    func test_migration_removesOrphans_butLeavesADanglingPointerAlone() {
        let gone = FilmPresetOwnership.ownCopy(of: shared("Orphan"), for: UUID())
        let dangling = movie("Dangling", preset: UUID())
        let result = FilmPresetOwnership.migrateToFilmsOnly(configurations: [dangling], presets: [gone])
        XCTAssertTrue(result.presets.isEmpty)
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.configurations, [dangling])
    }

    func test_migration_withNothingToDoReportsNoChange() {
        let m = movie("Plain")
        let result = FilmPresetOwnership.migrateToFilmsOnly(configurations: [m], presets: [])
        XCTAssertFalse(result.changed)
    }

    func test_storageLoad_migratesOnce_keepsTrees_andPersists() throws {
        let before = storedSet()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(before.configs).write(to: dir.appendingPathComponent("configs.json"))
        try encoder.encode(before.presets).write(to: dir.appendingPathComponent("presets.json"))
        let treesBefore = before.configs.map { tree($0, before.presets) }

        let first = ConfigurationStorage(baseDirectory: dir)
        XCTAssertTrue(FilmPresetOwnership.shared(first.organizationPresets).isEmpty)
        XCTAssertEqual(first.configurations.map { tree($0, first.organizationPresets) }, treesBefore)

        let second = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(second.organizationPresets, first.organizationPresets)
        XCTAssertEqual(second.configurations.map { tree($0, second.organizationPresets) }, treesBefore)
    }

    func test_storageLoad_withUnreadableMovies_deletesNoRecord() throws {
        let before = storedSet()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try "{ nope".write(to: dir.appendingPathComponent("configs.json"), atomically: true, encoding: .utf8)
        try encoder.encode(before.presets).write(to: dir.appendingPathComponent("presets.json"))
        let storage = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(storage.organizationPresets.count, before.presets.count,
                       "no movie loaded: nothing may look orphaned")
    }

    // MARK: New movie like another

    func test_newMovieLike_resetsTheShoot_keepsTheCrewSetup() {
        var source = movie("Citizen K")
        source.sourcePaths = ["/Volumes/A001"]
        source.destinationPaths = ["/Volumes/SSD"]
        source.sourceMediaKinds = ["/Volumes/A001": .sound]
        source.genericRollNames = ["card": "A001"]
        source.runRollNames = ["/Volumes/A001": "A001"]
        source.forceRecopy = true
        source.lastUsedAt = Date()
        let copy = BackupConfiguration.newFilm(name: "Movie 2", like: source)
        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.episode, "")
        XCTAssertEqual(copy.day, "")
        XCTAssertTrue(copy.sourcePaths.isEmpty)
        XCTAssertTrue(copy.destinationPaths.isEmpty)
        XCTAssertTrue(copy.sourceMediaKinds.isEmpty)
        XCTAssertTrue(copy.genericRollNames.isEmpty)
        XCTAssertTrue(copy.runRollNames.isEmpty)
        XCTAssertFalse(copy.forceRecopy)
        XCTAssertNil(copy.lastUsedAt)
        XCTAssertEqual(copy.unit, "MU")
        XCTAssertEqual(copy.cameraFormat, "ARRI")
    }

    func test_starterLike_givesTheNewMovieItsOwnRecord_andNoLinkToTheSource() throws {
        var source = movie("Citizen K")
        let record = FilmPresetOwnership.ownCopy(
            of: shared("Mine", folder: "CITIZENK/{day}"), for: source.id)
        source.selectedOrganizationPresetId = record.id
        let started = FilmStarter.like(source, name: "Movie 2", presets: [record])
        let own = try XCTUnwrap(started.preset)
        XCTAssertEqual(own.ownerFilmId, started.config.id)
        XCTAssertNotEqual(own.id, record.id)
        XCTAssertEqual(started.config.selectedOrganizationPresetId, own.id)
        XCTAssertEqual(own.folderTemplate, "{movie}/{day}", "its own top folder")
        XCTAssertEqual(started.config.episode, "")
    }

    func test_starterLike_withoutSettingsRecord_hasNone() {
        let started = FilmStarter.like(movie("Plain"), name: "Movie 2", presets: [])
        XCTAssertNil(started.preset)
        XCTAssertNil(started.config.selectedOrganizationPresetId)
    }

    func test_nextName_skipsTakenNames() {
        XCTAssertEqual(FilmStarter.nextName(existing: []), "Movie 1")
        XCTAssertEqual(FilmStarter.nextName(existing: ["Movie 2"]), "Movie 3")
        XCTAssertEqual(FilmStarter.nextName(existing: ["A", "Movie 2"]), "Movie 3")
    }

    func test_blankStarter_isTodaysFirstRunDefaults() {
        let started = FilmStarter.blank(name: "Movie 1")
        XCTAssertNil(started.preset)
        var expected = BackupConfiguration.newFilm(name: "Movie 1")
        expected.id = started.config.id
        expected.createdAt = started.config.createdAt
        XCTAssertEqual(started.config, expected)
    }

    // MARK: Netflix Ingest model

    func test_netflixStarter_resolvesTheSameTreeAsTheBuiltInPreset() throws {
        let started = FilmStarter.netflixIngest(name: "Movie 1")
        let record = try XCTUnwrap(started.preset)
        XCTAssertEqual(record.ownerFilmId, started.config.id)
        XCTAssertEqual(started.config.selectedOrganizationPresetId, record.id)

        var reference = movie("Movie 1")
        let builtIn = OrganizationPreset.netflixIngest()
        reference.selectedOrganizationPresetId = builtIn.id
        reference.id = started.config.id
        var mine = started.config
        mine.episode = reference.episode; mine.day = reference.day
        mine.unit = reference.unit; mine.cameraFormat = reference.cameraFormat

        XCTAssertEqual(tree(mine, [record]), tree(reference, [builtIn]))
    }

    func test_netflixStarter_putsLogsInReports_andKeepsTheFolderTemplates() throws {
        let started = FilmStarter.netflixIngest(name: "Movie 1")
        let record = try XCTUnwrap(started.preset)
        XCTAssertEqual(started.config.logLocation, .custom)
        XCTAssertEqual(started.config.customLogPath, "Reports")
        XCTAssertEqual(record.customLogPath, "Reports")
        XCTAssertEqual(record.folderTemplate, OrganizationPreset.netflixIngest().folderTemplate)
        XCTAssertEqual(record.soundFolderTemplate, OrganizationPreset.netflixIngest().soundFolderTemplate)
        XCTAssertEqual(record.name, OrganizationPreset.netflixIngestName)
    }

    // MARK: Settings file

    private func exportable() -> (config: BackupConfiguration, presets: [OrganizationPreset]) {
        var m = movie("Citizen K")
        m.sourcePaths = ["/Volumes/A001"]
        m.destinationPaths = ["/Volumes/SSD"]
        m.sourceMediaKinds = ["/Volumes/A001": .sound]
        m.runRollNames = ["/Volumes/A001": "A001"]
        m.duplicatePolicy = .overwrite
        m.reportEnabled = true
        var record = FilmPresetOwnership.ownCopy(
            of: shared("Mine", folder: "CITIZENK/{day}"), for: m.id)
        record.engineOptions.verificationMode = .paranoid
        m.selectedOrganizationPresetId = record.id
        return (m, [record])
    }

    func test_settingsFile_roundTrip_newIdAndNoShoot() throws {
        let source = exportable()
        let data = try MovieSettingsFile.export(movie: source.config, presets: source.presets)
        let made = try MovieSettingsFile.makeMovie(from: data, name: "Citizen K", existingNames: [])

        XCTAssertNotEqual(made.config.id, source.config.id)
        XCTAssertNotEqual(made.config.id.uuidString, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(made.config.name, "Citizen K")
        XCTAssertTrue(made.config.sourcePaths.isEmpty)
        XCTAssertTrue(made.config.destinationPaths.isEmpty)
        XCTAssertTrue(made.config.sourceMediaKinds.isEmpty)
        XCTAssertTrue(made.config.runRollNames.isEmpty)
        XCTAssertEqual(made.config.day, "")
        XCTAssertEqual(made.config.episode, "")
        XCTAssertEqual(made.config.unit, "MU")
        XCTAssertEqual(made.config.duplicatePolicy, .overwrite)
        XCTAssertTrue(made.config.reportEnabled)

        let own = try XCTUnwrap(made.preset)
        XCTAssertEqual(own.ownerFilmId, made.config.id)
        XCTAssertEqual(made.config.selectedOrganizationPresetId, own.id)
        XCTAssertEqual(own.folderTemplate, "{movie}/{day}", "the leading movie folder follows the new name")
        XCTAssertEqual(own.soundFolderTemplate, "{movie}/{day}/Sound")
        XCTAssertEqual(own.engineOptions.verificationMode, .paranoid)
        XCTAssertEqual(made.config.organizationFolderTemplate, own.folderTemplate)
    }

    func test_settingsFile_nameClashGetsASuffix() throws {
        let source = exportable()
        let data = try MovieSettingsFile.export(movie: source.config, presets: source.presets)
        XCTAssertEqual(try MovieSettingsFile.makeMovie(
            from: data, name: "Citizen K", existingNames: ["Citizen K"]).config.name, "Citizen K 2")
        XCTAssertEqual(try MovieSettingsFile.makeMovie(
            from: data, name: "Citizen K", existingNames: ["Citizen K", "Citizen K 2"]).config.name, "Citizen K 3")
        XCTAssertEqual(try MovieSettingsFile.makeMovie(
            from: data, name: nil, existingNames: []).config.name, "Citizen K")
    }

    func test_settingsFile_movieWithoutRecord_importsWithoutOne() throws {
        let data = try MovieSettingsFile.export(movie: movie("Plain"), presets: [])
        let made = try MovieSettingsFile.makeMovie(from: data, name: "Plain", existingNames: [])
        XCTAssertNil(made.preset)
        XCTAssertNil(made.config.selectedOrganizationPresetId)
    }

    private func edited(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&json)
        return try JSONSerialization.data(withJSONObject: json)
    }

    func test_settingsFile_unknownVersionOrFormatIsRefused() throws {
        let source = exportable()
        let data = try MovieSettingsFile.export(movie: source.config, presets: source.presets)

        let future = try edited(data) { $0["version"] = 99 }
        XCTAssertThrowsError(try MovieSettingsFile.makeMovie(from: future, name: nil, existingNames: [])) {
            XCTAssertEqual($0 as? MovieSettingsFile.ImportError, .unsupportedVersion(99))
        }
        let other = try edited(data) { $0["format"] = "something-else" }
        XCTAssertThrowsError(try MovieSettingsFile.makeMovie(from: other, name: nil, existingNames: [])) {
            XCTAssertEqual($0 as? MovieSettingsFile.ImportError, .notAMovieFile)
        }
        XCTAssertThrowsError(try MovieSettingsFile.makeMovie(from: Data("hello".utf8), name: nil, existingNames: []))
    }

    func test_settingsFile_unknownFieldsAreIgnored() throws {
        let source = exportable()
        let data = try MovieSettingsFile.export(movie: source.config, presets: source.presets)
        let newer = try edited(data) { $0["somethingNew"] = ["a": 1] }
        XCTAssertNoThrow(try MovieSettingsFile.makeMovie(from: newer, name: nil, existingNames: []))
    }

    func test_oldPresetsFileIsRefusedWithThePlainMessage() throws {
        let encoder = JSONEncoder()
        let presetsFile = try encoder.encode([shared("Old")])
        XCTAssertThrowsError(try MovieSettingsFile.makeMovie(from: presetsFile, name: nil, existingNames: [])) {
            XCTAssertEqual($0 as? MovieSettingsFile.ImportError, .presetsFile)
            XCTAssertEqual($0.localizedDescription,
                           "Presets no longer exist. Create a movie and export its settings instead.")
        }
        // The "Movies & History" import refuses it the same way.
        let storage = ConfigurationStorage(baseDirectory: dir)
        XCTAssertThrowsError(try storage.decodeMoviesHistoryConfigurations(from: presetsFile)) {
            XCTAssertEqual($0 as? MovieSettingsFile.ImportError, .presetsFile)
        }
    }

    // MARK: Quick Copy reads the movie's own record

    private func item(_ name: String) -> QuickCopyFormModel.Item {
        .init(path: "/Volumes/CARD/\(name)", isDirectory: true, kind: .camera)
    }

    func test_quickCopy_withAMovie_usesItsOwnRecord_withoutOne_none() throws {
        var film = movie("TLF")
        let record = FilmPresetOwnership.ownCopy(of: shared("Mine", folder: "{date}/Camera_Media"), for: film.id)
        film.selectedOrganizationPresetId = record.id
        var form = QuickCopyFormModel(items: [item("A001")])
        form.savedPresets = [record, shared("Stray shared")]
        form.savedFilms = [film]

        form.selectFilm(film.id)
        XCTAssertEqual(form.selectedPresetId, record.id)
        XCTAssertEqual(form.makeConfiguration().selectedOrganizationPresetId, record.id)
        XCTAssertNotNil(form.runPreset())

        form.selectFilm(nil)
        XCTAssertNil(form.selectedPresetId)
        XCTAssertNil(form.makeConfiguration().selectedOrganizationPresetId)
        XCTAssertNil(form.runPreset())
    }
}
