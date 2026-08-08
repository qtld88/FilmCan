import XCTest
@testable import FilmCan

final class HashListVerifierTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    /// Writes <roll>/a.bin + <roll>/ascmhl/0001_*.mhl and returns (rollFolder, manifestURL).
    private func makeSealedRoll(bytes: Data) async throws -> (roll: URL, manifest: URL) {
        let roll = tmp.appendingPathComponent("CARD")
        try FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        try bytes.write(to: roll.appendingPathComponent("a.bin"))
        let ascDir = roll.appendingPathComponent("ascmhl")
        let writer = try ASCMHLWriter(ascmhlDir: ascDir, rollName: "CARD")
        let hash = Hashing.hash(for: roll.appendingPathComponent("a.bin"), algorithm: .xxh128)
        try await writer.append(relPath: "a.bin", size: Int64(bytes.count),
                                hash: try XCTUnwrap(hash), mtime: nil)
        try await writer.seal()
        return (roll, URL(fileURLWithPath: writer.manifestPath))
    }

    func test_ascMHL_allFilesMatch() async throws {
        let (roll, manifest) = try await makeSealedRoll(bytes: Data(repeating: 7, count: 4096))
        let r = try XCTUnwrap(HashListVerifier.verify(hashListPath: manifest.path,
                                                      rootsFallback: [roll.path]))
        XCTAssertEqual(r.total, 1, "the manifest's one entry must be checked")
        XCTAssertEqual(r.missing, 0)
        XCTAssertEqual(r.mismatched, 0)
    }

    func test_ascMHL_modifiedFileIsMismatched() async throws {
        let (roll, manifest) = try await makeSealedRoll(bytes: Data(repeating: 7, count: 4096))
        try Data(repeating: 9, count: 4096).write(to: roll.appendingPathComponent("a.bin"))
        let r = try XCTUnwrap(HashListVerifier.verify(hashListPath: manifest.path,
                                                      rootsFallback: [roll.path]))
        XCTAssertEqual(r.total, 1)
        XCTAssertEqual(r.mismatched, 1)
    }

    func test_ascMHL_deletedFileIsMissing() async throws {
        let (roll, manifest) = try await makeSealedRoll(bytes: Data(repeating: 7, count: 4096))
        try FileManager.default.removeItem(at: roll.appendingPathComponent("a.bin"))
        let r = try XCTUnwrap(HashListVerifier.verify(hashListPath: manifest.path,
                                                      rootsFallback: [roll.path]))
        XCTAssertEqual(r.missing, 1)
    }

    func test_missingManifest_returnsNilNotEmptySuccess() {
        XCTAssertNil(HashListVerifier.verify(hashListPath: tmp.appendingPathComponent("nope.mhl").path))
    }

    func test_emptyManifest_returnsNilNotEmptySuccess() throws {
        // A manifest with zero <hash> entries must NOT read as "all good".
        let url = tmp.appendingPathComponent("0001_EMPTY_x.mhl")
        try #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0"><hashes></hashes></hashlist>
        """#.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(HashListVerifier.verify(hashListPath: url.path))
    }

    func test_rollFolder_derivedFromAscmhlParent() {
        XCTAssertEqual(
            HashListVerifier.rollFolder(forManifestPath: "/V/Day01/Camera_Media/CARD/ascmhl/0001_CARD.mhl",
                                        rootsFallback: []),
            "/V/Day01/Camera_Media/CARD")
    }

    func test_rollFolder_simpleHidden_fallsBackToDestRoot() {
        // <dest>/.filmcan/hashlists/<roll>.mhl → the entries are relative to <dest>.
        XCTAssertEqual(
            HashListVerifier.rollFolder(forManifestPath: "/V/BACKUP/.filmcan/hashlists/CARD.mhl",
                                        rootsFallback: []),
            "/V/BACKUP")
    }
}
