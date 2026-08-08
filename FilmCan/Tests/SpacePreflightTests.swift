import XCTest
@testable import FilmCan

final class SpacePreflightTests: XCTestCase {

    func test_twoDestinationsOnOneVolumeAreSummed() {
        let short = FanOutCopier.spaceShortfall(
            neededByDest: ["/V/A": 600, "/V/B": 400],
            volumeKeyByDest: ["/V/A": "vol-1", "/V/B": "vol-1"],
            availableByDest: ["/V/A": 900, "/V/B": 900])
        XCTAssertNotNil(short, "1000 needed on one 900-byte volume must fail the preflight")
        XCTAssertEqual(short?.required, 1000)
        XCTAssertEqual(short?.available, 900)
    }

    func test_separateVolumesAreCheckedIndependently() {
        XCTAssertNil(FanOutCopier.spaceShortfall(
            neededByDest: ["/V/A": 600, "/V/B": 600],
            volumeKeyByDest: ["/V/A": "vol-1", "/V/B": "vol-2"],
            availableByDest: ["/V/A": 900, "/V/B": 900]))
    }

    func test_destinationNeedingNothingIsIgnored() {
        XCTAssertNil(FanOutCopier.spaceShortfall(
            neededByDest: ["/V/A": 0, "/V/B": 100],
            volumeKeyByDest: ["/V/A": "vol-1", "/V/B": "vol-1"],
            availableByDest: ["/V/A": 50, "/V/B": 500]))
    }

    func test_unknownVolumeFallsBackToPerDestination() {
        // No UUID available: each path is its own key, matching today's behavior.
        XCTAssertNil(FanOutCopier.spaceShortfall(
            neededByDest: ["/V/A": 600, "/V/B": 600],
            volumeKeyByDest: ["/V/A": "/V/A", "/V/B": "/V/B"],
            availableByDest: ["/V/A": 900, "/V/B": 900]))
    }
}
