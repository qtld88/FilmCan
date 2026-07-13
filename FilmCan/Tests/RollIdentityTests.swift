import XCTest
@testable import FilmCan

final class RollIdentityTests: XCTestCase {

    func test_recommend_matchingUUIDAndPath_isResume() {
        let rec = RollIdentity(volumeUUID: "ABC", volumeName: "DJI", sourcePath: "/Volumes/DJI", lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: rec, currentUUID: "ABC", currentPath: "/Volumes/DJI"), .resumeSameCard)
    }

    func test_recommend_matchingUUIDDifferentPath_isNewCard() {
        // Same shuttle drive (same volume UUID), different staged folder → NOT the same card.
        let rec = RollIdentity(volumeUUID: "ABC", volumeName: "Shuttle", sourcePath: "/Volumes/Shuttle/DAY1/A001", lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: rec, currentUUID: "ABC", currentPath: "/Volumes/Shuttle/DAY2/A001"), .newCard)
    }

    func test_recommend_legacySidecarNoPath_matchingUUID_isResume() {
        // Pre-existing sidecar carries no path → fall back to UUID-only resume.
        let rec = RollIdentity(volumeUUID: "ABC", volumeName: "DJI", sourcePath: nil, lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: rec, currentUUID: "ABC", currentPath: "/Volumes/DJI"), .resumeSameCard)
    }

    func test_recommend_differingUUID_isNewCard() {
        let rec = RollIdentity(volumeUUID: "ABC", volumeName: "DJI", sourcePath: "/Volumes/DJI", lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: rec, currentUUID: "XYZ", currentPath: "/Volumes/DJI"), .newCard)
    }

    func test_recommend_noRecorded_isUnknown() {
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: nil, currentUUID: "ABC", currentPath: "/Volumes/DJI"), .unknown)
    }

    func test_recommend_missingEitherUUID_isUnknown() {
        let recNoUUID = RollIdentity(volumeUUID: nil, volumeName: "DJI", sourcePath: "/Volumes/DJI", lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: recNoUUID, currentUUID: "ABC", currentPath: "/Volumes/DJI"), .unknown)
        let rec = RollIdentity(volumeUUID: "ABC", volumeName: "DJI", sourcePath: "/Volumes/DJI", lastSeen: Date())
        XCTAssertEqual(RollIdentityResolver.recommend(recorded: rec, currentUUID: nil, currentPath: "/Volumes/DJI"), .unknown)
    }

    func test_defaultDecision_unknownAndResume_areResume_newCardIsNot() {
        XCTAssertTrue(RollIdentityResolver.defaultDecisionIsResume(.resumeSameCard))
        XCTAssertTrue(RollIdentityResolver.defaultDecisionIsResume(.unknown))
        XCTAssertFalse(RollIdentityResolver.defaultDecisionIsResume(.newCard))
    }

    func test_store_roundTrip() throws {
        let roll = FileManager.default.temporaryDirectory
            .appendingPathComponent("roll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: roll) }

        let original = RollIdentity(volumeUUID: "UUID-1", volumeName: "DJI", sourcePath: "/Volumes/DJI", lastSeen: Date(timeIntervalSince1970: 1_700_000_000))
        RollIdentityStore.write(original, rollFolder: roll.path)
        let read = RollIdentityStore.read(rollFolder: roll.path)
        XCTAssertEqual(read, original)
    }

    func test_store_readMissing_isNil() {
        let roll = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        XCTAssertNil(RollIdentityStore.read(rollFolder: roll.path))
    }
}
