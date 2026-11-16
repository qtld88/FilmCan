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
}
