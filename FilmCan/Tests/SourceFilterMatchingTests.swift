import XCTest
@testable import FilmCan

final class SourceFilterMatchingTests: XCTestCase {

    func test_normalizedPatterns_trimsAndDropsEmpty() {
        XCTAssertEqual(
            SourceFilterMatching.normalizedPatterns(["  *.mov ", "", "   ", "*.wav"]),
            ["*.mov", "*.wav"])
    }

    func test_matchesPattern_globCaseInsensitive() {
        XCTAssertTrue(SourceFilterMatching.matchesPattern("CLIP.MOV", pattern: "*.mov"))
        XCTAssertFalse(SourceFilterMatching.matchesPattern("clip.wav", pattern: "*.mov"))
    }
}
