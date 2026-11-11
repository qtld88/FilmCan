import XCTest
@testable import FilmCan

final class FolderStructureTests: XCTestCase {

    private func roundTrip(_ camera: String, _ sound: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let s = FolderStructure.parse(camera: camera, sound: sound) else {
            return XCTFail("\(camera) | \(sound) should be editable", file: file, line: line)
        }
        XCTAssertEqual(s.cameraTemplate, camera, file: file, line: line)
        XCTAssertEqual(s.soundTemplate, sound, file: file, line: line)
    }

    // MARK: Round trip, or not editable

    func test_shippedLayouts_roundTripUnchanged() {
        let netflix = OrganizationPreset.netflixIngest()
        roundTrip(netflix.folderTemplate, netflix.soundFolderTemplate)
        let fresh = BackupConfiguration()
        roundTrip(fresh.cameraFolderTemplate, fresh.soundFolderTemplate)
        roundTrip(QuickCopyFormModel.projectCameraTemplate, QuickCopyFormModel.projectSoundTemplate)
        roundTrip(QuickCopyFormModel.dateCameraTemplate, QuickCopyFormModel.dateSoundTemplate)
        roundTrip("", "")
        roundTrip("CITIZENK/RUSHES/Camera_Media", "")
        roundTrip("{movie}/{day}", "{movie}/{day}/Sound")
        roundTrip("A/B", "X/Y")
    }

    func test_everyStartingPoint_roundTrips() {
        for point in FolderStructure.startingPoints {
            roundTrip(point.structure.cameraTemplate, point.structure.soundTemplate)
        }
    }

    func test_layoutsTheTreeCannotShow_areDeclaredNotEditable() {
        let notEditable: [(String, String)] = [
            ("ARRI/{sourceDriveName}/DAY_{date}/CARD_{source}", ""),
            ("RUSHES/DAY_{counter}_{date}", ""),
            ("{filecreationdate}/Camera", ""),
            ("A//B", ""),
            ("/A", ""),
            ("A/", ""),
            (" A/B", ""),
            ("A\\B", ""),
            ("A/{unknown}", ""),
            ("A", "B/{source}"),
            ("", "Sound"),
            ("A/ /B", "")
        ]
        for (camera, sound) in notEditable {
            XCTAssertNil(FolderStructure.parse(camera: camera, sound: sound), "\(camera) | \(sound)")
        }
    }

    /// Whatever the editor does, the text it writes resolves through the engine's own
    /// function to the folders the tree shows.
    func test_editedStructure_resolvesToTheFoldersItShows() {
        var s = FolderStructure()
        s.addFolder("{movie}", inside: nil)
        s.addFolder("{day}", inside: s.rows[0])
        s.separateSound()
        var preset = OrganizationPreset()
        preset.useFolderTemplate = true
        preset.folderTemplate = s.cameraTemplate
        preset.soundFolderTemplate = s.soundTemplate
        let meta = ShootMetadata(day: "Day02", movie: "Citizen K")
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let camera = OrganizationTemplate.resolve(preset: preset, sourcePath: "/cards/A001", destinationRoot: "/dest",
                                                  counter: 0, date: date, metadata: meta, mediaKind: .camera)
        let sound = OrganizationTemplate.resolve(preset: preset, sourcePath: "/cards/S001", destinationRoot: "/dest",
                                                 counter: 0, date: date, metadata: meta, mediaKind: .sound)
        XCTAssertEqual(camera.folderPath, "Citizen K/Day02")
        XCTAssertEqual(sound.folderPath, "Citizen K/Sound")
    }

    // MARK: The reference structures, built without typing a token

    func test_oneDay_severalDays_andNetflix_areBuiltFromMenusOnly() {
        var oneDay = FolderStructure()
        oneDay.addFolder("{movie}", inside: nil)
        oneDay.addFolder("Camera", inside: oneDay.rows[0])
        oneDay.separateSound()
        XCTAssertEqual(oneDay, FolderStructure.startingPoints[0].structure)

        var severalDays = oneDay
        severalDays.addFolder("{day}", inside: severalDays.rows[0])
        XCTAssertEqual(severalDays, FolderStructure.startingPoints[1].structure)

        let netflix = OrganizationPreset.netflixIngest()
        XCTAssertEqual(FolderStructure.startingPoints[2].structure.cameraTemplate, netflix.folderTemplate)
        XCTAssertEqual(FolderStructure.startingPoints[2].structure.soundTemplate, netflix.soundFolderTemplate)
        XCTAssertEqual(FolderStructure.startingPoints[3].structure.cameraTemplate, "")
    }

