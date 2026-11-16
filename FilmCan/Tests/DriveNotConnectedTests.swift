import XCTest
@testable import FilmCan

final class DriveNotConnectedTests: XCTestCase {
    func testUnmountedVolumeIsReportedByName() {
        let name = DriveUtilities.disconnectedDriveName(for: "/Volumes/NAV_B/TLF", exists: { _ in false })
        XCTAssertEqual(name, "NAV_B")
    }

    func testMountedVolumeIsNotReported() {
        let name = DriveUtilities.disconnectedDriveName(
            for: "/Volumes/NAV_B/TLF", exists: { $0 == "/Volumes/NAV_B" })
        XCTAssertNil(name)
    }

    func testOnlyTheVolumeRootIsChecked() {
        var asked: [String] = []
        _ = DriveUtilities.disconnectedDriveName(for: "/Volumes/NAV_B/TLF/Day01", exists: {
            asked.append($0); return true
        })
        XCTAssertEqual(asked, ["/Volumes/NAV_B"])
    }

    func testPathOnTheMacIsNeverADisconnectedDrive() {
        XCTAssertNil(DriveUtilities.disconnectedDriveName(for: "/Users/me/Backups", exists: { _ in false }))
        XCTAssertNil(DriveUtilities.disconnectedDriveName(for: "/Volumes", exists: { _ in false }))
    }

    func testMessageNamesTheDriveAndTheFix() {
        XCTAssertEqual(DriveUtilities.driveNotConnectedMessage(driveName: "NAV_B"),
                       "The drive \"NAV_B\" is not connected. Connect it, or untick it in Save To.")
    }

    func testEngineErrorSaysNotConnectedForAnUnpluggedDrive() {
        let path = "/Volumes/FilmCanTestMissing-\(UUID().uuidString)/TLF"
        let message = FanOutCopier.Error.destinationUnwritable(path).errorDescription ?? ""
        XCTAssertTrue(message.contains("is not connected"), message)
    }
}
