import XCTest
@testable import FilmCan

final class FolderPickTests: XCTestCase {
    func test_replacing_keepsPosition() {
        let paths = ["/Volumes/A", "/Volumes/B", "/Volumes/C"]
        XCTAssertEqual(FolderPick.replacing("/Volumes/B", with: "/Volumes/B/DCIM/100", in: paths),
                       ["/Volumes/A", "/Volumes/B/DCIM/100", "/Volumes/C"])
    }

    func test_replacing_dropsOldWhenNewAlreadyListed() {
        let paths = ["/Volumes/A", "/Volumes/A/CLIPS"]
        XCTAssertEqual(FolderPick.replacing("/Volumes/A", with: "/Volumes/A/CLIPS", in: paths),
                       ["/Volumes/A/CLIPS"])
    }

    func test_replacing_unknownOld_isNoOp() {
        XCTAssertEqual(FolderPick.replacing("/x", with: "/y", in: ["/a"]), ["/a"])
    }

    func test_hasDeeperPick() {
        XCTAssertTrue(FolderPick.hasDeeperPick(under: "/Volumes/A", in: ["/Volumes/A/CLIPS"]))
        XCTAssertFalse(FolderPick.hasDeeperPick(under: "/Volumes/A", in: ["/Volumes/A"]))
        XCTAssertFalse(FolderPick.hasDeeperPick(under: "/Volumes/A", in: ["/Volumes/AB/CLIPS"]))
    }
}
