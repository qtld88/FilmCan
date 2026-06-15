import XCTest
@testable import FilmCan

final class ASCMHLReaderTests: XCTestCase {
    func testRoundTripWithWriter() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rt-\(UUID().uuidString)/ascmhl/0001_A001.mhl")
        let w = try ASCMHLWriter(url: url, rollName: "A001")
        try await w.append(relPath: "Clips/A001C001.mov", size: 42, hash: "0ea03b369a463d9d2ad5f8e0c1b4a9f3")
        try await w.append(relPath: "Sidecar.txt", size: 7, hash: "ffffffffffffffffffffffffffffffff")
        try await w.seal()

        let entries = try ASCMHLReader.read(url: url)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].relPath, "Clips/A001C001.mov")
        XCTAssertEqual(entries[0].size, 42)
        XCTAssertEqual(entries[0].hash, "0ea03b369a463d9d2ad5f8e0c1b4a9f3")
        XCTAssertEqual(entries[1].relPath, "Sidecar.txt")
    }

    func testFilmCanXXH128MatchesManifestValue() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("clip.bin")
        try Data([0x01, 0x02, 0x03, 0x04, 0x05]).write(to: file)

        guard let hex = Hashing.hash(for: file, algorithm: .xxh128) else {
            throw XCTSkip("libxxhash unavailable in this environment")
        }
        let url = dir.appendingPathComponent("ascmhl/0001_R.mhl")
        let w = try ASCMHLWriter(url: url, rollName: "R")
        try await w.append(relPath: "clip.bin", size: 5, hash: hex)
        try await w.seal()
        let entries = try ASCMHLReader.read(url: url)
        XCTAssertEqual(entries.first?.hash, hex)
    }
}
