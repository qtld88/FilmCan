import XCTest
@testable import FilmCan

final class FastVerifyTests: XCTestCase {
    func testFastVerifyRereadsDestinationAndFailsOnBadRead() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-fastverify-\(UUID().uuidString)")
        let src = tmp.appendingPathComponent("src")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let clip = src.appendingPathComponent("A001.mov")
        try Data(repeating: 0xAB, count: 4 * 1024 * 1024).write(to: clip)

        var cfg = FanOutCopier.Configuration(
            sources: [src.path],
            destinations: [DestWriter.Config(
                destPath: dst.path, displayName: "dst",
                verifyMode: .fast, requiresFullFsync: false, chunkSize: nil)],
            verifyMode: .fast,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil)
        cfg._testForceDestReadHashNil = true   // force the dest re-read to fail

        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success,
                       "fast verify must re-read the destination and fail on a bad read")
    }

    // MARK: - Paranoid settle before re-reading a drive that may ignore F_FULLFSYNC

    /// The wait counts from the moment the file was written (monotonic clock), not from
    /// when the verify lane picks it up: a file that already waited is re-read at once.
    func test_settleRemaining_countsFromTheFileFinalization() {
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: 100, now: 100), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: 100, now: 100.3), 0.7, accuracy: 0.0001)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: 100, now: 101.5), 0)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: nil, now: 100), 0,
                       "a file this run did not write (kept as identical) needs no settle")
    }

    private final class RereadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [(dest: String, gap: TimeInterval?)] = []
        func add(_ dest: String, _ finalizedAt: TimeInterval?, _ startedAt: TimeInterval) {
            lock.lock(); defer { lock.unlock() }
            entries.append((dest, finalizedAt.map { startedAt - $0 }))
        }
        var all: [(dest: String, gap: TimeInterval?)] { lock.lock(); defer { lock.unlock() }; return entries }
    }

    /// Runs a real copy of `files` files to one destination per entry of `fullFsync`.
    private func runTimed(files: Int, bytes: Int, mode: VerifyMode, fullFsync: [Bool],
                          log: RereadLog) async throws -> (TimeInterval, [DestResult]) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-settle-\(UUID().uuidString)")
        let src = tmp.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for i in 0..<files {
            try Data(repeating: UInt8(i % 251), count: bytes)
                .write(to: src.appendingPathComponent(String(format: "C%04d.WAV", i)))
        }
        var dests: [DestWriter.Config] = []
        for (i, full) in fullFsync.enumerated() {
            let dst = tmp.appendingPathComponent("dst\(i)")
            try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
            dests.append(DestWriter.Config(destPath: dst.path, displayName: "dst\(i)",
                                           verifyMode: mode, requiresFullFsync: full, chunkSize: nil))
        }
        var cfg = FanOutCopier.Configuration(
            sources: [src.path], destinations: dests,
            verifyMode: mode, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        cfg._testOnDestReread = { log.add($0, $1, $2) }
        let start = Date()
        let results = try await FanOutCopier(config: cfg).run()
        return (Date().timeIntervalSince(start), results)
    }

    /// Same guarantee as before (every destination file re-read at least 1 s after it
    /// was written), without paying 1 s per file: twelve files used to cost ≥ 12 s.
    func test_paranoid_fullFsyncDrive_everyRereadAtLeastOneSecondAfterWrite_butNotOneSecondPerFile() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let log = RereadLog()
        let (elapsed, results) = try await runTimed(files: 12, bytes: 100 * 1024, mode: .paranoid,
                                                    fullFsync: [true], log: log)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertEqual(log.all.count, 12)
        for e in log.all {
            let gap = try XCTUnwrap(e.gap)
            XCTAssertGreaterThanOrEqual(gap, FanOutCopier.fullFsyncSettle - 0.005, "re-read too early")
        }
        XCTAssertLessThan(elapsed, 6.0, "was ≥ 12 s with a fixed 1 s per file")
    }

    /// As before, when one destination needs F_FULLFSYNC every destination of the run
    /// waits (coverage unchanged), each counted from its own write.
    func test_paranoid_mixedDrives_everyDestinationStillSettles() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let log = RereadLog()
        let (_, results) = try await runTimed(files: 3, bytes: 100 * 1024, mode: .paranoid,
                                              fullFsync: [true, false], log: log)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertEqual(log.all.count, 6)
        for e in log.all {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(e.gap), FanOutCopier.fullFsyncSettle - 0.005, e.dest)
        }
    }

    /// Fast is unchanged: it never waits, even on a drive that needs F_FULLFSYNC.
    func test_fast_fullFsyncDrive_neverWaits() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let log = RereadLog()
        let (elapsed, results) = try await runTimed(files: 3, bytes: 100 * 1024, mode: .fast,
                                                    fullFsync: [true], log: log)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertEqual(log.all.count, 3)
        XCTAssertLessThan(elapsed, 1.0)
    }

    /// Paranoid with no drive needing F_FULLFSYNC never waited and still does not.
    func test_paranoid_noFullFsyncDrive_neverWaits() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let log = RereadLog()
        let (elapsed, results) = try await runTimed(files: 3, bytes: 100 * 1024, mode: .paranoid,
                                                    fullFsync: [false], log: log)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertLessThan(elapsed, 1.0)
    }
}
