import XCTest
import PDFKit
@testable import FilmCan

final class ReportRecreationTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("recreate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func roll(name: String = "A001") -> CatalogRoll {
        CatalogRoll(configId: nil, projectName: "Citizen K", shootDay: "Day02", rollName: name,
                    mediaKind: .camera, sourceVolumeUUID: nil, sourcePath: "/Volumes/CARD",
                    firstBackedUp: Date(timeIntervalSince1970: 1_780_000_000), files: [], copies: [])
    }

    private func copy(path: String, uuid: String? = nil, name: String = "SSD_1") -> CatalogCopy {
        CatalogCopy(destVolumeUUID: uuid, destVolumeName: name, rollFolderPath: path,
                    verified: true, date: Date(timeIntervalSince1970: 1_780_000_000))
    }

    // MARK: Where the roll is now

    func test_currentRollFolder_followsADriveMountedUnderAnotherName() {
        let c = copy(path: "/Volumes/SSD_1/CITIZENK/Day02/A001", uuid: "U1")
        let found = ReportRecreation.currentRollFolder(
            copy: c, mountedRootsByUUID: ["U1": "/Volumes/SSD_1 1"],
            exists: { $0 == "/Volumes/SSD_1 1/CITIZENK/Day02/A001" })
        XCTAssertEqual(found, "/Volumes/SSD_1 1/CITIZENK/Day02/A001")
    }

    func test_currentRollFolder_sameName_notConnected_missingFolder_noId() {
        let c = copy(path: "/Volumes/SSD_1/A001", uuid: "U1")
        XCTAssertEqual(ReportRecreation.currentRollFolder(
            copy: c, mountedRootsByUUID: ["U1": "/Volumes/SSD_1"], exists: { _ in true }), "/Volumes/SSD_1/A001")
        // Another drive with the same name is not this drive.
        XCTAssertNil(ReportRecreation.currentRollFolder(
            copy: c, mountedRootsByUUID: ["OTHER": "/Volumes/SSD_1"], exists: { _ in true }))
        XCTAssertNil(ReportRecreation.currentRollFolder(
            copy: c, mountedRootsByUUID: ["U1": "/Volumes/SSD_1"], exists: { _ in false }))
        let noId = copy(path: "/Volumes/NAS/A001", uuid: nil)
        XCTAssertEqual(ReportRecreation.currentRollFolder(
            copy: noId, mountedRootsByUUID: [:], exists: { _ in true }), "/Volumes/NAS/A001")
        XCTAssertNil(ReportRecreation.currentRollFolder(copy: noId, mountedRootsByUUID: [:], exists: { _ in false }))
        // A copy on the startup disk keeps its path.
        let local = copy(path: "/Users/me/Backups/A001", uuid: "BOOT")
        XCTAssertEqual(ReportRecreation.currentRollFolder(
            copy: local, mountedRootsByUUID: ["BOOT": "/"], exists: { _ in true }), "/Users/me/Backups/A001")
    }

    // MARK: The report

    private let files = [CatalogFile(relPath: "a.mov", size: 100),
                         CatalogFile(relPath: "b.mov", size: 250),
                         CatalogFile(relPath: "extra.txt", size: 5)]

    private func listed() -> ReportRecreation.Checksums {
        var sums = ReportRecreation.Checksums()
        sums.byRelPath = ["a.mov": .init(hash: "aaaa", size: 100),
                          "b.mov": .init(hash: "bbbb", size: 200),
                          "gone.mov": .init(hash: "cccc", size: 10)]
        return sums
    }

    func test_build_showsAChecksumOnlyForAListedFileOfUnchangedSize() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let report = ReportRecreation.build(
            roll: roll(), copy: copy(path: "/d/A001"), rollFolder: "/d/A001",
            filesOnDisk: files, checksums: listed(), now: now, appVersion: "1.0")

        let clips = report.rolls[0].clips
        XCTAssertEqual(clips.map(\.relPath), ["a.mov", "b.mov", "extra.txt"])
        XCTAssertEqual(clips[0].checksum, "aaaa")
        XCTAssertNil(clips[0].note)
        XCTAssertNil(clips[1].checksum, "size no longer matches the list")
        XCTAssertEqual(clips[1].note, ReportRecreation.noteSizeChanged)
        XCTAssertNil(clips[2].checksum, "not in the list")
        XCTAssertEqual(clips[2].note, ReportRecreation.noteNotListed)
        XCTAssertEqual(clips[0].absolutePath, "/d/A001/a.mov")
        XCTAssertTrue(clips[0].isVideo)

        let recreated = try? XCTUnwrap(report.recreated)
        XCTAssertEqual(recreated?.createdAt, now)
        XCTAssertEqual(recreated?.missingFiles, ["gone.mov"])
        XCTAssertEqual(recreated?.sizeChanged, 1)
        XCTAssertEqual(recreated?.notListed, 1)
        XCTAssertNil(recreated?.recheck)
        XCTAssertEqual(recreated?.hasProblems, true)
        XCTAssertFalse(report.verified, "a report made after the fact never claims the backup's check")
        XCTAssertEqual(report.projectName, "Citizen K")
        XCTAssertEqual(report.day, "Day02")
        XCTAssertEqual(report.destinationVolumeName, "SSD_1")
    }

    func test_build_withoutAChecksumList_listsFilesWithoutChecksums() {
        let report = ReportRecreation.build(
            roll: roll(), copy: copy(path: "/d/A001"), rollFolder: "/d/A001",
            filesOnDisk: files, checksums: ReportRecreation.Checksums(), now: Date(), appVersion: "1.0")
        XCTAssertTrue(report.rolls[0].clips.allSatisfy { $0.checksum == nil && $0.note == nil })
        XCTAssertEqual(report.recreated?.hasChecksumList, false)
        XCTAssertEqual(report.recreated?.hasProblems, false)
        XCTAssertTrue(report.recreated?.statusText.contains("No checksum list") == true)
    }

    func test_build_recheck_keepsOnlyChecksumsThatMatch() {
        var sums = ReportRecreation.Checksums()
        sums.byRelPath = ["a.mov": .init(hash: "AAAA", size: 100), "b.mov": .init(hash: "bbbb", size: 250),
                          "extra.txt": .init(hash: "eeee", size: nil)]
        let report = ReportRecreation.build(
            roll: roll(), copy: copy(path: "/d/A001"), rollFolder: "/d/A001",
            filesOnDisk: files, checksums: sums,
            rechecked: ["a.mov": "aaaa", "b.mov": "ffff", "extra.txt": .some(nil)],
            now: Date(), appVersion: "1.0")
        let clips = report.rolls[0].clips
        XCTAssertEqual(clips[0].checksum, "AAAA")
        XCTAssertNil(clips[1].checksum)
        XCTAssertEqual(clips[1].note, ReportRecreation.noteMismatch)
        XCTAssertNil(clips[2].checksum, "a file that could not be read does not match")
        XCTAssertEqual(report.recreated?.recheck, .init(checked: 3, mismatched: 2))
        XCTAssertEqual(report.recreated?.hasProblems, true)
    }

    func test_statusText_neverSaysVerified() {
        typealias R = BackupReport.Recreated
        let cases: [R] = [
            R(createdAt: Date(), hasChecksumList: false, missingFiles: [], sizeChanged: 0, notListed: 0, recheck: nil),
            R(createdAt: Date(), hasChecksumList: true, missingFiles: [], sizeChanged: 0, notListed: 0, recheck: nil),
            R(createdAt: Date(), hasChecksumList: true, missingFiles: ["x"], sizeChanged: 2, notListed: 1, recheck: nil),
            R(createdAt: Date(), hasChecksumList: true, missingFiles: [], sizeChanged: 0, notListed: 0,
              recheck: .init(checked: 4, mismatched: 0)),
            R(createdAt: Date(), hasChecksumList: true, missingFiles: ["x"], sizeChanged: 0, notListed: 0,
              recheck: .init(checked: 4, mismatched: 1))
        ]
        for item in cases {
            XCTAssertFalse(item.statusText.lowercased().contains("verified"), item.statusText)
            XCTAssertFalse(item.statusText.isEmpty)
        }
        XCTAssertTrue(cases[1].statusText.contains("not re-read"))
        XCTAssertTrue(cases[2].statusText.contains("1 missing"))
        XCTAssertTrue(cases[2].statusText.contains("2 changed size"))
        XCTAssertEqual(cases[3].statusText, "Re-checked: 4 files match the checksum list")
        XCTAssertTrue(cases[4].statusText.contains("1 do not match"))
        XCTAssertFalse(cases[1].hasProblems)
        XCTAssertFalse(cases[3].hasProblems)
    }

    func test_outputURL_isInTheReportsFolder_byFilmDayDrive() {
        let url = ReportRecreation.outputURL(roll: roll(name: "A/001"), copy: copy(path: "/d/A001"),
                                             base: URL(fileURLWithPath: "/base"))
        XCTAssertEqual(url.path, "/base/Citizen K/Day02/SSD_1/A-001_report_recreated.pdf")
    }

    // MARK: Checksum lists on disk

    private func write(_ name: String, _ bytes: Data, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url)
        return url
    }

    /// <tmp>/dest/A001 with a.bin and sub/b.bin, both in one sealed ASC MHL generation.
    private func makeRoll() async throws -> URL {
        let folder = tmp.appendingPathComponent("dest").appendingPathComponent("A001")
        let a = try write("a.bin", Data(repeating: 7, count: 4096), in: folder)
        let b = try write("sub/b.bin", Data(repeating: 9, count: 2048), in: folder)
        let writer = try ASCMHLWriter(ascmhlDir: folder.appendingPathComponent("ascmhl"), rollName: "A001")
        try await writer.append(relPath: "a.bin", size: 4096,
                                hash: try XCTUnwrap(Hashing.hash(for: a, algorithm: .xxh128)), mtime: nil)
        try await writer.append(relPath: "sub/b.bin", size: 2048,
                                hash: try XCTUnwrap(Hashing.hash(for: b, algorithm: .xxh128)), mtime: nil)
        try await writer.seal()
        return folder
    }

    func test_checksums_readTheListOnTheDrive_andRecheckFindsAChangedFile() async throws {
        let folder = try await makeRoll()
        let sums = ReportRecreation.checksums(rollFolder: folder.path)
        XCTAssertEqual(Set(sums.byRelPath.keys), ["a.bin", "sub/b.bin"])
        XCTAssertEqual(sums.byRelPath["a.bin"]?.size, 4096)

        let onDisk = MediaCatalogStore.listFiles(inRollFolder: folder.path)
        XCTAssertEqual(onDisk.map(\.relPath), ["a.bin", "sub/b.bin"])
        var rechecked = ReportRecreation.recheck(rollFolder: folder.path, filesOnDisk: onDisk, checksums: sums)
        XCTAssertEqual(rechecked["a.bin"] ?? nil, sums.byRelPath["a.bin"]?.hash)

        // Same size, other content: only a re-check can see it.
        try Data(repeating: 1, count: 2048).write(to: folder.appendingPathComponent("sub/b.bin"))
        rechecked = ReportRecreation.recheck(rollFolder: folder.path, filesOnDisk: onDisk, checksums: sums)
        let report = ReportRecreation.build(
            roll: roll(), copy: copy(path: folder.path), rollFolder: folder.path, filesOnDisk: onDisk,
            checksums: sums, rechecked: rechecked, now: Date(), appVersion: "1.0")
        XCTAssertNotNil(report.rolls[0].clips[0].checksum)
        XCTAssertEqual(report.rolls[0].clips[1].note, ReportRecreation.noteMismatch)
        XCTAssertEqual(report.recreated?.recheck, .init(checked: 2, mismatched: 1))
    }

    func test_checksums_simpleHiddenList() throws {
        let dest = tmp.appendingPathComponent("dest2")
        let folder = dest.appendingPathComponent("RUSHES").appendingPathComponent("A001")
        _ = try write("a.bin", Data(repeating: 7, count: 16), in: folder)
        let list = "<hashlist><file name=\"RUSHES/A001/a.bin\"><hash>abcd</hash></file>"
            + "<file name=\"RUSHES/OTHER/x.bin\"><hash>ffff</hash></file></hashlist>"
        _ = try write(".filmcan/hashlists/A001.mhl", Data(list.utf8), in: dest)
        let sums = ReportRecreation.checksums(rollFolder: folder.path)
        XCTAssertEqual(sums.byRelPath, ["a.bin": .init(hash: "abcd", size: nil)])
    }

    func test_checksums_noList() throws {
        let folder = tmp.appendingPathComponent("plain")
        _ = try write("a.bin", Data(repeating: 7, count: 16), in: folder)
        XCTAssertFalse(ReportRecreation.checksums(rollFolder: folder.path).found)
    }

    // MARK: The PDF

    func test_recreate_writesAPDFThatSaysItWasMadeAfterTheBackup() async throws {
        let folder = try await makeRoll()
        _ = try write("notes.txt", Data("hello".utf8), in: folder)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("a.bin"))
        let base = tmp.appendingPathComponent("reports")

        let path = await BackupReportWriter.recreate(roll: roll(), copy: copy(path: folder.path),
                                                     recheck: false, base: base)

        let pdf = try XCTUnwrap(path)
        XCTAssertEqual(pdf, base.appendingPathComponent("Citizen K/Day02/SSD_1/A001_report_recreated.pdf").path)
        let text = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: pdf))?.string)
        XCTAssertTrue(text.contains("Report created after the backup"), text)
        XCTAssertTrue(text.contains("missing from the drive"), text)
        XCTAssertTrue(text.contains("a.bin"))
        XCTAssertTrue(text.contains("b.bin"))
        XCTAssertTrue(text.contains(ReportRecreation.noteNotListed))
        XCTAssertFalse(text.contains("Verified"), "never the backup's own wording")
        // The drive is only read: nothing new next to the roll.
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(names, ["ascmhl", "notes.txt", "sub"])
    }

    func test_recreate_rollNotReachable_returnsNil_andWritesNothing() async {
        let base = tmp.appendingPathComponent("reports")
        let path = await BackupReportWriter.recreate(
            roll: roll(), copy: copy(path: tmp.appendingPathComponent("nowhere").path), recheck: true, base: base)
        XCTAssertNil(path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path))
    }

    /// A report written by a backup keeps its wording.
    func test_backupReport_isUnchangedByDefault() throws {
        let report = BackupReport(
            projectName: "P", episode: "", day: "", unit: "", destinationPath: "/d", destinationVolumeName: "D",
            startedAt: Date(), endedAt: Date(), success: true, verified: true, warning: nil,
            rolls: [], appVersion: "1.0")
        XCTAssertNil(report.recreated)
        let url = tmp.appendingPathComponent("r.pdf")
        try BackupReportWriter.render(report, thumbnails: [:], durations: [:], to: url)
        let text = try XCTUnwrap(PDFDocument(url: url)?.string)
        XCTAssertTrue(text.contains("Verified"))
        XCTAssertFalse(text.contains("Report created after the backup"))
    }
}