    // MARK: Rows

    func test_rows_sharedThenCameraThenSound_withLandingMarks() {
        let s = FolderStructure(camera: ["{movie}", "{day}", "Camera"], sound: ["{movie}", "{day}", "Sound"])
        let rows = s.rows
        XCTAssertEqual(rows.map(\.branch), [.shared, .shared, .camera, .sound])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 2])
        XCTAssertEqual(rows.map(\.label), ["Movie name", "Shoot day", "Camera", "Sound"])
        XCTAssertEqual(rows.map(\.holdsCards), [false, false, true, false])
        XCTAssertEqual(rows.map(\.holdsSound), [false, false, false, true])
        XCTAssertEqual(rows.map(\.isPlain), [false, false, true, true])
    }

    func test_soundWithCards_marksTheSameFolder() {
        let s = FolderStructure(camera: ["{movie}", "{day}"])
        XCTAssertEqual(s.rows.map(\.holdsCards), [false, true])
        XCTAssertEqual(s.rows.map(\.holdsSound), [false, true])
        XCTAssertFalse(s.soundIsSeparate)
        XCTAssertTrue(FolderStructure().cardsAtTopLevel)
        XCTAssertTrue(FolderStructure().soundAtTopLevel)
    }

    func test_mixedName_showsItsWordsInClear() {
        XCTAssertEqual(FolderStructure.label(for: "{date}_{episode}_{day}_{unit}"),
                       "‹Date›_‹Project / episode›_‹Shoot day›_‹Unit›")
        XCTAssertEqual(FolderStructure.label(for: "RUSHES"), "RUSHES")
    }

    // MARK: Editing

    func test_rename_changesSharedFolderInBothPaths_andRefusesUnsafeNames() {
        var s = FolderStructure(camera: ["PROJECT", "Camera"], sound: ["PROJECT", "Sound"])
        s.rename(s.rows[0], to: " Citizen/K: {x} ")
        XCTAssertEqual(s.cameraTemplate, "CitizenK x/Camera")
        XCTAssertEqual(s.soundTemplate, "CitizenK x/Sound")
        s.rename(s.rows[0], to: "  ")
        XCTAssertEqual(s.camera.first, "CitizenK x")
        // A folder named by a word (Shoot day) is not renamed by typing.
        var t = FolderStructure(camera: ["{day}"])
        t.rename(t.rows[0], to: "X")
        XCTAssertEqual(t.cameraTemplate, "{day}")
    }

    func test_remove_andMove() {
        var s = FolderStructure(camera: ["{movie}", "{day}", "Camera"], sound: ["{movie}", "{day}", "Sound"])
        XCTAssertTrue(s.canMove(s.rows[0], by: 1))
        XCTAssertFalse(s.canMove(s.rows[0], by: -1))
        XCTAssertFalse(s.canMove(s.rows[1], by: 1), "a shared folder cannot go below a folder only cards use")
        XCTAssertFalse(s.canMove(s.rows[2], by: -1))
        s.move(s.rows[0], by: 1)
        XCTAssertEqual(s.cameraTemplate, "{day}/{movie}/Camera")
        XCTAssertEqual(s.soundTemplate, "{day}/{movie}/Sound")
        s.remove(s.rows[0])
        XCTAssertEqual(s.cameraTemplate, "{movie}/Camera")
        XCTAssertEqual(s.soundTemplate, "{movie}/Sound")
        // Removing the sound's only own folder puts sound... in the shared folder.
        s.remove(s.rows[2])
        XCTAssertEqual(s.soundTemplate, "{movie}")
        // Removing the cards' own folder makes both paths equal: sound is with the cards again.
        s.remove(s.rows.first { $0.branch == .camera }!)
        XCTAssertEqual(s.cameraTemplate, "{movie}")
        XCTAssertEqual(s.soundTemplate, "")
        XCTAssertFalse(s.soundIsSeparate)
    }

    func test_separateSound_andBack() {
        var s = FolderStructure(camera: ["{movie}", "Sound"])
        s.separateSound()
        XCTAssertEqual(s.soundTemplate, "{movie}/Sound 2", "never the cards' own folder")
        s.putSoundWithCards()
        XCTAssertEqual(s.soundTemplate, "")
        var top = FolderStructure()
        top.separateSound()
        XCTAssertFalse(top.soundIsSeparate, "needs a cards folder first")
    }

    func test_everyEdit_staysEditable() {
        var s = FolderStructure.startingPoints[1].structure
        s.addFolder("Rushes: A/B", inside: s.rows[1])
        s.addFolder("{date}", inside: nil)
        s.move(s.rows[1], by: 1)
        s.rename(s.rows.last!, to: "Audio")
        XCTAssertEqual(FolderStructure.parse(camera: s.cameraTemplate, sound: s.soundTemplate), s)
    }
}

