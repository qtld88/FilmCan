import XCTest
@testable import FilmCan

/// A film owns its settings: a preset is a starting point, never a live link.
@MainActor
final class FilmPresetOwnershipTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func sharedPreset(_ name: String = "Alexa35") -> OrganizationPreset {
        var p = OrganizationPreset()
        p.name = name
        p.useFolderTemplate = true
        p.folderTemplate = "CITIZENK/{day}"
        p.soundFolderTemplate = "CITIZENK/{day}/Sound"
        p.duplicatePolicy = .skip
        return p
    }

    private func film(_ name: String, preset: UUID?) -> BackupConfiguration {
        var c = BackupConfiguration()
        c.name = name
        c.selectedOrganizationPresetId = preset
        return c
    }

    /// Everything a run reads from a preset, identity aside.
    private func values(_ p: OrganizationPreset) -> OrganizationPreset {
        var v = p
        v.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        v.ownerFilmId = nil
        return v
    }

    // MARK: Decoding

    func test_legacyPresetJSON_decodesWithoutOwner() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","folderTemplate":"{date}/{source}","useFolderTemplate":true}"#
        let p = try JSONDecoder().decode(OrganizationPreset.self, from: Data(json.utf8))
        XCTAssertNil(p.ownerFilmId)
    }

    func test_owner_roundTrips_andSharedPresetWritesNoKey() throws {
        var p = sharedPreset()
        let sharedJSON = String(data: try JSONEncoder().encode(p), encoding: .utf8)!
        XCTAssertFalse(sharedJSON.contains("ownerFilmId"))
        let owner = UUID()
        p.ownerFilmId = owner
        let back = try JSONDecoder().decode(OrganizationPreset.self, from: try JSONEncoder().encode(p))
        XCTAssertEqual(back.ownerFilmId, owner)
    }

    // MARK: Adoption

    func test_adopt_givesEachFilmItsOwnCopy_withTheSameValues() {
        let preset = sharedPreset()
        let a = film("A", preset: preset.id), b = film("B", preset: preset.id)
        let result = FilmPresetOwnership.adopt(configurations: [a, b], presets: [preset])

        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.presets.count, 3, "the shared preset stays, plus one copy per film")
        XCTAssertEqual(result.presets[0], preset, "the shared preset is untouched")
        let idA = result.configurations[0].selectedOrganizationPresetId
        let idB = result.configurations[1].selectedOrganizationPresetId
        XCTAssertNotEqual(idA, preset.id)
        XCTAssertNotEqual(idA, idB)
        for (config, id) in [(a, idA), (b, idB)] {
            let copy = result.presets.first { $0.id == id }
            XCTAssertEqual(copy?.ownerFilmId, config.id)
            XCTAssertEqual(copy.map(values), values(preset), "same folders and files as before")
            XCTAssertEqual(copy?.name, preset.name, "built-in behaviours are keyed on the name")
        }
    }

    func test_adopt_isIdempotent() {
        let preset = sharedPreset()
        let first = FilmPresetOwnership.adopt(
            configurations: [film("A", preset: preset.id)], presets: [preset])
        let second = FilmPresetOwnership.adopt(configurations: first.configurations, presets: first.presets)
        XCTAssertFalse(second.changed)
        XCTAssertEqual(second.presets, first.presets)
        XCTAssertEqual(second.configurations, first.configurations)
    }

    func test_adopt_leavesFilmsWithoutPresetOrWithDanglingIdAlone() {
        let none = film("None", preset: nil), dangling = film("Dangling", preset: UUID())
        let result = FilmPresetOwnership.adopt(configurations: [none, dangling], presets: [sharedPreset()])
        XCTAssertFalse(result.changed)
        XCTAssertEqual(result.configurations, [none, dangling])
    }

    func test_adopt_alignsTheFilmsWorkingCopy_soItsFirstSaveCannotWriteStaleFolders() {
        let preset = sharedPreset()
        var stale = film("B", preset: preset.id)
        stale.organizationFolderTemplate = "OLD/{date}"
        stale.organizationUseFolderTemplate = true
        let result = FilmPresetOwnership.adopt(configurations: [stale], presets: [preset])
        XCTAssertEqual(result.configurations[0].organizationFolderTemplate, "CITIZENK/{day}")
    }

    func test_adopt_copiesAPresetOwnedByAnotherFilm() {
        var foreign = sharedPreset()
        foreign.ownerFilmId = UUID()
        let config = film("A", preset: foreign.id)
        let result = FilmPresetOwnership.adopt(configurations: [config], presets: [foreign])
        XCTAssertTrue(result.changed)
        XCTAssertEqual(result.presets.last?.ownerFilmId, config.id)
    }

    func test_sharedFilter_andRemovalWithTheFilm() {
        let shared = sharedPreset()
        let filmId = UUID()
        let own = FilmPresetOwnership.ownCopy(of: shared, for: filmId)
        let other = FilmPresetOwnership.ownCopy(of: shared, for: UUID())
        XCTAssertEqual(FilmPresetOwnership.shared([shared, own, other]), [shared])
        XCTAssertEqual(FilmPresetOwnership.removingCopies(ownedBy: filmId, from: [shared, own, other]),
                       [shared, other])
    }

    func test_nextSharedName_ignoresOwnCopies_andSkipsTakenNames() {
        var p2 = sharedPreset("Preset 2")
        p2.id = UUID()
        let own = FilmPresetOwnership.ownCopy(of: sharedPreset("Preset 9"), for: UUID())
        XCTAssertEqual(FilmPresetOwnership.nextSharedName(in: [own]), "Preset 1")
        XCTAssertEqual(FilmPresetOwnership.nextSharedName(in: [sharedPreset("X"), p2]), "Preset 3")
        XCTAssertEqual(FilmPresetOwnership.nextSharedName(in: [p2]), "Preset 3")
    }

    // MARK: Storage

    private func writeLegacyFiles(configs: [BackupConfiguration], presets: [OrganizationPreset]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(configs).write(to: dir.appendingPathComponent("configs.json"))
        try encoder.encode(presets).write(to: dir.appendingPathComponent("presets.json"))
    }

    func test_storageLoad_adoptsOnce_andPersists() throws {
        let preset = sharedPreset()
        try writeLegacyFiles(configs: [film("A", preset: preset.id), film("B", preset: preset.id)],
                             presets: [preset])

        let first = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(first.organizationPresets.count, 3)
        let ids = first.configurations.map(\.selectedOrganizationPresetId)
        XCTAssertFalse(ids.contains(preset.id))

        let second = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(second.organizationPresets.count, 3, "a second launch adopts nothing more")
        XCTAssertEqual(second.configurations.map(\.selectedOrganizationPresetId), ids)
    }

    func test_storageLoad_withUnreadablePresets_changesNoFilm() throws {
        let preset = sharedPreset()
        try writeLegacyFiles(configs: [film("A", preset: preset.id)], presets: [preset])
        try "{ nope".write(to: dir.appendingPathComponent("presets.json"), atomically: true, encoding: .utf8)

        let storage = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(storage.configurations.first?.selectedOrganizationPresetId, preset.id)
    }

    func test_deletingAFilm_removesItsCopy_notTheSharedPreset() throws {
        let preset = sharedPreset()
        try writeLegacyFiles(configs: [film("A", preset: preset.id), film("B", preset: preset.id)],
                             presets: [preset])
        let storage = ConfigurationStorage(baseDirectory: dir)
        let a = storage.configurations[0]

        storage.delete(a)

        XCTAssertEqual(storage.organizationPresets.count, 2)
        XCTAssertTrue(storage.organizationPresets.contains { $0.id == preset.id })
        XCTAssertFalse(storage.organizationPresets.contains { $0.ownerFilmId == a.id })
    }

    func test_export_writesSharedPresetsOnly_andImportNeverCreatesAnOwnedOne() throws {
        let preset = sharedPreset()
        try writeLegacyFiles(configs: [film("A", preset: preset.id)], presets: [preset])
        let storage = ConfigurationStorage(baseDirectory: dir)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode([OrganizationPreset].self, from: storage.exportPresetsData())
        XCTAssertEqual(exported.map(\.id), [preset.id])

        var incoming = sharedPreset("Imported")
        incoming.id = UUID()
        incoming.ownerFilmId = UUID()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try storage.importPresets(from: encoder.encode([incoming]))
        XCTAssertNil(storage.organizationPresets.first { $0.id == incoming.id }?.ownerFilmId)
    }

    // MARK: Editing one film never reaches another

    func test_editingOneFilm_leavesTheOtherFilmAndTheSharedPresetUnchanged() throws {
        // A storage of its own in a temp directory: the app's real films are never touched.
        let storage = ConfigurationStorage(baseDirectory: dir)
        let preset = sharedPreset()
        var a = film("Ownership A", preset: nil), b = film("Ownership B", preset: nil)
        storage.organizationPresets.append(preset)
        storage.add(a)
        storage.add(b)

        let editorA = BackupEditorViewModel(config: a, storage: storage)
        let editorB = BackupEditorViewModel(config: b, storage: storage)
        editorA.applyPreset(preset)
        editorB.applyPreset(preset)
        a = editorA.config
        b = editorB.config
        let idA = try XCTUnwrap(a.selectedOrganizationPresetId)
        let idB = try XCTUnwrap(b.selectedOrganizationPresetId)
        XCTAssertNotEqual(idA, preset.id)
        XCTAssertNotEqual(idA, idB)
        let copyBBefore = storage.organizationPresets.first { $0.id == idB }

        // Film A changes its folders the way the editor does: through its own record.
        var presets = editorA.organizationPresets
        let index = try XCTUnwrap(presets.firstIndex { $0.id == idA })
        presets[index].folderTemplate = "CHANGED/{day}"
        editorA.organizationPresets = presets
        editorA.syncFromSelectedPresetIfNeeded()
        editorA.copyFolderContents.toggle()

        XCTAssertEqual(storage.organizationPresets.first { $0.id == preset.id }, preset)
        XCTAssertEqual(storage.organizationPresets.first { $0.id == idB }, copyBBefore)
        XCTAssertEqual(storage.organizationPresets.first { $0.id == idA }?.folderTemplate, "CHANGED/{day}")

        // Choosing another preset replaces the copy instead of piling them up.
        editorA.applyPreset(preset)
        XCTAssertEqual(storage.organizationPresets.filter { $0.ownerFilmId == a.id }.count, 1)
        // Off removes it.
        editorA.applyOffOrganizationSettings()
        XCTAssertNil(editorA.config.selectedOrganizationPresetId)
        XCTAssertTrue(storage.organizationPresets.filter { $0.ownerFilmId == a.id }.isEmpty)
        // Saving as a preset adds a shared one and keeps film B on its own copy.
        let sharedBefore = FilmPresetOwnership.shared(storage.organizationPresets).count
        editorB.saveCurrentSettingsAsPreset()
        let sharedAfter = FilmPresetOwnership.shared(storage.organizationPresets)
        XCTAssertEqual(sharedAfter.count, sharedBefore + 1)
        XCTAssertEqual(editorB.config.selectedOrganizationPresetId, idB)
        XCTAssertEqual(sharedAfter.last?.soundFolderTemplate, preset.soundFolderTemplate)
        XCTAssertEqual(sharedAfter.last?.name, "Preset 2", "the name of the starting preset is taken")
    }
}

