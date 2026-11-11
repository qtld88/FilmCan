import XCTest
@testable import FilmCan

final class VolumesInUseTests: XCTestCase {
    func test_volumeRoot() {
        XCTAssertEqual(VolumesInUse.volumeRoot(for: "/Volumes/A001/DCIM/clip.mov"), "/Volumes/A001")
        XCTAssertEqual(VolumesInUse.volumeRoot(for: "/Volumes/A001"), "/Volumes/A001")
        XCTAssertNil(VolumesInUse.volumeRoot(for: "/Users/me/Movies"))
        XCTAssertNil(VolumesInUse.volumeRoot(for: "/Volumes"))
    }

    func test_refcountedAcrossLeases() {
        let registry = VolumesInUse()
        let first = registry.acquire(paths: ["/Volumes/CARD/DCIM", "/Volumes/CARD/PRIVATE", "/Volumes/RAID/Backup"])
        let second = registry.acquire(paths: ["/Volumes/CARD"])
        XCTAssertTrue(registry.isBusy(path: "/Volumes/CARD/anything"))
        XCTAssertTrue(registry.isBusy(path: "/Volumes/RAID"))

        registry.release(first)
        XCTAssertTrue(registry.isBusy(path: "/Volumes/CARD"), "second lease still holds the card")
        XCTAssertFalse(registry.isBusy(path: "/Volumes/RAID"))

        registry.release(second)
        XCTAssertFalse(registry.isBusy(path: "/Volumes/CARD"))
        XCTAssertTrue(registry.busyRoots.isEmpty)
    }

    func test_bootDiskPathsIgnored_andDoubleReleaseHarmless() {
        let registry = VolumesInUse()
        let token = registry.acquire(paths: ["/Users/me/Movies"])
        XCTAssertTrue(registry.busyRoots.isEmpty)
        registry.release(token)
        registry.release(token)
        XCTAssertTrue(registry.busyRoots.isEmpty)
    }
}
