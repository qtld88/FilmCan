import XCTest
@testable import FilmCan

final class MainScreenSummaryTests: XCTestCase {

    // MARK: - Shoot-day stepper

    func testStepKeepsPrefixAndWidth() {
        XCTAssertEqual(ShootDayStepper.step("Day02", by: 1), "Day03")
        XCTAssertEqual(ShootDayStepper.step("Day02", by: -1), "Day01")
        XCTAssertEqual(ShootDayStepper.step("D9", by: 1), "D10")
        XCTAssertEqual(ShootDayStepper.step("Day099", by: 1), "Day100")
        XCTAssertEqual(ShootDayStepper.step("Day100", by: -1), "Day099")
        XCTAssertEqual(ShootDayStepper.step("7", by: 1), "8")
        XCTAssertEqual(ShootDayStepper.step("J 04", by: 1), "J 05")
    }

    func testStepNeverGoesBelowOne() {
        XCTAssertEqual(ShootDayStepper.step("Day01", by: -1), "Day01")
        XCTAssertFalse(ShootDayStepper.canStepBack("Day01"))
        XCTAssertTrue(ShootDayStepper.canStepBack("Day02"))
    }

    func testStepOnEmptyOrTextOnlyDay() {
        XCTAssertEqual(ShootDayStepper.step("", by: 1), "Day01")
        XCTAssertEqual(ShootDayStepper.step("", by: -1), "")
        XCTAssertEqual(ShootDayStepper.step("Pickups", by: 1), "Pickups")
        XCTAssertFalse(ShootDayStepper.canStepForward("Pickups"))
        XCTAssertFalse(ShootDayStepper.canStepBack(""))
        XCTAssertTrue(ShootDayStepper.canStepForward(""))
    }

    /// Stepping forward agrees with the automatic day counter on a new calendar day.
    func testStepForwardMatchesTheDayCounter() {
        let cal = Calendar(identifier: .gregorian)
        let yesterday = Date(timeIntervalSince1970: 1_700_000_000)
        let today = yesterday.addingTimeInterval(86_400 * 2)
        for day in ["Day01", "D9", "Day099", "3"] {
            XCTAssertEqual(ShootDayStepper.step(day, by: 1),
                           ShootDayCounter.advance(day: day, lastRun: yesterday, now: today, calendar: cal))
        }
    }

    func testDayShownOnlyWhenTheFilmUsesIt() {
        XCTAssertFalse(ShootDayStepper.usesShootDay(nil))
        var preset = OrganizationPreset()
        preset.useFolderTemplate = true
        preset.folderTemplate = "PROJ/{date}/{source}"
        XCTAssertFalse(ShootDayStepper.usesShootDay(preset))
        preset.folderTemplate = "PROJ/{day}/{source}"
        XCTAssertTrue(ShootDayStepper.usesShootDay(preset))
        preset.useFolderTemplate = false
        XCTAssertFalse(ShootDayStepper.usesShootDay(preset), "an unused template does not count")
        preset.useFolderTemplate = true
        preset.folderTemplate = "PROJ/{source}"
        preset.soundFolderTemplate = "PROJ/{day}/Sound"
        XCTAssertTrue(ShootDayStepper.usesShootDay(preset))
        preset.soundFolderTemplate = ""
        preset.useRenameTemplate = true
        preset.renameTemplate = "{day}_{filename}"
        XCTAssertTrue(ShootDayStepper.usesShootDay(preset))
    }

    func testNetflixPresetShowsTheDay() {
        XCTAssertTrue(ShootDayStepper.usesShootDay(OrganizationPreset.netflixIngest()))
    }

    // MARK: - Summary line

