import XCTest
@testable import FilmCan

final class ASCMHLWriterTests: XCTestCase {
    private func tempAscmhlDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ascmhl-\(UUID().uuidString)")
            .appendingPathComponent("A001")
            .appendingPathComponent("ascmhl")
    }

    func testWritesValidASCMHLV2() async throws {
        let dir = tempAscmhlDir()
        let w = try ASCMHLWriter(ascmhlDir: dir, rollName: "A001")
        try await w.append(relPath: "Clips/A001C001.mov", size: 5, hash: "0ea03b369a463d9d2ad5f8e0c1b4a9f3", mtime: nil)
        try await w.seal()
        let xml = try String(contentsOfFile: w.manifestPath, encoding: .utf8)
        XCTAssertTrue(xml.contains(#"<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">"#))
        XCTAssertTrue(xml.contains("<tool version=") && xml.contains(">FilmCan</tool>"))
        XCTAssertTrue(xml.contains("<process>in-place</process>"))
        XCTAssertTrue(xml.contains(#"<path size="5">Clips/A001C001.mov</path>"#))
        XCTAssertTrue(xml.contains(#"<xxh128 action="original" hashdate="#))
        XCTAssertTrue(xml.contains("0ea03b369a463d9d2ad5f8e0c1b4a9f3</xxh128>"))
        XCTAssertTrue(xml.contains("</hashlist>"))
        XCTAssertEqual(w.sequence, 1)
        XCTAssertTrue(w.manifestFileName.hasPrefix("0001_A001_"))
        XCTAssertEqual(ASCMHLChain.latestManifestPath(ascmhlDir: dir), w.manifestFileName)
    }

    func testEmptyWriterLeavesNoDirOrManifest() async throws {
        let dir = tempAscmhlDir()
        let w = try ASCMHLWriter(ascmhlDir: dir, rollName: "A001")
        try await w.seal()  // nothing appended
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path),
                       "a roll with nothing copied must not create an ascmhl/ folder")
        XCTAssertNil(ASCMHLChain.latestManifestFileName(ascmhlDir: dir))
    }

    func testSecondRunCreatesGenerationTwo() async throws {
        let dir = tempAscmhlDir()
        let g1 = try ASCMHLWriter(ascmhlDir: dir, rollName: "A001")
        try await g1.append(relPath: "f.mov", size: 1, hash: "aa", mtime: nil)
        try await g1.seal()
        let g2 = try ASCMHLWriter(ascmhlDir: dir, rollName: "A001")
        XCTAssertEqual(g2.sequence, 2)
        try await g2.append(relPath: "f.mov", size: 1, hash: "aa", mtime: nil)
        try await g2.seal()
        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: dir).count, 2)
        XCTAssertEqual(ASCMHLChain.latestManifestPath(ascmhlDir: dir), g2.manifestFileName)
    }

    func testEscapesXMLInPath() async throws {
        let dir = tempAscmhlDir()
        let w = try ASCMHLWriter(ascmhlDir: dir, rollName: "A001")
        try await w.append(relPath: "a & b <x>.mov", size: 1, hash: "ab", mtime: nil)
        try await w.seal()
        let xml = try String(contentsOfFile: w.manifestPath, encoding: .utf8)
        XCTAssertTrue(xml.contains("a &amp; b &lt;x&gt;.mov"))
        XCTAssertFalse(xml.contains("a & b <x>"))
    }
}
