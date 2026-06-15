import XCTest
@testable import FilmCan

final class ASCMHLChainTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("chain-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testEmptyChainNextSequenceIsOne() {
        XCTAssertEqual(ASCMHLChain.nextSequence(ascmhlDir: tempDir()), 1)
        XCTAssertNil(ASCMHLChain.latestManifestPath(ascmhlDir: tempDir()))
    }

    func testAppendThenReadRoundTrip() throws {
        let dir = tempDir()
        try ASCMHLChain.append(ascmhlDir: dir, sequence: 1,
                               manifestFileName: "0001_A001_2026-06-15_120000Z.mhl",
                               manifestData: Data("manifest-one".utf8))
        try ASCMHLChain.append(ascmhlDir: dir, sequence: 2,
                               manifestFileName: "0002_A001_2026-06-16_120000Z.mhl",
                               manifestData: Data("manifest-two".utf8))

        let refs = ASCMHLChain.read(ascmhlDir: dir)
        XCTAssertEqual(refs.count, 2)
        XCTAssertEqual(refs[0].seq, 1)
        XCTAssertEqual(refs[0].path, "0001_A001_2026-06-15_120000Z.mhl")
        XCTAssertEqual(refs[0].c4, C4Hash.id(of: Data("manifest-one".utf8)))
        XCTAssertEqual(refs[1].seq, 2)
        XCTAssertEqual(ASCMHLChain.nextSequence(ascmhlDir: dir), 3)
        XCTAssertEqual(ASCMHLChain.latestManifestPath(ascmhlDir: dir), "0002_A001_2026-06-16_120000Z.mhl")

        let xml = try String(contentsOf: dir.appendingPathComponent("ascmhl_chain.xml"), encoding: .utf8)
        XCTAssertTrue(xml.contains(#"<ascmhldirectory xmlns="urn:ASC:MHL:DIRECTORY:v2.0">"#))
        XCTAssertTrue(xml.contains(#"<hashlist sequencenr="1">"#))
        XCTAssertTrue(xml.contains("<path>0001_A001_2026-06-15_120000Z.mhl</path>"))
    }
}