final class FolderLayoutSourceTests: XCTestCase {

    func test_netflixPreset_readsTheFilmsOwnFieldsFirst_likeTheRun() {
        let preset = OrganizationPreset.netflixIngest()
        let filled = FolderLayoutSource.templates(preset: preset, isNetflix: true,
                                                  cameraOverride: "X/Camera", soundOverride: "  ")
        XCTAssertEqual(filled.camera, "X/Camera")
        XCTAssertEqual(filled.sound, preset.soundFolderTemplate, "a blank field falls back to the preset")
        let other = FolderLayoutSource.templates(preset: preset, isNetflix: false,
                                                 cameraOverride: "X/Camera", soundOverride: "Y")
        XCTAssertEqual(other.camera, preset.folderTemplate, "only the Netflix preset reads those fields")
        XCTAssertEqual(other.sound, preset.soundFolderTemplate)
    }

    func test_newBadge_onlyOnFoldersThatWillBeCreated() {
        XCTAssertTrue(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 0, name: "Day02", isNew: true)))
        XCTAssertTrue(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 1, name: "A001", isNew: true, role: .copiedFolder)))
        XCTAssertFalse(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 0, name: "Day02", isNew: false)))
        XCTAssertFalse(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 1, name: "clip.mov", isNew: true, role: .copiedFile)))
        XCTAssertFalse(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 1, name: "contents of A001", isNew: true, role: .contents)))
        XCTAssertFalse(FolderTreeLine.showsNewBadge(FolderTreeLine(depth: 1, name: "", isNew: true)))
    }
}

/// The tree writes through the film's own settings record, never into a shared preset.
@MainActor
final class FolderStructureWritingTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func test_filmOnOff_getsItsOwnRecord_andTheSeparateSoundFolderIsKept() throws {
        let storage = ConfigurationStorage(baseDirectory: dir)
        var film = BackupConfiguration()
        film.name = "Citizen K"
        storage.add(film)
        let editor = BackupEditorViewModel(config: film, storage: storage)
        let model = OrganizationEditorModel(viewModel: editor)
        XCTAssertEqual(model.folderStructure, FolderStructure(), "a film with no layout reads as empty")

        model.setFolderStructure(FolderStructure.startingPoints[1].structure)

        let id = try XCTUnwrap(editor.config.selectedOrganizationPresetId)
        let own = try XCTUnwrap(storage.organizationPresets.first { $0.id == id })
        XCTAssertEqual(own.ownerFilmId, film.id)
        XCTAssertTrue(own.useFolderTemplate)
        XCTAssertEqual(own.folderTemplate, "{movie}/{day}/Camera")
        XCTAssertEqual(own.soundFolderTemplate, "{movie}/{day}/Sound")
        XCTAssertEqual(model.folderStructure, FolderStructure.startingPoints[1].structure)
        XCTAssertTrue(FilmPresetOwnership.shared(storage.organizationPresets).isEmpty)

        // Emptying the tree switches the layout off instead of leaving an empty one on.
        model.setFolderStructure(FolderStructure())
        XCTAssertEqual(storage.organizationPresets.first { $0.id == id }?.useFolderTemplate, false)
    }

    func test_netflixFilm_treeEditsReachTheFieldsTheRunReads() throws {
        let storage = ConfigurationStorage(baseDirectory: dir)
        let film = BackupConfiguration()
        storage.add(film)
        let editor = BackupEditorViewModel(config: film, storage: storage)
        editor.applyNetflixIngestPreset()
        let model = OrganizationEditorModel(viewModel: editor)
        var structure = try XCTUnwrap(model.folderStructure)
        XCTAssertEqual(structure, FolderStructure.startingPoints[2].structure)

        structure.addFolder("RUSHES", inside: nil)
        model.setFolderStructure(structure)

        XCTAssertEqual(editor.config.cameraFolderTemplate,
                       "RUSHES/{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}")
        XCTAssertEqual(editor.config.soundFolderTemplate, "RUSHES/{date}_{episode}_{day}_{unit}/Sound_Media")
        XCTAssertEqual(model.folderStructure, structure)
    }
}
