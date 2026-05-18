import XCTest
@testable import FilmCan

@MainActor
final class ExplodeFanOutResultTests: XCTestCase {

    func test_explodeFanOutResult_producesOneRecordPerDest() {
        let vm = TransferViewModel()
        let now = Date()

        var dr1 = DestResult(destinationPath: "/Volumes/CARD_A", displayName: "CARD_A")
        dr1.success = true
        dr1.filesTransferred = 10
        dr1.bytesTransferred = 1_000_000
        dr1.mhlPath = "/Volumes/CARD_A/.filmcan/hashlists/SRC.mhl"
        dr1.verifyMode = .paranoid

        var dr2 = DestResult(destinationPath: "/Volumes/CARD_B", displayName: "CARD_B")
        dr2.success = false
        dr2.filesTransferred = 3
        dr2.bytesTransferred = 300_000
        dr2.failureReason = .verify
        dr2.verifyMode = .paranoid

        var fanOut = TransferResult(
            configurationName: "MyConfig",
            destination: dr1.destinationPath,
            startTime: now,
            endTime: now.addingTimeInterval(10),
            success: false
        )
        fanOut.destinationResults = [dr1, dr2]

        let exploded = vm.explodeFanOutResult(fanOut, configName: "MyConfig")

        XCTAssertEqual(exploded.count, 2)

        let r1 = exploded[0]
        XCTAssertEqual(r1.destination, "/Volumes/CARD_A")
        XCTAssertTrue(r1.success)
        XCTAssertNil(r1.errorMessage)
        XCTAssertEqual(r1.hashListPath, "/Volumes/CARD_A/.filmcan/hashlists/SRC.mhl")
        XCTAssertTrue(r1.wasVerified)
        XCTAssertEqual(r1.destinationResults.count, 1)
        XCTAssertEqual(r1.destinationResults[0].destinationPath, "/Volumes/CARD_A")

        let r2 = exploded[1]
        XCTAssertEqual(r2.destination, "/Volumes/CARD_B")
        XCTAssertFalse(r2.success)
        XCTAssertNotNil(r2.errorMessage)
        XCTAssertFalse(r2.wasVerified)
        XCTAssertEqual(r2.destinationResults.count, 1)
        XCTAssertEqual(r2.destinationResults[0].destinationPath, "/Volumes/CARD_B")
    }

    func test_explodeFanOutResult_preservesTimestamps() {
        let vm = TransferViewModel()
        let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let end = Date(timeIntervalSinceReferenceDate: 1_000_060)

        var dr = DestResult(destinationPath: "/Volumes/X", displayName: "X")
        dr.success = true
        dr.bytesTransferred = 512
        dr.verifyMode = .fast

        var fanOut = TransferResult(
            configurationName: "Cfg",
            destination: "/Volumes/X",
            startTime: start,
            endTime: end,
            success: true
        )
        fanOut.destinationResults = [dr]

        let exploded = vm.explodeFanOutResult(fanOut, configName: "Cfg")
        XCTAssertEqual(exploded[0].startTime, start)
        XCTAssertEqual(exploded[0].endTime, end)
    }
}