    func testSummaryForOneCard() throws {
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: ["CITIZENK/Day02/A003"], totalBytes: 128_000_000_000, itemCount: 412,
            driveCount: 2, isLoading: false))
        XCTAssertEqual(s.breadcrumb, ["CITIZENK", "Day02", "A003"])
        XCTAssertTrue(s.detail.hasSuffix(" · 412 files · 2 drives"), s.detail)
        XCTAssertTrue(s.detail.contains("GB"), s.detail)
    }

    func testSummaryForSeveralCardsKeepsTheSharedFolders() throws {
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: ["P/Day02/Camera_Media/A003", "P/Day02/Camera_Media/A004", "P/Day02/Sound_Media/S001"],
            totalBytes: 1, itemCount: nil, driveCount: 1, isLoading: false))
        XCTAssertEqual(s.breadcrumb, ["P", "Day02", "3 items"])
        XCTAssertTrue(s.detail.hasSuffix(" · 1 drive"), s.detail)
        XCTAssertFalse(s.detail.contains("files"))
    }

    func testSummaryNeverTreatsACopiedItemAsASharedFolder() throws {
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: ["A001", "A001/extra"], totalBytes: 0, itemCount: 2, driveCount: 0, isLoading: false))
        XCTAssertEqual(s.breadcrumb, ["2 items"])
    }

    func testSummaryWithoutOrganisationIsJustTheItem() throws {
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: ["A001"], totalBytes: 0, itemCount: 1, driveCount: 1, isLoading: false))
        XCTAssertEqual(s.breadcrumb, ["A001"])
        XCTAssertTrue(s.detail.contains("1 file"))
        XCTAssertFalse(s.detail.contains("1 files"))
    }

    func testSummaryWhileMeasuringAndWithoutDrive() throws {
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: ["A001"], totalBytes: 0, itemCount: nil, driveCount: 0, isLoading: true))
        XCTAssertEqual(s.detail, "Measuring…")
    }

    func testNoSummaryWithoutSources() {
        XCTAssertNil(BackupSummary.make(relativePaths: [], totalBytes: 0, itemCount: nil, driveCount: 2, isLoading: false))
    }

    /// The breadcrumb is the engine's own destination path for the roll.
    func testSummaryFollowsTheEnginePathFunction() throws {
        var preset = OrganizationPreset()
        preset.useFolderTemplate = true
        preset.folderTemplate = "CITIZENK/{day}"
        var options = FolderTreeBuilder.Options()
        options.preset = preset
        options.organizationActive = true
        options.metadata = ShootMetadata(episode: "", day: "Day02", unit: "", cameraFormat: "")
        let rels = FolderTreeBuilder.relativePaths(
            for: "/Volumes/SSD", sources: [.init(path: "/Volumes/A003", isDirectory: true)], options: options)
        let s = try XCTUnwrap(BackupSummary.make(
            relativePaths: rels, totalBytes: 0, itemCount: nil, driveCount: 1, isLoading: false))
        XCTAssertEqual(s.breadcrumb.first, "CITIZENK")
        XCTAssertTrue(s.breadcrumb.contains("Day02"))
        XCTAssertEqual(s.breadcrumb.last, "A003")
    }

    // MARK: - Run subtitle

    func testRunSubtitleSaysWhatIsMissingFirst() {
        XCTAssertEqual(RunSubtitle.text(sourceCount: 0, driveCount: 0, newFolderCount: 0, isRunning: false),
                       "Add a card or a folder to copy")
        XCTAssertEqual(RunSubtitle.text(sourceCount: 1, driveCount: 0, newFolderCount: 0, isRunning: false),
                       "Add a drive to save to")
    }

    func testRunSubtitleCountsNewFolders() {
        XCTAssertEqual(RunSubtitle.text(sourceCount: 1, driveCount: 2, newFolderCount: 1, isRunning: false),
                       "1 folder will be created")
        XCTAssertEqual(RunSubtitle.text(sourceCount: 1, driveCount: 2, newFolderCount: 3, isRunning: false),
                       "3 folders will be created")
        XCTAssertEqual(RunSubtitle.text(sourceCount: 1, driveCount: 2, newFolderCount: 0, isRunning: false),
                       "Folders already exist: only missing files are copied")
        XCTAssertEqual(RunSubtitle.text(sourceCount: 1, driveCount: 2, newFolderCount: 3, isRunning: true),
                       "Backup in progress")
    }

    func testNewFolderCountIgnoresFilesExistingFoldersAndUnnamedLines() {
        let lines = [
            FolderTreeLine(depth: 0, name: "P", isNew: false),
            FolderTreeLine(depth: 1, name: "Day02", isNew: true),
            FolderTreeLine(depth: 2, name: "A003", isNew: true, role: .copiedFolder),
            FolderTreeLine(depth: 2, name: "clip.mov", isNew: true, role: .copiedFile),
            FolderTreeLine(depth: 2, name: "contents of X", isNew: true, role: .contents),
            FolderTreeLine(depth: 1, name: "", isNew: true, mediaKind: .camera),
        ]
        XCTAssertEqual(RunSubtitle.newFolderCount(in: lines), 2)
    }

    // MARK: - Chrome

    func testPathLineHiddenOnlyForAWholeDrive() {
        XCTAssertFalse(MainScreenChrome.showsPathLine(for: "/Volumes/A003"))
        XCTAssertFalse(MainScreenChrome.showsPathLine(for: "/Volumes/A003/"))
        XCTAssertTrue(MainScreenChrome.showsPathLine(for: "/Volumes/A003/DCIM"))
        XCTAssertTrue(MainScreenChrome.showsPathLine(for: "/Users/me/Footage/A003"))
        XCTAssertTrue(MainScreenChrome.showsPathLine(for: "/Volumes"))
    }

    func testOrderNumbersOnlyWithSeveralRows() {
        XCTAssertTrue(MainScreenChrome.displayNumbers(for: ["a"], isIncluded: { _ in true }).isEmpty)
        XCTAssertEqual(MainScreenChrome.displayNumbers(for: ["a", "b", "c"], isIncluded: { $0 != "b" }),
                       ["a": 1, "c": 2])
    }

    func testTreeCollapsesOnlyWhenNothingIsNew() {
        let old = FolderTreeLine(depth: 0, name: "P", isNew: false)
        let new = FolderTreeLine(depth: 1, name: "Day02", isNew: true)
        XCTAssertTrue(MainScreenChrome.treeStartsCollapsed([old]))
        XCTAssertFalse(MainScreenChrome.treeStartsCollapsed([old, new]))
        XCTAssertFalse(MainScreenChrome.treeStartsCollapsed([]))
    }
}

@MainActor
final class ShootDayHeaderTests: XCTestCase {
    /// Counter off: the header edits the film's own day, like the field in Options.
    func testHeaderSetsTheFilmDayWhenTheCounterIsOff() {
        var config = BackupConfiguration()
        config.day = "Day02"
        let vm = BackupEditorViewModel(config: config)
        vm.setShootDayFromHeader(ShootDayStepper.step(vm.effectiveShootDay(), by: 1))
        XCTAssertEqual(vm.config.day, "Day03")
        XCTAssertEqual(vm.effectiveShootDay(), "Day03")
    }

    func testHeaderIgnoresBlankAndUnchangedValues() {
        var config = BackupConfiguration()
        config.day = "Day02"
        let vm = BackupEditorViewModel(config: config)
        vm.setShootDayFromHeader("  ")
        vm.setShootDayFromHeader("Day02")
        XCTAssertEqual(vm.config.day, "Day02")
    }
}
