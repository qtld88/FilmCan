import XCTest
@testable import FilmCan

final class MHLAppendFailureTests: XCTestCase {
    func testMHLAppendFailureMarksDestinationFailed() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-mhlfail-\(UUID().uuidString)")
        let src = tmp.appendingPathComponent("src")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(repeating: 7, count: 1024).write(to: src.appendingPathComponent("A001.mov"))

        var cfg = FanOutCopier.Configuration(
            sources: [src.path],
            destinations: [DestWriter.Config(
                destPath: dst.path, displayName: "dst",
                verifyMode: .paranoid, requiresFullFsync: false, chunkSize: nil)],
            verifyMode: .paranoid, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        cfg._testForceMHLAppendFailure = true

        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success,
                       "a failed manifest write must not be reported as success")
    }
}
