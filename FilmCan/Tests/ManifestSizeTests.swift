import XCTest
@testable import FilmCan

final class ManifestSizeTests: XCTestCase {

    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_enumerator_reportsBothSizes() async throws {
        let card = tmp.appendingPathComponent("CARD")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data([0x41]).write(to: card.appendingPathComponent("tiny.txt"))

        let result = await FileEnumerator.enumerateFiles(sources: [card.path], preset: nil)
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.logicalSize, 1, "logical size is the file's byte count")
        XCTAssertGreaterThanOrEqual(entry.allocatedSize, entry.logicalSize)
    }

    func test_manifestRecordsLogicalSize() async throws {
        let card = tmp.appendingPathComponent("CARD")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data([0x41]).write(to: card.appendingPathComponent("tiny.txt"))
        let dest = tmp.appendingPathComponent("DEST")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        // Reuse the integration suite's minimal config helper shape.
        let cfg = FanOutCopier.Configuration(
            sources: [card.path],
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "DEST",
                                             verifyMode: .fast, requiresFullFsync: false,
                                             chunkSize: nil)],
            verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        _ = try await FanOutCopier(config: cfg).run()

        let ascDir = dest.appendingPathComponent("CARD/ascmhl")
        let name = try XCTUnwrap(ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir))
        let entries = try ASCMHLReader.read(url: ascDir.appendingPathComponent(name))
        XCTAssertEqual(entries.first?.size, 1, "the manifest must record the file's real byte count")
    }
}
