import XCTest
@testable import FilmCan

final class PerfSignpostTests: XCTestCase {

    func test_region_returnsWrappedValue() {
        let result = PerfSignpost.region("test") { 6 * 7 }
        XCTAssertEqual(result, 42)
    }

    func test_region_rethrows() {
        struct Boom: Error {}
        XCTAssertThrowsError(try PerfSignpost.region("test") { throw Boom() })
    }

    func test_shouldLogDuration_gating() {
        XCTAssertFalse(PerfSignpost.shouldLogDuration(ms: 50, warnMs: 100))
        XCTAssertFalse(PerfSignpost.shouldLogDuration(ms: 99.9, warnMs: 100))
        XCTAssertTrue(PerfSignpost.shouldLogDuration(ms: 100, warnMs: 100))
        XCTAssertTrue(PerfSignpost.shouldLogDuration(ms: 250, warnMs: 100))
    }

    func test_currentRegion_setAndRestore() {
        XCTAssertEqual(PerfSignpost.currentRegion, "idle")
        PerfSignpost.region("outer") {
            XCTAssertEqual(PerfSignpost.currentRegion, "outer")
            PerfSignpost.region("inner") {
                XCTAssertEqual(PerfSignpost.currentRegion, "inner")
            }
            XCTAssertEqual(PerfSignpost.currentRegion, "outer")
        }
        XCTAssertEqual(PerfSignpost.currentRegion, "idle")
    }
}