final class MovieTokenTests: XCTestCase {
    private func preset(_ template: String) -> OrganizationPreset {
        var p = OrganizationPreset()
        p.useFolderTemplate = true
        p.folderTemplate = template
        return p
    }

    private func folder(_ template: String, movie: String) -> String {
        OrganizationTemplate.resolve(
            preset: preset(template), sourcePath: "/cards/A001", destinationRoot: "/dest",
            counter: 0, date: Date(timeIntervalSince1970: 1_780_000_000),
            metadata: ShootMetadata(day: "Day02", movie: movie)).folderPath
    }

    func test_movieToken_resolvesToTheFilmName() {
        XCTAssertEqual(folder("{movie}/{day}", movie: "Citizen K"), "Citizen K/Day02")
    }

    func test_movieToken_neverOpensASubfolder() {
        XCTAssertEqual(folder("{movie}/{day}", movie: "Fast/Slow: Part 2"), "Fast-Slow- Part 2/Day02")
    }

    func test_templateWithoutTheToken_isUnchangedByTheFilmName() {
        XCTAssertEqual(folder("CITIZENK/{day}", movie: "Anything"), folder("CITIZENK/{day}", movie: ""))
        XCTAssertEqual(folder("CITIZENK/{day}", movie: "Anything"), "CITIZENK/Day02")
    }

