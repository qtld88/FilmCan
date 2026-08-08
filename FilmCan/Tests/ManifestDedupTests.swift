import XCTest
@testable import FilmCan

final class ManifestDedupTests: XCTestCase {

    private var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func test_ascMHLWriter_appendReplacesSeededEntry() async throws {
        let writer = try ASCMHLWriter(ascmhlDir: tmp.appendingPathComponent("ascmhl"), rollName: "R")
        await writer.seed([MHLEntry(relPath: "a.bin", size: 10, hash: "OLD", mtime: nil)])
        try await writer.append(relPath: "a.bin", size: 20, hash: "NEW", mtime: nil)
        try await writer.seal()

        let entries = try ASCMHLReader.read(url: URL(fileURLWithPath: writer.manifestPath))
        XCTAssertEqual(entries.count, 1, "a re-copied file must not appear twice")
        XCTAssertEqual(entries.first?.hash, "NEW", "the fresh hash wins")
        XCTAssertEqual(entries.first?.size, 20)
    }

    func test_simpleMHLWriter_appendReplacesSeededEntry() async throws {
        let writer = try SimpleMHLWriter(destRoot: tmp.path, rollName: "R")
        await writer.seed([MHLEntry(relPath: "a.bin", size: 10, hash: "OLD", mtime: nil)])
        try await writer.append(relPath: "a.bin", size: 20, hash: "NEW", mtime: nil)
        try await writer.seal()

        let entries = try SimpleMHLReader.read(url: URL(fileURLWithPath: writer.manifestPath))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.hash, "NEW")
    }

    func test_ascMHLWriter_preservesSeededOrderForUntouchedEntries() async throws {
        let writer = try ASCMHLWriter(ascmhlDir: tmp.appendingPathComponent("ascmhl"), rollName: "R")
        await writer.seed([
            MHLEntry(relPath: "a.bin", size: 1, hash: "A", mtime: nil),
            MHLEntry(relPath: "b.bin", size: 1, hash: "B", mtime: nil)
        ])
        try await writer.append(relPath: "a.bin", size: 1, hash: "A2", mtime: nil)
        try await writer.append(relPath: "c.bin", size: 1, hash: "C", mtime: nil)
        try await writer.seal()

        let entries = try ASCMHLReader.read(url: URL(fileURLWithPath: writer.manifestPath))
        XCTAssertEqual(entries.map(\.relPath), ["a.bin", "b.bin", "c.bin"])
        XCTAssertEqual(entries.first?.hash, "A2")
    }
}
