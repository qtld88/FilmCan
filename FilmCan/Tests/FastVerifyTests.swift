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
}
