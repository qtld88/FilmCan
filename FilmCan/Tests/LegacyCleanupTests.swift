import XCTest
@testable import FilmCan

final class LegacyCleanupTests: XCTestCase {

    func test_defaultExcludes_matchLegacyList() {
        XCTAssertTrue(DefaultExcludes.patterns.contains(".DS_Store"))
        XCTAssertTrue(DefaultExcludes.patterns.contains(".Trashes"))
        XCTAssertTrue(DefaultExcludes.patterns.contains(".Spotlight-V100"))
        XCTAssertTrue(DefaultExcludes.patterns.contains(".fseventsd"))
        XCTAssertTrue(DefaultExcludes.patterns.contains(".DocumentRevisions-V100"))
        XCTAssertTrue(DefaultExcludes.patterns.contains(".TemporaryItems"))
    }

    func test_engineOptions_roundTripsLiveFields() throws {
        var o = EngineOptions()
        o.parallelCopyEnabled = false
        o.customVerifyEnabled = false
        o.verificationMode = .paranoid
        o.fileOrdering = .defaultOrder
        let data = try JSONEncoder().encode(o)
        let decoded = try JSONDecoder().decode(EngineOptions.self, from: data)
        XCTAssertEqual(decoded, o)
        let fresh = EngineOptions()
        XCTAssertTrue(fresh.parallelCopyEnabled)
        XCTAssertTrue(fresh.customVerifyEnabled)
        XCTAssertTrue(fresh.allowResume)
    }
}