    func test_emptyFilmName_collapsesLikeAnyEmptyToken() {
        XCTAssertEqual(folder("{movie}/{day}", movie: ""), "Day02")
    }
}

final class NewFilmLikeTests: XCTestCase {

    func test_leadingFolderThatSpellsTheFilmName_becomesTheMovieToken() {
        XCTAssertEqual(FilmTemplate.replacingLeadingFilmFolder(in: "CITIZENK/{day}", filmName: "Citizen K"),
                       "{movie}/{day}")
        XCTAssertEqual(FilmTemplate.replacingLeadingFilmFolder(in: "Citizen_K", filmName: "Citizen K"), "{movie}")
    }

    func test_otherLeadingFolders_areLeftAsTyped() {
        for template in ["RUSHES/CITIZENK/{day}", "{date}/CITIZENK", "CITIZENK2/{day}", "", "{movie}/{day}"] {
            XCTAssertEqual(FilmTemplate.replacingLeadingFilmFolder(in: template, filmName: "Citizen K"), template)
        }
        XCTAssertEqual(FilmTemplate.replacingLeadingFilmFolder(in: "X/{day}", filmName: "  "), "X/{day}")
    }

    func test_newFilmLike_copiesSettings_notTheShoot() {
        var source = BackupConfiguration()
        source.name = "Citizen K"
        source.sourcePaths = ["/Volumes/A001"]
        source.destinationPaths = ["/Volumes/SSD"]
        source.excludedSourcePaths = ["/Volumes/A001"]
        source.excludedDestinationPaths = ["/Volumes/SSD"]
        source.sourceMediaKinds = ["/Volumes/A001": .sound]
        source.genericRollNames = ["card": "A001"]
        source.day = "Day07"
        source.forceRecopy = true
        source.lastUsedAt = Date()
        source.selectedOrganizationPresetId = UUID()
        // Settings.
        source.engineOptions.postVerify.toggle()
        source.duplicatePolicy = .skip
        source.reportEnabled = true
        source.logEnabled = false
        source.hashListStyle = .simpleHidden
        source.rollNumbering.enabled = true
        source.rollNumbering.cameraPrefix = "B"
        source.dayAutoAdvance = true
        source.cardAutoDetectEnabled = true
        source.sourceAutoDetectEnabled = true
        source.sourceAutoDetectPatterns = ["A*"]
        source.destinationAutoDetectPatterns = ["SSD*"]
        source.soundAutoDetectPatterns = ["MIX*"]
        source.episode = "EP1"
        source.unit = "MU"
        source.cameraFormat = "ARRI"
        source.cameraFolderTemplate = "CITIZENK/{day}/Camera"
        source.offOrganizationFolderTemplate = "CITIZENK/{date}"

        let copy = BackupConfiguration.newFilm(name: "Movie 2", like: source)

        XCTAssertNotEqual(copy.id, source.id)
        XCTAssertEqual(copy.name, "Movie 2")
        XCTAssertTrue(copy.sourcePaths.isEmpty)
        XCTAssertTrue(copy.destinationPaths.isEmpty)
        XCTAssertTrue(copy.excludedSourcePaths.isEmpty)
        XCTAssertTrue(copy.excludedDestinationPaths.isEmpty)
        XCTAssertTrue(copy.sourceMediaKinds.isEmpty)
        XCTAssertTrue(copy.genericRollNames.isEmpty)
        XCTAssertEqual(copy.day, "")
        XCTAssertFalse(copy.forceRecopy)
        XCTAssertNil(copy.lastUsedAt)
        XCTAssertNil(copy.selectedOrganizationPresetId, "the caller attaches the film's own copy")

        XCTAssertEqual(copy.engineOptions, source.engineOptions)
        XCTAssertEqual(copy.duplicatePolicy, .skip)
        XCTAssertTrue(copy.reportEnabled)
        XCTAssertFalse(copy.logEnabled)
        XCTAssertEqual(copy.hashListStyle, .simpleHidden)
        XCTAssertEqual(copy.rollNumbering, source.rollNumbering)
        XCTAssertTrue(copy.dayAutoAdvance)
        XCTAssertTrue(copy.cardAutoDetectEnabled)
        XCTAssertTrue(copy.sourceAutoDetectEnabled)
        XCTAssertEqual(copy.sourceAutoDetectPatterns, ["A*"])
        XCTAssertEqual(copy.destinationAutoDetectPatterns, ["SSD*"])
        XCTAssertEqual(copy.soundAutoDetectPatterns, ["MIX*"])
        XCTAssertEqual(copy.episode, "EP1")
        XCTAssertEqual(copy.unit, "MU")
        XCTAssertEqual(copy.cameraFormat, "ARRI")
        // The new film gets its own top folder.
        XCTAssertEqual(copy.cameraFolderTemplate, "{movie}/{day}/Camera")
        XCTAssertEqual(copy.offOrganizationFolderTemplate, "{movie}/{date}")
    }
}
