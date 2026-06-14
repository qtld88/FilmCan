import XCTest
@testable import FilmCan

final class ConstantsTests: XCTestCase {
    func test_ringCapBytes_capsAt96MB() {
        let cap = Constants.ringCapBytesPerDest(physRamBytes: 64 * 1024 * 1024 * 1024)
        XCTAssertEqual(cap, 96 * 1024 * 1024)
    }

    func test_ringCapBytes_scalesWithRam() {
        // 8 GB / 128 = 64 MB, between the 32 MB floor and 96 MB cap.
        let cap = Constants.ringCapBytesPerDest(physRamBytes: 8 * 1024 * 1024 * 1024)
        XCTAssertEqual(cap, 64 * 1024 * 1024)
    }

    func test_ringCapBytes_floorsAt32MB() {
        let cap = Constants.ringCapBytesPerDest(physRamBytes: 1 * 1024 * 1024 * 1024)
        XCTAssertEqual(cap, 32 * 1024 * 1024)
    }

    func test_chunkSize_nvmeToNvmeIs16MB() {
        XCTAssertEqual(Constants.chunkBytes(forSlowestDest: .nvmeLocal), 16 * 1024 * 1024)
    }

    func test_chunkSize_exfatIs4MB() {
        XCTAssertEqual(Constants.chunkBytes(forSlowestDest: .exfat), 4 * 1024 * 1024)
    }

    func test_speedDisparityWarnRatio_is3() {
        XCTAssertEqual(Constants.speedDisparityWarnRatio, 3.0)
    }

    func test_localDestTimeoutSec_is30() {
        XCTAssertEqual(Constants.localDestTimeoutSec, 30.0)
    }
}
