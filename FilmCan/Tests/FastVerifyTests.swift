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

    // MARK: - Settle before re-reading a drive that may ignore F_FULLFSYNC

    /// The wait counts from the moment the file was written, not from when the verify
    /// lane picks it up: a file that already waited behind the previous one is re-read
    /// at once.
    func test_settleRemaining_countsFromTheFileFinalization() {
        let t = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: t, now: t), 1.0, accuracy: 0.0001)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: t, now: t.addingTimeInterval(0.3)), 0.7, accuracy: 0.0001)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: t, now: t.addingTimeInterval(1.5)), 0)
        XCTAssertEqual(FanOutCopier.settleRemaining(finalizedAt: nil, now: t), 0,
                       "a file this run did not write (kept as identical) needs no settle")
    }

    private func runTimed(files: Int, bytes: Int, mode: VerifyMode) async throws -> (TimeInterval, [DestResult]) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-settle-\(UUID().uuidString)")
        let src = tmp.appendingPathComponent("A001")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        for i in 0..<files {
            try Data(repeating: UInt8(i % 251), count: bytes)
                .write(to: src.appendingPathComponent(String(format: "C%04d.WAV", i)))
        }
        let cfg = FanOutCopier.Configuration(
            sources: [src.path],
            destinations: [DestWriter.Config(
                destPath: dst.path, displayName: "dst",
                verifyMode: mode, requiresFullFsync: true, chunkSize: nil)],
            verifyMode: mode, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        let start = Date()
        let results = try await FanOutCopier(config: cfg).run()
        return (Date().timeIntervalSince(start), results)
    }

    /// Fast re-reads the destination too, so it gets the same settle as Paranoid on a
    /// drive that may ignore the flush.
    func test_fastVerify_onFullFsyncDrive_waitsBeforeTheReread() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let (elapsed, results) = try await runTimed(files: 1, bytes: 256 * 1024, mode: .fast)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertGreaterThanOrEqual(elapsed, 1.0, "re-read at least 1 s after the file was written")
    }

    /// Twelve small files used to cost twelve seconds of waiting (1 s each, counted
    /// from the verify lane). Counted from each file's write, they overlap.
    func test_paranoid_onFullFsyncDrive_doesNotWaitASecondPerFile() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let (elapsed, results) = try await runTimed(files: 12, bytes: 100 * 1024, mode: .paranoid)
        XCTAssertTrue(results.allSatisfy(\.success))
        XCTAssertGreaterThanOrEqual(elapsed, 1.0)
        XCTAssertLessThan(elapsed, 6.0, "was ≥ 12 s with a fixed 1 s per file")
    }
}
