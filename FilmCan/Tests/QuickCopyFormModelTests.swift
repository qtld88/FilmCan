import XCTest
@testable import FilmCan

final class QuickCopyFormModelTests: XCTestCase {

    // MARK: helpers
    private func dir(_ name: String, _ kind: SourceMediaKind = .camera) -> QuickCopyFormModel.Item {
        .init(path: "/Volumes/CARD/\(name)", isDirectory: true, kind: kind)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func folderPath(_ preset: OrganizationPreset, source: String, kind: SourceMediaKind,
                            day: String, project: String, on when: Date) -> String {
        OrganizationTemplate.resolve(
            preset: preset, sourcePath: source, destinationRoot: "/Volumes/SSD",
            counter: 0, date: when,
            metadata: ShootMetadata(episode: project, day: day), mediaKind: kind
        ).folderPath
    }

    // MARK: sanitizing
    func test_sanitizeName_spacesAndProhibitedChars() {
        XCTAssertEqual(QuickCopyFormModel.sanitizeName("Docu Truc"), "Docu_Truc")
        XCTAssertEqual(QuickCopyFormModel.sanitizeName("A/B:C"), "A_B_C")
        XCTAssertEqual(QuickCopyFormModel.sanitizeName("  x   y "), "x_y")
        XCTAssertEqual(QuickCopyFormModel.sanitizeName("   "), "")
    }

    // MARK: organization modes
    func test_none_hasNoRunPreset_andNoOrganization() {
        let form = QuickCopyFormModel(items: [dir("A001")])
        XCTAssertNil(form.runPreset())
        XCTAssertFalse(form.organizationActive)
    }

    func test_dateOnly_templates() throws {
        var form = QuickCopyFormModel(items: [dir("A001"), dir("ZOOM", .sound)])
        form.organization = .dateOnly
        let preset = try XCTUnwrap(form.runPreset())
        XCTAssertTrue(preset.useFolderTemplate)
        XCTAssertEqual(preset.folderTemplate, "{date}/Camera_Media")
        XCTAssertEqual(preset.soundFolderTemplate, "{date}/Sound_Media")
        let d = date(2026, 10, 14)
        XCTAssertEqual(folderPath(preset, source: "/x/A001", kind: .camera, day: "", project: "", on: d),
                       "20261014/Camera_Media")
        XCTAssertEqual(folderPath(preset, source: "/x/ZOOM", kind: .sound, day: "", project: "", on: d),
                       "20261014/Sound_Media")
    }

    func test_projectAndDay_templates_andEmptyDaySqueezes() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.organization = .projectAndDay
        form.project = "Docu Truc"
        form.day = "itw Machin"
        let preset = try XCTUnwrap(form.runPreset())
        let d = date(2026, 10, 14)
        XCTAssertEqual(folderPath(preset, source: "/x/A001", kind: .camera,
                                  day: form.sanitizedDay, project: form.sanitizedProject, on: d),
                       "20261014_Docu_Truc_itw_Machin/Camera_Media")
        form.day = ""
        XCTAssertEqual(folderPath(preset, source: "/x/A001", kind: .camera,
                                  day: form.sanitizedDay, project: form.sanitizedProject, on: d),
                       "20261014_Docu_Truc/Camera_Media")
    }

