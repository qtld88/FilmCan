import XCTest
@testable import FilmCan

final class CardSealTests: XCTestCase {

    func test_cardSeal_roundTripsThroughJSON() throws {
        let seal = CardSeal(
            schemaVersion: CardSeal.currentSchemaVersion,
            volumeUUID: "UUID-1",
            sealDate: Date(timeIntervalSince1970: 1_700_000_000),
            appVersion: "1.4.0",
            entries: [
                CardSeal.Entry(relPath: "A001.MOV", size: 100),
                CardSeal.Entry(relPath: "sub/B002.MOV", size: 200)
            ],
            includePatterns: ["*.mov"],
            excludePatterns: [],
            copyOnlyPatterns: [],
            destinationsVerified: ["/Volumes/DEST"],
            mhlRef: "ascmhl/A001.mhl"
        )

        let data = try JSONEncoder().encode(seal)
        let decoded = try JSONDecoder().decode(CardSeal.self, from: data)

        XCTAssertEqual(decoded.volumeUUID, "UUID-1")
        XCTAssertEqual(decoded.entries.count, 2)
        XCTAssertEqual(decoded.entries[1].relPath, "sub/B002.MOV")
        XCTAssertEqual(decoded.entries[1].size, 200)
        XCTAssertEqual(decoded.includePatterns, ["*.mov"])
        XCTAssertEqual(decoded.schemaVersion, CardSeal.currentSchemaVersion)
    }

    func test_sealState_isEquatable() {
        XCTAssertEqual(SealState.sealed, SealState.sealed)
        XCTAssertNotEqual(SealState.sealed, SealState.none)
        XCTAssertEqual(
            SealState.broken(added: ["x"], missing: [], modified: []),
            SealState.broken(added: ["x"], missing: [], modified: [])
        )
    }
}
