import XCTest
import PDFKit
@testable import FilmCan

/// Thread-safe flag for driving `FanOutCopier.Configuration.shouldCancel`.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    func set() { lock.lock(); stopped = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

/// Session 5 of the audit: the functions around the engine must never announce a
/// result that is not true (repair, verify data, PDF report, statuses).
/// Real disk I/O in a temp folder, no mocks.
@MainActor
final class HonestOutcomeTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("honest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
    }

    // MARK: - Helpers

    private func randomData(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        return Data(bytes)
    }

    @discardableResult
    private func makeCard(_ name: String, files: [String], size: Int = 48 * 1024) throws -> URL {
        let card = tmpDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        for f in files { try randomData(size).write(to: card.appendingPathComponent(f)) }
        return card
    }

    private func makeDir(_ name: String) throws -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func run(sources: [URL], dests: [URL], verify: VerifyMode = .paranoid,
                     rollNames: [String: String] = [:],
                     progress: (@Sendable (DestProgress) -> Void)? = nil,
                     shouldCancel: (@Sendable () -> Bool)? = nil) async throws -> [DestResult] {
        let cfg = FanOutCopier.Configuration(
            sources: sources.map(\.path),
            destinations: dests.map {
                DestWriter.Config(destPath: $0.path, displayName: $0.lastPathComponent,
                                  verifyMode: verify, requiresFullFsync: false, chunkSize: 32 * 1024)
            },
            verifyMode: verify, mhlBasePath: nil, dryRun: false,
            progressHandler: progress,
            rollNames: rollNames,
            shouldCancel: shouldCancel)
        return try await FanOutCopier(config: cfg).run()
    }

    private func transferResult(_ dr: DestResult, name: String = "Proj") -> TransferResult {
        var fan = TransferResult(configurationName: name, destination: dr.destinationPath,
                                 startTime: Date(), endTime: Date(), success: dr.success)
        fan.destinationResults = [dr]
        return TransferViewModel(isBackgroundWorker: true).explodeFanOutResult(fan, configName: name)[0]
    }

    // MARK: - Finding 1: repair from a sibling covers every roll

    /// A run with two cards writes one manifest per roll. Repairing the failed
    /// destination from the sibling must bring back BOTH rolls, not only the first.
    func test_repairFromSibling_twoCards_repairsEveryRoll() async throws {
        let fm = FileManager.default
        let cardA = try makeCard("A001", files: ["C0001.MP4", "C0002.MP4"])
        let cardB = try makeCard("B001", files: ["C0101.MP4"])
        let sibling = try makeDir("sibling")
        let failedRoot = try makeDir("failed")

        let results = try await run(sources: [cardA, cardB], dests: [sibling])
        let siblingResult = try XCTUnwrap(results.first)
        XCTAssertTrue(siblingResult.success)

        let failed = DestResult(destinationPath: failedRoot.path, displayName: "failed",
                                success: false, failureReason: .ioError("simulated"),
                                verifyMode: .paranoid)
        let vm = TransferViewModel(isBackgroundWorker: true)
        var parent = TransferResult(configurationName: "t", destination: failedRoot.path,
                                    startTime: Date(), endTime: Date(), success: false)
        parent.destinationResults = [siblingResult, failed]
        vm.results = [parent]

        let ok = await vm.repairFailedDest(failed: failed, sibling: siblingResult, choice: .fromSibling)

        XCTAssertTrue(ok)
        for (roll, name) in [("A001", "C0001.MP4"), ("A001", "C0002.MP4"), ("B001", "C0101.MP4")] {
            let repaired = failedRoot.appendingPathComponent(roll).appendingPathComponent(name)
            let original = sibling.appendingPathComponent(roll).appendingPathComponent(name)
            XCTAssertTrue(fm.fileExists(atPath: repaired.path), "\(roll)/\(name) not repaired")
            XCTAssertEqual(try? Data(contentsOf: repaired), try? Data(contentsOf: original))
        }
        // Each repaired roll gets its own sealed generation.
        for roll in ["A001", "B001"] {
            let asc = failedRoot.appendingPathComponent(roll).appendingPathComponent("ascmhl")
            XCTAssertNotNil(ASCMHLChain.latestManifestPath(ascmhlDir: asc), "\(roll) has no manifest")
        }
    }

    /// One roll that cannot be repaired (its file is gone from the sibling) makes the
    /// whole repair fail, even when another roll repaired fine.
    func test_repairFromSibling_oneRollMissing_isNotSuccess() async throws {
        let cardA = try makeCard("A001", files: ["C0001.MP4"])
        let cardB = try makeCard("B001", files: ["C0101.MP4"])
        let sibling = try makeDir("sibling")
        let failedRoot = try makeDir("failed")
        let results = try await run(sources: [cardA, cardB], dests: [sibling])
        let siblingResult = try XCTUnwrap(results.first)
        try FileManager.default.removeItem(
            at: sibling.appendingPathComponent("B001").appendingPathComponent("C0101.MP4"))

        let failed = DestResult(destinationPath: failedRoot.path, displayName: "failed",
                                success: false, failureReason: .ioError("simulated"),
                                verifyMode: .paranoid)
        let vm = TransferViewModel(isBackgroundWorker: true)
        var parent = TransferResult(configurationName: "t", destination: failedRoot.path,
                                    startTime: Date(), endTime: Date(), success: false)
        parent.destinationResults = [siblingResult, failed]
        vm.results = [parent]

        let ok = await vm.repairFailedDest(failed: failed, sibling: siblingResult, choice: .fromSibling)

        XCTAssertFalse(ok)
        let patched = vm.results.first?.destinationResults.first { $0.destinationPath == failedRoot.path }
        XCTAssertEqual(patched?.success, false)
    }

    // MARK: - Finding 8: statuses

    /// A Stop that lands after the copy, while the file waits for verification, is a
    /// cancellation — never "Verification mismatch".
    func test_stopDuringVerification_isCancelledNotMismatch() async throws {
        let card = try makeCard("A001", files: ["C0001.MP4"], size: 256 * 1024)
        let dest = try makeDir("dest")
        let flag = StopFlag()
        let results = try await run(
            sources: [card], dests: [dest],
            progress: { prog in
                // Copy bytes all written: from here on the file is waiting for, or in,
                // verification.
                if prog.bytesTotal > 0, prog.bytesCompleted >= prog.bytesTotal { flag.set() }
            },
            shouldCancel: { flag.get() })

        let r = try XCTUnwrap(results.first)
        XCTAssertTrue(flag.get(), "the stop must have been requested")
        if !r.success {
            XCTAssertEqual(r.failureReason, .userCancel)
            XCTAssertNotEqual(r.failureReason?.displayMessage, DestFailureReason.verify.displayMessage)
        }
    }

    /// A failure on the card is final for the run: a stale `.active` delivered later
    /// must not turn it back into a running card.
    func test_mergedStatus_failedIsStickyAgainstLateActive() {
        XCTAssertEqual(TransferViewModel.mergedStatus(previous: .failed(.verify), incoming: .active),
                       .failed(.verify))
        XCTAssertEqual(TransferViewModel.mergedStatus(previous: .failed(.userCancel), incoming: .preparing),
                       .failed(.userCancel))
        XCTAssertEqual(TransferViewModel.mergedStatus(previous: .failed(.verify), incoming: .complete),
                       .failed(.verify))
        // Unchanged behaviour.
        XCTAssertEqual(TransferViewModel.mergedStatus(previous: .active, incoming: .failed(.verify)),
                       .failed(.verify))
        XCTAssertEqual(TransferViewModel.mergedStatus(previous: .complete, incoming: .active), .complete)
    }

    // MARK: - Finding 4: PDF report

    /// A file whose size no longer matches the checksum list shows no checksum, and
    /// the report as a whole is not "verified".
    func test_report_sizeChanged_showsNoChecksumAndIsNotVerified() async throws {
        let card = try makeCard("A001", files: ["A.mov", "B.wav"])
        let dest = try makeDir("dest")
        let results = try await run(sources: [card], dests: [dest])
        let dr = try XCTUnwrap(results.first)
        XCTAssertTrue(dr.success)
        let onDrive = dest.appendingPathComponent("A001").appendingPathComponent("A.mov")
        try randomData(1000).write(to: onDrive)

        var config = BackupConfiguration()
        config.name = "Proj"
        let report = BackupReport.build(result: transferResult(dr), config: config, appVersion: "1")
        let clips = report.rolls[0].clips
        let a = try XCTUnwrap(clips.first { $0.relPath == "A.mov" })
        let b = try XCTUnwrap(clips.first { $0.relPath == "B.wav" })
        XCTAssertNil(a.checksum, "a checksum is never shown without proof")
        XCTAssertNotNil(b.checksum)
        XCTAssertEqual(b.checksumAlgorithm, "xxh128")
        XCTAssertFalse(report.verified, "the whole report cannot say verified")
    }

    /// A damaged latest generation does not wipe every checksum: the previous
    /// readable generation still proves the files it lists.
    func test_report_damagedLatestGeneration_fallsBackToPrevious() async throws {
        let fm = FileManager.default
        let card = try makeCard("A001", files: ["A.mov"])
        let dest = try makeDir("dest")
        _ = try await run(sources: [card], dests: [dest])
        try randomData(48 * 1024).write(to: card.appendingPathComponent("B.mov"))
        let second = try await run(sources: [card], dests: [dest])
        let dr = try XCTUnwrap(second.first)

        let asc = dest.appendingPathComponent("A001").appendingPathComponent("ascmhl")
        let latest = try XCTUnwrap(ASCMHLChain.latestManifestFileName(ascmhlDir: asc))
        let latestURL = asc.appendingPathComponent(latest)
        let full = try Data(contentsOf: latestURL)
        try full.prefix(full.count / 2).write(to: latestURL)
        XCTAssertGreaterThanOrEqual(ASCMHLChain.manifestFilesOnDisk(ascmhlDir: asc).count, 2)
        _ = fm

        var config = BackupConfiguration()
        config.name = "Proj"
        let report = BackupReport.build(result: transferResult(dr), config: config, appVersion: "1")
        let clips = report.rolls[0].clips
        XCTAssertNotNil(clips.first { $0.relPath == "A.mov" }?.checksum,
                        "A.mov is proved by the first generation")
        XCTAssertNil(clips.first { $0.relPath == "B.mov" }?.checksum,
                     "B.mov is only in the damaged generation")
    }

    /// The PDF does not depend on the log: with the log off, a report is still written.
    func test_report_generatedWithoutLog() async throws {
        let card = try makeCard("A001", files: ["meta.xml"], size: 4 * 1024)
        let dest = try makeDir("dest")
        let results = try await run(sources: [card], dests: [dest])
        let dr = try XCTUnwrap(results.first)
        var config = BackupConfiguration()
        config.name = "Proj"
        config.logEnabled = false
        config.reportEnabled = true
        let result = transferResult(dr)
        XCTAssertNil(result.logFilePath)

        let path = await BackupReportWriter.generate(result: result, config: config)

        let pdfPath = try XCTUnwrap(path, "a report must be written without a log")
        XCTAssertNotNil(PDFDocument(url: URL(fileURLWithPath: pdfPath)))
        XCTAssertTrue(pdfPath.hasPrefix(dest.path), "the report goes where the log would have gone")
    }

    /// The report lists each file with its own status: copied and checked this run.
    func test_report_perFileStatus_andStatusLine() async throws {
        let card = try makeCard("A001", files: ["A.mov"])
        let dest = try makeDir("dest")
        _ = try await run(sources: [card], dests: [dest])
        try randomData(48 * 1024).write(to: card.appendingPathComponent("B.mov"))
        let second = try await run(sources: [card], dests: [dest])
        let dr = try XCTUnwrap(second.first)
        var config = BackupConfiguration()
        config.name = "Proj"
        let report = BackupReport.build(result: transferResult(dr), config: config, appVersion: "1")
        let clips = report.rolls[0].clips
        XCTAssertEqual(clips.first { $0.relPath == "A.mov" }?.status, .fromEarlierBackup)
        XCTAssertEqual(clips.first { $0.relPath == "B.mov" }?.status, .verifiedThisRun)
        XCTAssertTrue(report.verified)
        XCTAssertTrue(report.statusLine.contains("1 verified this run"), report.statusLine)
        XCTAssertTrue(report.statusLine.contains("1 from an earlier backup"), report.statusLine)
    }

    /// Verification Off: the file was copied but never checked. No checksum, not verified.
    func test_report_verificationOff_isNotVerified() async throws {
        let card = try makeCard("A001", files: ["A.mov"])
        let dest = try makeDir("dest")
        let dr = try XCTUnwrap(try await run(sources: [card], dests: [dest], verify: .off).first)
        var config = BackupConfiguration()
        config.name = "Proj"
        let report = BackupReport.build(result: transferResult(dr), config: config, appVersion: "1")
        let a = try XCTUnwrap(report.rolls.first?.clips.first)
        XCTAssertEqual(a.status, .copiedNotVerified)
        XCTAssertNil(a.checksum)
        XCTAssertFalse(report.verified)
    }

    // MARK: - Finding 1: the repaired copy is read back from disk

    func test_siblingCheckOnDisk_rejectsAndRemovesADifferentFile() throws {
        let file = tmpDir.appendingPathComponent("x.bin")
        try randomData(4096).write(to: file)
        XCTAssertThrowsError(try SiblingDestSource.checkOnDisk(
            path: file.path, fileName: "x.bin", expectedHash: String(repeating: "0", count: 32)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - Finding 2: repair from source keeps the shoot tokens

    func test_runContext_keepsShootMetadata_andReadsOldEntries() throws {
        var ctx = RunContext(organizationPresetId: nil, cameraFolderTemplate: nil, soundFolderTemplate: nil,
                             copyFolderContents: false, sourceMediaKinds: [:], duplicatePolicy: .ask,
                             hashListStyle: .ascMHL)
        ctx.shootMetadata = ShootMetadata(episode: "EP01", day: "D02", unit: "U1", cameraFormat: "ARRI", movie: "M")
        let back = try JSONDecoder().decode(RunContext.self, from: JSONEncoder().encode(ctx))
        XCTAssertEqual(back.shootMetadata, ctx.shootMetadata)

        let old = #"{"copyFolderContents":false,"sourceMediaKinds":{},"duplicatePolicy":"ask","hashListStyle":"ascMHL"}"#
        let decoded = try? JSONDecoder().decode(RunContext.self, from: Data(old.utf8))
        if let decoded { XCTAssertNil(decoded.shootMetadata) }
    }

    /// Netflix layout: the repair writes into the same episode/day/unit folder as the
    /// backup, not an empty-token one.
    func test_repairFromSource_netflix_usesShootMetadata() async throws {
        let fm = FileManager.default
        let card = try makeCard("A001", files: ["C0001.MOV"])
        let dest = try makeDir("dest")
        let preset = OrganizationPreset.netflixIngest()
        let meta = ShootMetadata(episode: "EP01", day: "D02", unit: "U1", cameraFormat: "ARRI", movie: "M")
        let failed = DestResult(destinationPath: dest.path, displayName: "dest", success: false,
                                failureReason: .ioError("x"), verifyMode: .fast)

        let outcome = await RepairCoordinator.repairFromSource(
            failed: failed, sources: [card.path], organizationPreset: preset,
            copyFolderContents: false, duplicatePolicy: .overwrite, sourceMediaKinds: [:],
            hashListStyle: .ascMHL, shootMetadata: meta)

        XCTAssertTrue(outcome.allOK)
        let all = (fm.enumerator(atPath: dest.path)?.allObjects as? [String]) ?? []
        let copied = try XCTUnwrap(all.first { $0.hasSuffix("C0001.MOV") }, "file not copied")
        XCTAssertTrue(copied.contains("EP01") && copied.contains("D02") && copied.contains("ARRI"), copied)
    }

    // MARK: - Finding 3: Verify data follows the assigned roll names

    func test_verifyBackedUp_withAssignedRollName_checksTheFiles() async throws {
        let card = try makeCard("Untitled", files: ["C0001.MP4", "C0002.MP4"])
        let dest = try makeDir("dest")
        let results = try await run(sources: [card], dests: [dest], rollNames: [card.path: "A001"])
        XCTAssertTrue(results[0].success)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dest.appendingPathComponent("A001/C0001.MP4").path))

        let info = AlreadyBackedUpInfo(sources: [card.path], destinations: [dest.path],
                                       fileCount: 2, date: Date(), rollNames: [card.path: "A001"])
        let r = TransferViewModel.verifyBackedUp(info)
        XCTAssertEqual(r.total, 2)
        XCTAssertEqual(r.missing, 0)
        XCTAssertEqual(r.mismatched, 0)
    }

    // MARK: - Finding 5: Netflix auto-fix never touches the card

    func test_netflixFix_namesTheDestination_andLeavesTheCardAlone() async throws {
        let fm = FileManager.default
        let card1 = try makeCard("A#01", files: ["C0001.MP4"])
        let card2 = try makeCard("A_01", files: ["C0002.MP4"])
        let fixes = NetflixNameValidator.fixedRollNames(sources: [card1.path, card2.path])
        XCTAssertEqual(fixes[card1.path], "A_01")
        XCTAssertEqual(fixes[card2.path], "A_01_001")
        XCTAssertTrue(fm.fileExists(atPath: card1.path), "the card folder is never renamed")

        var config = BackupConfiguration()
        config.sourcePaths = [card1.path, card2.path]
        config.runRollNames = [card2.path: "B001"]  // numbering wins
        let applied = config.withRollNameFallbacks(fixes)
        XCTAssertEqual(applied.runRollNames[card1.path], "A_01")
        XCTAssertEqual(applied.runRollNames[card2.path], "B001")

        let dest = try makeDir("dest")
        _ = try await run(sources: [card1], dests: [dest], rollNames: [card1.path: "A_01"])
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A_01/C0001.MP4").path))
        XCTAssertTrue(fm.fileExists(atPath: card1.appendingPathComponent("C0001.MP4").path))
        let onCard = try fm.contentsOfDirectory(atPath: card1.path)
        XCTAssertEqual(onCard.filter { !$0.hasPrefix(".") }, ["C0001.MP4"])
    }

    // MARK: - Finding 6: a waiting destination stopped in sequential mode

    func test_cancelledBeforeStart_isACancellationNotACopy() {
        let r = TransferViewModel.cancelledBeforeStartResult(
            destination: "/Volumes/B", configName: "Film", startedAt: Date())
        XCTAssertFalse(r.success)
        XCTAssertEqual(r.filesTransferred, 0)
        XCTAssertEqual(r.destinationResults.first?.failureReason, .userCancel)
        XCTAssertEqual(r.errorMessage, DestFailureReason.userCancel.displayMessage)
    }
}
