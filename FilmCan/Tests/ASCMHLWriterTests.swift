import XCTest
@testable import FilmCan

final class ASCMHLWriterTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ascmhl-\(UUID().uuidString)")
            .appendingPathComponent("ascmhl")
            .appendingPathComponent("0001_A001.mhl")
    }

    func testWritesValidASCMHLV2() async throws {
        let url = tempURL()
        let w = try ASCMHLWriter(url: url, rollName: "A001")
        try await w.append(relPath: "Clips/A001C001.mov", size: 5, hash: "0ea03b369a463d9d2ad5f8e0c1b4a9f3")
        try await w.seal()
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains(#"<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">"#))
        XCTAssertTrue(xml.contains("<tool version=") && xml.contains(">FilmCan</tool>"))
        XCTAssertTrue(xml.contains("<process>in-place</process>"))
        XCTAssertTrue(xml.contains(#"<path size="5">Clips/A001C001.mov</path>"#))
        XCTAssertTrue(xml.contains(#"<xxh128 action="original" hashdate="#))
        XCTAssertTrue(xml.contains("0ea03b369a463d9d2ad5f8e0c1b4a9f3</xxh128>"))
        XCTAssertTrue(xml.contains("</hashlist>"))
    }

    func testEscapesXMLInPath() async throws {
        let url = tempURL()
        let w = try ASCMHLWriter(url: url, rollName: "A001")
        try await w.append(relPath: "a & b <x>.mov", size: 1, hash: "ab")
        try await w.seal()
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains("a &amp; b &lt;x&gt;.mov"))
        XCTAssertFalse(xml.contains("a & b <x>"))
    }
}
