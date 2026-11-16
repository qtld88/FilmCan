import XCTest
@testable import FilmCan

final class ReportArchiveTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("ReportArchive-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        suiteName = "ReportArchiveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// One destination with roll A001 (ASC MHL, two generations) and roll S001 (simple list).
    private func makeResult() throws -> (TransferResult, pdf: URL) {
        let dest = tmp.appendingPathComponent("SSD-A")
        let a001 = dest.appendingPathComponent("Proj/A001")
        try write("clip", to: a001.appendingPathComponent("C001.mov"))
        try write("gen1", to: a001.appendingPathComponent("ascmhl/0001_A001_2026-11-10_100000Z.mhl"))
        try write("gen2", to: a001.appendingPathComponent("ascmhl/0002_A001_2026-11-11_100000Z.mhl"))
        let s001 = dest.appendingPathComponent("Proj/S001")
        try write("wav", to: s001.appendingPathComponent("T001.wav"))
        try write("simple", to: dest.appendingPathComponent(".filmcan/hashlists/S001.mhl"))
        let pdf = dest.appendingPathComponent("transfer_20261111_report.pdf")
        try write("%PDF", to: pdf)

        var destResult = DestResult(destinationPath: dest.path, displayName: "SSD-A")
        destResult.success = true
        destResult.rollFolders = ["/Volumes/A001": a001.path, "/Volumes/S001": s001.path]
        var result = TransferResult(configurationName: "Proj", destination: dest.path,
                                    startTime: date(2026, 11, 11), endTime: date(2026, 11, 11), success: true)
        result.destinationResults = [destResult]
        return (result, pdf)
    }

    // MARK: - Preferences

    func testEnabledByDefaultAndCanBeSwitchedOff() {
        XCTAssertTrue(ReportArchive.isEnabled(defaults: defaults))
        defaults.set(false, forKey: ReportArchive.DefaultsKey.enabled)
        XCTAssertFalse(ReportArchive.isEnabled(defaults: defaults))
    }

    func testDefaultFolderIsDocumentsFilmCanReports() {
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(ReportArchive.baseURL(defaults: defaults, home: home).path,
                       "/Users/someone/Documents/FilmCan Reports")
    }

    func testCustomFolderWinsAndBlankFallsBack() {
        let home = URL(fileURLWithPath: "/Users/someone")
        defaults.set("/Volumes/Sync/Reports", forKey: ReportArchive.DefaultsKey.folder)
        XCTAssertEqual(ReportArchive.baseURL(defaults: defaults, home: home).path, "/Volumes/Sync/Reports")
        defaults.set("   ", forKey: ReportArchive.DefaultsKey.folder)
        XCTAssertEqual(ReportArchive.baseURL(defaults: defaults, home: home).path,
                       "/Users/someone/Documents/FilmCan Reports")
    }

    // MARK: - Layout

    func testSafeName() {
        XCTAssertEqual(ReportArchive.safeName("Citizen K", fallback: "x"), "Citizen K")
        XCTAssertEqual(ReportArchive.safeName("A/B:C", fallback: "x"), "A-B-C")
        XCTAssertEqual(ReportArchive.safeName("  ", fallback: "x"), "x")
        XCTAssertEqual(ReportArchive.safeName("..", fallback: "x"), "x")
        XCTAssertEqual(ReportArchive.safeName(".hidden", fallback: "x"), "hidden")
        XCTAssertEqual(ReportArchive.safeName("../../etc", fallback: "x"), "-..-etc")
    }

    func testDayFolderUsesShootDayElseDate() {
        let d = date(2026, 3, 7)
        XCTAssertEqual(ReportArchive.dayFolderName(day: "Day05", date: d, calendar: utc), "Day05")
        XCTAssertEqual(ReportArchive.dayFolderName(day: "", date: d, calendar: utc), "2026-03-07")
        XCTAssertEqual(ReportArchive.dayFolderName(day: " ", date: d, calendar: utc), "2026-03-07")
    }

    func testFolderIsFilmThenDayThenDrive() {
        let url = ReportArchive.folder(
            base: URL(fileURLWithPath: "/R"), film: "Citizen K", day: "Day02",
            date: date(2026, 1, 1), drive: "SSD-A", calendar: utc)
        XCTAssertEqual(url.path, "/R/Citizen K/Day02/SSD-A")
    }

    func testFolderNeverEscapesTheBase() {
        let url = ReportArchive.folder(
            base: URL(fileURLWithPath: "/R"), film: "../..", day: "/etc", date: date(2026, 1, 1),
            drive: "..", calendar: utc)
        XCTAssertTrue(url.standardizedFileURL.path.hasPrefix("/R/"))
        XCTAssertEqual(url.pathComponents.count, 5)
    }

    func testHashListFileNameIsPrefixedOnlyWhenNeeded() {
        XCTAssertEqual(ReportArchive.hashListFileName(roll: "S001", original: "S001.mhl"), "S001.mhl")
        XCTAssertEqual(ReportArchive.hashListFileName(roll: "A001", original: "0002_A001_2026.mhl"), "0002_A001_2026.mhl")
        XCTAssertEqual(ReportArchive.hashListFileName(roll: "CARD", original: "0001_x.mhl"), "CARD_0001_x.mhl")
    }

    // MARK: - What to copy

    func testHashListsPicksLatestGenerationAndSimpleList() throws {
        let (result, _) = try makeResult()
        let lists = ReportArchive.hashLists(for: result)
        XCTAssertEqual(lists.map(\.roll), ["A001", "S001"])
        XCTAssertEqual(lists[0].url.lastPathComponent, "0002_A001_2026-11-11_100000Z.mhl")
        XCTAssertEqual(lists[1].url.lastPathComponent, "S001.mhl")
    }

    /// A roll holding both kinds: the film's current style decides.
    func testHashListsFollowTheFilmStyleWhenBothExist() throws {
        let (result, _) = try makeResult()
        try write("simpleA", to: tmp.appendingPathComponent("SSD-A/.filmcan/hashlists/A001.mhl"))
        XCTAssertEqual(ReportArchive.hashLists(for: result, style: .ascMHL)[0].url.lastPathComponent,
                       "0002_A001_2026-11-11_100000Z.mhl")
        XCTAssertEqual(ReportArchive.hashLists(for: result, style: .simpleHidden)[0].url.lastPathComponent,
                       "A001.mhl")
    }

    func testHashListsEmptyWithoutDestinationResult() {
        let result = TransferResult(configurationName: "P", destination: "/nowhere", startTime: Date())
        XCTAssertTrue(ReportArchive.hashLists(for: result).isEmpty)
    }

    func testDriveNameFallsBackToTheFolderNameWhenTheDriveIsGone() {
        var result = TransferResult(configurationName: "P", destination: "/Volumes/GONE-\(UUID().uuidString)/Backups",
                                    startTime: Date())
        result.destinationResults = []
        XCTAssertEqual(ReportArchive.driveName(for: result), "Backups")
    }

    // MARK: - Copy

    func testArchiveCopiesPDFAndListsAndLeavesTheDriveUntouched() throws {
        let (result, pdf) = try makeResult()
        let base = tmp.appendingPathComponent("Mac Reports")
        defaults.set(base.path, forKey: ReportArchive.DefaultsKey.folder)
        var config = BackupConfiguration()
        config.name = "Proj"
        config.day = "Day02"

        let dest = tmp.appendingPathComponent("SSD-A")
        let before = try fm.subpathsOfDirectory(atPath: dest.path).sorted()
        let written = ReportArchive.archive(pdfPath: pdf.path, result: result, config: config, defaults: defaults)
        XCTAssertEqual(try fm.subpathsOfDirectory(atPath: dest.path).sorted(), before)

        // The drive folder is the volume's name (the temp dir lives on the system volume here).
        let folder = base.appendingPathComponent("Proj/Day02")
            .appendingPathComponent(ReportArchive.driveName(for: result))
        XCTAssertEqual(Set(written.map(\.lastPathComponent)),
                       ["transfer_20261111_report.pdf", "0002_A001_2026-11-11_100000Z.mhl", "S001.mhl"])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: folder.path).sorted(),
                       ["0002_A001_2026-11-11_100000Z.mhl", "S001.mhl", "transfer_20261111_report.pdf"])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("0002_A001_2026-11-11_100000Z.mhl")), "gen2")
    }

    func testArchiveDoesNothingWhenSwitchedOff() throws {
        let (result, pdf) = try makeResult()
        let base = tmp.appendingPathComponent("Mac Reports")
        defaults.set(base.path, forKey: ReportArchive.DefaultsKey.folder)
        defaults.set(false, forKey: ReportArchive.DefaultsKey.enabled)
        XCTAssertTrue(ReportArchive.archive(pdfPath: pdf.path, result: result,
                                            config: BackupConfiguration(), defaults: defaults).isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: base.path))
    }

    func testCopyReplacesAnOlderCopyAndLeavesNoTempFile() throws {
        let (result, pdf) = try makeResult()
        let folder = tmp.appendingPathComponent("out")
        try write("old", to: folder.appendingPathComponent("transfer_20261111_report.pdf"))
        ReportArchive.copy(pdfPath: pdf.path, hashLists: ReportArchive.hashLists(for: result), into: folder)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("transfer_20261111_report.pdf")), "%PDF")
        let names = try fm.contentsOfDirectory(atPath: folder.path)
        XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })
        XCTAssertEqual(names.count, 3)
    }

    func testCopyWithNothingToCopyCreatesNoFolder() {
        let folder = tmp.appendingPathComponent("never")
        XCTAssertTrue(ReportArchive.copy(pdfPath: "/nonexistent/report.pdf", hashLists: [], into: folder).isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: folder.path))
    }

    func testCopyIntoAnUnwritablePlaceFailsQuietly() throws {
        let (_, pdf) = try makeResult()
        let blocker = tmp.appendingPathComponent("file-not-folder")
        try write("x", to: blocker)
        let written = ReportArchive.copy(pdfPath: pdf.path, hashLists: [],
                                         into: blocker.appendingPathComponent("sub"))
        XCTAssertTrue(written.isEmpty)
    }
}
