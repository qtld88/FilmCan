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
}
