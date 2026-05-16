import XCTest
@testable import FilmCan

final class MHLReaderTests: XCTestCase {
    func test_parseEntries_reportsAll() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-read-\(UUID().uuidString).mhl")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MHLWriter(url: url, sourceName: "Test.dmg")
        try await writer.append(hash: "hash1", fileName: "f1.bin")
        try await writer.append(hash: "hash2", fileName: "f2.bin")
        try await writer.flush()
        let entries = try MHLReader.read(url: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].hash, "hash1")
        XCTAssertEqual(entries[1].fileName, "f2.bin")
    }

    func test_parseKnownXmlHeader_returnsExpectedSource() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="1.0" source="FilmCan_v1.0.dmg">
          <file name="a.bin"><hash>abc</hash></file>
        </hashlist>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mhl")
        defer { try? FileManager.default.removeItem(at: url) }
        try xml.write(to: url, atomically: true, encoding: .utf8)
        let entries = try MHLReader.read(url: url)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].hash, "abc")
    }
}
