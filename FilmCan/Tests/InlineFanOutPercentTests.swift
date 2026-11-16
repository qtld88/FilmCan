import XCTest
@testable import FilmCan

final class InlineFanOutPercentTests: XCTestCase {

    private func dest(copied: Int64, verified: Int64, total: Int64 = 100,
                      mode: VerifyMode = .fast, status: DestStatus = .active) -> DestProgress {
        var p = DestProgress(id: "/d", displayName: "d", status: status,
                             bytesTotal: total, verifyMode: mode)
        p.bytesCompleted = copied
        p.verifyBytesTotal = mode == .off ? 0 : total
        p.verifyBytesCompleted = verified
        return p
    }

    func test_copyDone_verifyPending_readsHalf() {
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 100, verified: 0)), 50)
    }

    func test_percentMovesDuringVerifyOnly() {
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 100, verified: 20)), 60)
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 100, verified: 60)), 80)
    }

    func test_capsAt99UntilComplete() {
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 100, verified: 100)), 99)
        XCTAssertEqual(InlineFanOutProgress.percent(
            for: dest(copied: 100, verified: 100, status: .complete)), 100)
    }

    func test_verifyOff_isCopyOnly() {
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 40, verified: 0, mode: .off)), 40)
    }

    func test_nothingToCopy_readsZero() {
        XCTAssertEqual(InlineFanOutProgress.percent(for: dest(copied: 0, verified: 0, total: 0)), 0)
    }

    func test_bytesText_showsVerifiedGBDuringVerifyOnly() {
        let p = dest(copied: 43_000_000_000, verified: 18_000_000_000, total: 43_000_000_000)
        XCTAssertEqual(InlineFanOutProgress.bytesText(for: p), "18 / 43 GB")
    }

    func test_bytesText_showsCopiedGBWhileCopying() {
        let p = dest(copied: 20_000_000_000, verified: 5_000_000_000, total: 43_000_000_000)
        XCTAssertEqual(InlineFanOutProgress.bytesText(for: p), "20 / 43 GB")
    }
}
