import XCTest
@testable import FilmCan

final class SharedJobTimingTests: XCTestCase {
    private func row(_ id: String, status: DestStatus = .active,
                     speed: Double, eta: TimeInterval?) -> DestProgress {
        var p = DestProgress(id: id, displayName: id, status: status)
        p.speedBytesPerSecond = speed
        p.estimatedTimeRemaining = eta
        p.bytesCompleted = 61
        p.bytesTotal = 132
        return p
    }

    func testSSDAndHDDShowTheSameSpeedAndTimeLeft() {
        let rows = [row("ssd", speed: 83, eta: 14 * 60), row("hdd", speed: 44, eta: 28 * 60)]
        let shared = rows.sharingJobTiming()
        XCTAssertEqual(shared.map(\.speedBytesPerSecond), [44, 44])
        XCTAssertEqual(shared.map(\.estimatedTimeRemaining), [28 * 60, 28 * 60])
    }

    func testBytesAndOtherFieldsAreUntouched() {
        let rows = [row("ssd", speed: 83, eta: 840), row("hdd", speed: 44, eta: 1680)]
        let shared = rows.sharingJobTiming()
        XCTAssertEqual(shared.map(\.bytesCompleted), rows.map(\.bytesCompleted))
        XCTAssertEqual(shared.map(\.id), ["ssd", "hdd"])
    }

    func testSingleActiveDestinationKeepsItsOwnValues() {
        let rows = [row("ssd", status: .complete, speed: 83, eta: nil), row("hdd", speed: 44, eta: 600)]
        XCTAssertEqual(rows.sharingJobTiming(), rows)
    }

    func testFinishedOrFailedRowsAreNotChanged() {
        let rows = [row("a", speed: 80, eta: 100), row("b", speed: 40, eta: 300),
                    row("c", status: .complete, speed: 0, eta: nil)]
        let shared = rows.sharingJobTiming()
        XCTAssertEqual(shared[2], rows[2])
    }

    func testStillEstimatingRowsDoNotBlankTheOthers() {
        let rows = [row("a", speed: 0, eta: nil), row("b", speed: 40, eta: 300)]
        let shared = rows.sharingJobTiming()
        XCTAssertEqual(shared.map(\.estimatedTimeRemaining), [300, 300])
        XCTAssertEqual(shared.map(\.speedBytesPerSecond), [40, 40])
    }

    func testSharedTimingRowLooksUpById() {
        let rows = [row("ssd", speed: 83, eta: 840), row("hdd", speed: 44, eta: 1680)]
        XCTAssertEqual(rows.sharedTimingRow(for: "ssd")?.estimatedTimeRemaining, 1680)
        XCTAssertNil(rows.sharedTimingRow(for: "missing"))
    }
}

final class TabJobFractionTests: XCTestCase {
    private func row(_ id: String, copied: Int64, verified: Int64,
                     status: DestStatus = .active) -> DestProgress {
        var p = DestProgress(id: id, displayName: id, status: status)
        p.bytesTotal = 100
        p.verifyBytesTotal = 100
        p.bytesCompleted = copied
        p.verifyBytesCompleted = verified
        return p
    }

    func testTwoDrivesHalfCopiedIsNotReportedAsFinished() {
        let progress = TransferProgress()
        progress.isRunning = true
        progress.perDestProgress = [row("a", copied: 50, verified: 0), row("b", copied: 50, verified: 0)]
        XCTAssertEqual(progress.jobFraction, 0.25, accuracy: 0.0001)
    }

    func testSlowestDriveSetsThePace() {
        let progress = TransferProgress()
        progress.isRunning = true
        progress.perDestProgress = [row("ssd", copied: 60, verified: 60), row("hdd", copied: 60, verified: 20)]
        XCTAssertEqual(progress.jobFraction, 0.4, accuracy: 0.0001)
    }

    func testFailedDriveDoesNotFreezeTheBar() {
        let progress = TransferProgress()
        progress.isRunning = true
        progress.perDestProgress = [row("ok", copied: 80, verified: 80),
                                    row("bad", copied: 0, verified: 0, status: .failed(.userCancel))]
        XCTAssertEqual(progress.jobFraction, 0.8, accuracy: 0.0001)
    }

    func testCompleteRowCountsAsDone() {
        XCTAssertEqual(row("a", copied: 10, verified: 0, status: .complete).workFraction, 1)
    }
}