    func test_pickedDate_setsCustomDateOnRunPreset_only() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.organization = .dateOnly
        XCTAssertFalse(try XCTUnwrap(form.runPreset()).useCustomDate)
        let picked = date(2026, 3, 2)
        form.pickedDate = picked
        let preset = try XCTUnwrap(form.runPreset())
        XCTAssertTrue(preset.useCustomDate)
        XCTAssertEqual(preset.customDate, picked)
    }

    // MARK: saved preset
    private func netflixLike(projectName: String = "") -> OrganizationPreset {
        var p = OrganizationPreset()
        p.name = "Netflix Ingest"
        p.useFolderTemplate = true
        p.folderTemplate = "{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"
        p.soundFolderTemplate = "{date}_{episode}_{day}_{unit}/Sound_Media"
        p.projectName = projectName
        return p
    }

    func test_savedPreset_fieldVisibility() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        let withName = netflixLike(projectName: "Show")
        let noName = netflixLike()
        form.savedPresets = [withName, noName]

        form.selectedPresetId = noName.id
        XCTAssertTrue(form.organizationActive)
        XCTAssertTrue(form.showsProjectField)
        XCTAssertTrue(form.showsDayField)

        form.selectedPresetId = withName.id
        XCTAssertFalse(form.showsProjectField)
        XCTAssertEqual(form.sanitizedProject, "Show")
    }

    func test_savedPreset_askPolicyMapsToSkip() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        var p = netflixLike()
        p.duplicatePolicy = .ask
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        XCTAssertEqual(form.effectiveDuplicatePolicy, .skip)
        XCTAssertTrue(form.duplicatePolicyWasMapped)
    }

    func test_savedPreset_pickedDateAppliedToCopy_notToStoredPreset() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        let p = netflixLike()
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.pickedDate = date(2026, 1, 5)
        let run = try XCTUnwrap(form.runPreset())
        XCTAssertTrue(run.useCustomDate)
        XCTAssertFalse(form.savedPresets[0].useCustomDate)
    }

    // MARK: temporary configuration
    func test_makeConfiguration_noPreset() {
        var form = QuickCopyFormModel(items: [dir("A001"), dir("ZOOM", .sound)])
        form.destinations = ["/Volumes/SSD1", "/Volumes/SSD2"]
        form.verification = .paranoid
        form.duplicatePolicy = .overwrite
        form.copyFolderContents = true
        form.organization = .projectAndDay
        form.project = "Docu Truc"
        form.day = "itw/1"
        let c = form.makeConfiguration()
        XCTAssertEqual(c.name, "Quick Copy — A001")
        XCTAssertEqual(c.sourcePaths, ["/Volumes/CARD/A001", "/Volumes/CARD/ZOOM"])
        XCTAssertEqual(c.destinationPaths, ["/Volumes/SSD1", "/Volumes/SSD2"])
        XCTAssertEqual(c.sourceMediaKinds["/Volumes/CARD/ZOOM"], .sound)
        XCTAssertEqual(c.sourceMediaKinds["/Volumes/CARD/A001"], .camera)
        XCTAssertEqual(c.episode, "Docu_Truc")
        XCTAssertEqual(c.day, "itw_1")
        XCTAssertEqual(c.engineOptions.verificationMode, .paranoid)
        XCTAssertEqual(c.duplicatePolicy, .overwrite)
        XCTAssertTrue(c.copyFolderContents)
        XCTAssertTrue(c.logEnabled)
        XCTAssertEqual(c.hashListStyle, .ascMHL)
        XCTAssertNil(c.selectedOrganizationPresetId)
    }

    func test_makeConfiguration_withPreset_usesPresetValues() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        var p = netflixLike(projectName: "Show")
        p.engineOptions.verificationMode = .off
        p.duplicatePolicy = .increment
        p.copyFolderContents = true
        p.hashListStyle = .simpleHidden
        p.runInParallel = true
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.destinations = ["/Volumes/SSD"]
        form.verification = .paranoid   // ignored: preset wins
        let c = form.makeConfiguration()
        XCTAssertTrue(c.runInParallel)
        XCTAssertEqual(c.selectedOrganizationPresetId, p.id)
        XCTAssertEqual(c.engineOptions.verificationMode, .off)
        XCTAssertEqual(c.duplicatePolicy, .increment)
        XCTAssertTrue(c.copyFolderContents)
        XCTAssertEqual(c.hashListStyle, .simpleHidden)
        XCTAssertEqual(c.episode, "Show")
    }

    // MARK: Run blockers
    func test_blockers() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.pathExists = { _ in true }
        XCTAssertEqual(form.blocker, .noDestination)
        XCTAssertFalse(form.canRun)

        form.destinations = ["/Volumes/SSD"]
        XCTAssertNil(form.blocker)
        XCTAssertTrue(form.canRun)

        form.pathExists = { $0 != "/Volumes/SSD" }
        XCTAssertEqual(form.blocker, .missingDestination("/Volumes/SSD"))

        form.pathExists = { _ in true }
        form.organization = .projectAndDay
        XCTAssertEqual(form.blocker, .missingProject)
        form.project = "Docu"
        XCTAssertNil(form.blocker)
    }

    func test_blocker_twoLooseFiles_butFoldersAreFine() {
        let f1 = QuickCopyFormModel.Item(path: "/x/a.mov", isDirectory: false, kind: .camera)
        let f2 = QuickCopyFormModel.Item(path: "/x/b.mov", isDirectory: false, kind: .camera)
        var form = QuickCopyFormModel(items: [f1, dir("A001")])
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { _ in true }
        XCTAssertNil(form.blocker)                 // one loose file + a folder
        form.items = [f1, f2]
        XCTAssertEqual(form.blocker, .multipleFiles)
    }

    func test_blocker_presetWithEpisodeToken_needsProject() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        let p = netflixLike()          // {episode} in template, empty projectName
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { _ in true }
        XCTAssertEqual(form.blocker, .missingProject)
        form.project = "Docu"
        XCTAssertNil(form.blocker)

        let named = netflixLike(projectName: "Show")
        form.savedPresets = [named]
        form.selectedPresetId = named.id
        form.project = ""
        XCTAssertNil(form.blocker)     // preset supplies the project name
    }

    func test_blocker_prohibitedRollName_onlyUnderNetflixPreset() {
        let bad = QuickCopyFormModel.Item(path: "/Volumes/CARD/A@001", isDirectory: true, kind: .camera)
        var form = QuickCopyFormModel(items: [bad])
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { _ in true }
        XCTAssertNil(form.blocker)     // Preset = None: no Netflix rules

        var p = netflixLike(projectName: "Show")
        p.name = OrganizationPreset.netflixIngestName
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        XCTAssertEqual(form.blocker, .invalidRollName("A@001"))
        XCTAssertTrue(form.blocker?.message.contains("A@001") == true)
        XCTAssertTrue(form.blocker?.message.contains("@") == true)

        var other = p
        other.name = "Something else"
        form.savedPresets = [other]
        form.selectedPresetId = other.id
        XCTAssertNil(form.blocker)
    }

    // MARK: Save as preset
    func test_makeSavedPreset_contents_noDateStored() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.organization = .projectAndDay
        form.project = "Docu Truc"
        form.verification = .paranoid
        form.duplicatePolicy = .verify
        form.copyFolderContents = true
        form.pickedDate = date(2026, 3, 2)
        form.savePresetName = "  Docu  "
        let p = try XCTUnwrap(form.makeSavedPreset())
        XCTAssertEqual(p.name, "Docu")
        XCTAssertEqual(p.engineOptions.verificationMode, .paranoid)
        XCTAssertEqual(p.duplicatePolicy, .verify)
        XCTAssertTrue(p.copyFolderContents)
        XCTAssertTrue(p.logEnabled)
        XCTAssertEqual(p.hashListStyle, .ascMHL)
        XCTAssertEqual(p.projectName, "Docu_Truc")
        XCTAssertTrue(p.useFolderTemplate)
        XCTAssertEqual(p.folderTemplate, QuickCopyFormModel.projectCameraTemplate)
        XCTAssertEqual(p.soundFolderTemplate, QuickCopyFormModel.projectSoundTemplate)
        XCTAssertFalse(p.useCustomDate)
    }

    func test_makeSavedPreset_nilWhenNameEmptyOrPresetSelected() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        XCTAssertNil(form.makeSavedPreset())
        form.savePresetName = "X"
        let p = netflixLike()
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        XCTAssertNil(form.makeSavedPreset())
    }

    func test_makeSavedPreset_noOrganization_hasNoTemplate() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.savePresetName = "Plain"
        let p = try XCTUnwrap(form.makeSavedPreset())
        XCTAssertFalse(p.useFolderTemplate)
        XCTAssertEqual(p.folderTemplate, "")
        XCTAssertEqual(p.projectName, "")
    }

    // MARK: Summary line
    func test_presetSummary_mentionsMappedAsk() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        var p = netflixLike()
        p.duplicatePolicy = .ask
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        let summary = form.presetSummary ?? ""
        XCTAssertTrue(summary.contains("Fast"), summary)
        XCTAssertTrue(summary.contains("Skip"), summary)
        XCTAssertTrue(summary.contains("Ask each time"), summary)
        form.selectedPresetId = nil
        XCTAssertNil(form.presetSummary)
    }

    // MARK: Folder tree preview
    private func previewForm() -> QuickCopyFormModel {
        var form = QuickCopyFormModel(items: [dir("A001"), dir("ZOOM_F8", .sound)])
        form.organization = .projectAndDay
        form.project = "Docu Truc"
        form.day = "itw"
        form.today = date(2026, 10, 14)
        form.pathExists = { _ in false }
        return form
    }

    func test_treePreview_projectAndDay() {
        let lines = previewForm().treePreview(for: "/Volumes/SSD")
        XCTAssertEqual(lines.map(\.name), [
            "20261014_Docu_Truc_itw", "Camera_Media", "A001", "Sound_Media", "ZOOM_F8"])
        XCTAssertEqual(lines.map(\.depth), [0, 1, 2, 1, 2])
        XCTAssertTrue(lines.allSatisfy(\.isNew))
    }

    func test_treePreview_marksExistingFolderNotNew() {
        var form = previewForm()
        form.pathExists = { $0 == "/Volumes/SSD/20261014_Docu_Truc_itw" }
        let lines = form.treePreview(for: "/Volumes/SSD")
        XCTAssertFalse(lines[0].isNew)
        XCTAssertTrue(lines[1].isNew)
    }

    func test_treePreview_noOrganization_isJustTheRoll() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.pathExists = { _ in false }
        let lines = form.treePreview(for: "/Volumes/SSD")
        XCTAssertEqual(lines.map(\.name), ["A001"])
    }

    func test_treePreview_copyContents_showsFlatContentsAndHashListFolder() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.copyFolderContents = true
        form.organization = .dateOnly
        form.today = date(2026, 10, 14)
        form.pathExists = { _ in false }
        let lines = form.treePreview(for: "/Volumes/SSD")
        XCTAssertEqual(lines.map(\.name), [
            "20261014", "Camera_Media", "contents of A001", "A001 (hash list only)"])
        XCTAssertEqual(lines.map(\.depth), [0, 1, 2, 2])
        XCTAssertTrue(lines.allSatisfy(\.isNew))

        form.pathExists = { $0 == "/Volumes/SSD/20261014/Camera_Media/A001" }
        let existing = form.treePreview(for: "/Volumes/SSD")
        XCTAssertTrue(existing[2].isNew)
        XCTAssertFalse(existing[3].isNew)
    }

    func test_revealPath_isTopCreatedFolder() {
        XCTAssertEqual(previewForm().revealPath(for: "/Volumes/SSD"),
                       "/Volumes/SSD/20261014_Docu_Truc_itw")
        let plain = QuickCopyFormModel(items: [dir("A001")])
        XCTAssertEqual(plain.revealPath(for: "/Volumes/SSD"), "/Volumes/SSD/A001")
    }

    // MARK: Review fixes
    func test_sanitizedProject_hiddenFieldIgnoresStaleTypedValue() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.project = "Foo"
        XCTAssertEqual(form.sanitizedProject, "Foo")
        let named = netflixLike(projectName: "Show")
        form.savedPresets = [named]
        form.selectedPresetId = named.id
        XCTAssertFalse(form.showsProjectField)
        XCTAssertEqual(form.sanitizedProject, "Show")
    }

    func test_sanitizedProject_visibleFieldUsesTypedValue() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        let unnamed = netflixLike()
        form.savedPresets = [unnamed]
        form.selectedPresetId = unnamed.id
        form.project = "Foo"
        XCTAssertTrue(form.showsProjectField)
        XCTAssertEqual(form.sanitizedProject, "Foo")
    }

    func test_runPreset_storedUseCustomDateIgnoredWithoutPickedDate() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        var p = netflixLike()
        p.useCustomDate = true
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        let run = try XCTUnwrap(form.runPreset())
        XCTAssertFalse(run.useCustomDate)
        XCTAssertTrue(form.savedPresets[0].useCustomDate)
    }

    func test_blocker_noSources() {
        var form = QuickCopyFormModel(items: [])
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { _ in true }
        XCTAssertEqual(form.blocker, .noSources)
    }

    func test_revealPath_contentsMode_noOrganization_isDestination() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.copyFolderContents = true
        XCTAssertEqual(form.revealPath(for: "/Volumes/SSD"), "/Volumes/SSD")
    }

    func test_showsDayField_falseWhenTemplatesHaveNoDayToken() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        var p = netflixLike()
        p.folderTemplate = "{date}/Camera_Media"
        p.soundFolderTemplate = "{date}/Sound_Media"
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        XCTAssertTrue(form.organizationActive)
        XCTAssertFalse(form.showsDayField)
    }

    func test_makeSavedPreset_dateOnly() throws {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.savePresetName = "By date"
        form.organization = .dateOnly
        let p = try XCTUnwrap(form.makeSavedPreset())
        XCTAssertTrue(p.useFolderTemplate)
        XCTAssertEqual(p.folderTemplate, "{date}/Camera_Media")
        XCTAssertEqual(p.soundFolderTemplate, "{date}/Sound_Media")
        XCTAssertEqual(p.projectName, "")
    }

    // MARK: gate feedback (2026-11-03)
    private func cameraOnlyPreset() -> OrganizationPreset {
        var p = OrganizationPreset()
        p.name = "DCM"
        p.useFolderTemplate = true
        p.folderTemplate = "DCM_{day}_{date}/Camera_Media"
        return p
    }

    func test_presetWithoutSoundTemplate_sendsSoundToSoundMedia() throws {
        var form = QuickCopyFormModel(items: [dir("261103_", .sound)])
        let p = cameraOnlyPreset()
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.today = date(2026, 11, 3)
        form.day = "J07"
        XCTAssertTrue(form.showsMediaKind)
        XCTAssertEqual(form.relativePaths(for: "/Volumes/SSD"), ["DCM_J07_20261103/Sound_Media/261103_"])
        XCTAssertEqual(form.savedPresets[0].soundFolderTemplate, "", "stored preset untouched")
    }

    func test_presetWithoutMediaFolder_requiresTypedNamePerKind() {
        var form = QuickCopyFormModel(items: [dir("A001"), dir("ZOOM", .sound)])
        var p = cameraOnlyPreset()
        p.folderTemplate = "{date}"
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { $0 == "/Volumes/SSD" }
        form.today = date(2026, 11, 3)
        XCTAssertTrue(form.showsMediaKind)
        XCTAssertTrue(form.lacksMediaFolder)
        XCTAssertEqual(form.blocker, .missingMediaFolder(.camera))
        let missing = form.treePreview(for: "/Volumes/SSD").filter { $0.mediaKind != nil }
        XCTAssertEqual(missing.map(\.name), ["", ""])
        form.mediaFolderNames[.camera] = "Cam"
        XCTAssertEqual(form.blocker, .missingMediaFolder(.sound))
        form.mediaFolderNames[.sound] = "Son Pro"
        XCTAssertNil(form.blocker)
        XCTAssertEqual(form.relativePaths(for: "/Volumes/SSD"),
                       ["20261103/Cam/A001", "20261103/Son_Pro/ZOOM"])
        let named = form.treePreview(for: "/Volumes/SSD").filter { $0.mediaKind != nil }
        XCTAssertEqual(named.map(\.name), ["Cam", "Son_Pro"])
        XCTAssertEqual(named.map(\.depth), [1, 1])
    }

    func test_rootFolderName_prefilledThenOverridesBothTemplates() {
        var form = QuickCopyFormModel(items: [dir("A001"), dir("ZOOM", .sound)])
        form.organization = .dateOnly
        form.today = date(2026, 11, 3)
        XCTAssertEqual(form.defaultRootFolderName, "20261103")
        form.rootFolderName = "DCM J07 {x}"
        XCTAssertEqual(form.relativePaths(for: "/Volumes/SSD"),
                       ["DCM_J07_x/Camera_Media/A001", "DCM_J07_x/Sound_Media/ZOOM"])
        XCTAssertEqual(form.defaultRootFolderName, "20261103")
        XCTAssertEqual(form.copyFolders(for: "/Volumes/SSD"),
                       ["/Volumes/SSD/DCM_J07_x/Camera_Media", "/Volumes/SSD/DCM_J07_x/Sound_Media"])
    }

    func test_rootFolderName_satisfiesMissingProject() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.destinations = ["/Volumes/SSD"]
        form.pathExists = { _ in true }
        form.organization = .projectAndDay
        XCTAssertEqual(form.blocker, .missingProject)
        form.rootFolderName = "Docu"
        XCTAssertNil(form.blocker)
        form.rootFolderName = "   "
        XCTAssertEqual(form.blocker, .missingProject)
    }

    func test_copyFolders_noOrganization_isDestination() {
        let form = QuickCopyFormModel(items: [dir("A001")])
        XCTAssertEqual(form.copyFolders(for: "/Volumes/SSD"), ["/Volumes/SSD"])
    }

    func test_mediaFolderRename_replacesOnlyThatKindsFolder() {
        var form = previewForm()
        XCTAssertEqual(form.defaultMediaFolderName(for: .camera), "Camera_Media")
        XCTAssertEqual(form.defaultMediaFolderName(for: .sound), "Sound_Media")
        form.setFolderName("Cam A", root: false, kind: .camera)
        XCTAssertEqual(form.relativePaths(for: "/Volumes/SSD"),
                       ["20261014_Docu_Truc_itw/Cam_A/A001", "20261014_Docu_Truc_itw/Sound_Media/ZOOM_F8"])
        XCTAssertTrue(form.isFolderNameEdited(root: false, kind: .camera))
        XCTAssertFalse(form.isFolderNameEdited(root: false, kind: .sound))
        form.setFolderName("Camera_Media", root: false, kind: .camera)
        XCTAssertNil(form.mediaFolderNames[.camera], "typing the suggestion back clears the override")
    }

    func test_treePreview_marksRootAndMediaFoldersEditable() {
        let lines = previewForm().treePreview(for: "/Volumes/SSD")
        XCTAssertEqual(lines.map(\.isRoot), [true, false, false, false, false])
        XCTAssertEqual(lines.map(\.mediaKind), [nil, .camera, nil, .sound, nil])
    }

    func test_netflixTemplate_mediaFolderIsCameraMediaNotFormat() {
        XCTAssertEqual(QuickCopyFormModel.mediaComponentIndex(
            in: "{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}", kind: .camera), 1)
        XCTAssertEqual(QuickCopyFormModel.replacingComponent(
            1, of: "{date}/Camera_Media/{cameraFormat}", with: "CAM"), "{date}/CAM/{cameraFormat}")
    }

    // MARK: folder vs contents from the preview (2026-11-05)
    func test_copyModeOverride_flipsTreeAndConfig_withoutTouchingPreset() {
        var p = OrganizationPreset()
        p.name = "P"
        p.copyFolderContents = true
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.savedPresets = [p]
        form.selectedPresetId = p.id
        form.destinations = ["/Volumes/SSD"]
        XCTAssertTrue(form.treePreview(for: "/Volumes/SSD").contains { $0.role == .contents })

        form.setCopyFolderContents(false)
        XCTAssertEqual(form.copyFolderContentsOverride, false)
        let lines = form.treePreview(for: "/Volumes/SSD")
        XCTAssertEqual(lines.last?.role, .copiedFolder)
        XCTAssertFalse(lines.contains { $0.role == .contents || $0.role == .hashListOnly })
        XCTAssertFalse(form.makeConfiguration().copyFolderContents)
        XCTAssertTrue(form.savedPresets[0].copyFolderContents)

        form.setCopyFolderContents(true)
        XCTAssertNil(form.copyFolderContentsOverride)
    }

    func test_copyModeWithoutPreset_editsBasicOption() {
        var form = QuickCopyFormModel(items: [dir("A001")])
        form.setCopyFolderContents(true)
        XCTAssertTrue(form.copyFolderContents)
        XCTAssertNil(form.copyFolderContentsOverride)
    }
}
