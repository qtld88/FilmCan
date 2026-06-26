import XCTest
@testable import FilmCan

final class InlineFanOutETALabelTests: XCTestCase {

    func test_active_withNoETA_showsEstimating() {
        XCTAssertEqual(InlineFanOutProgress.etaLabel(eta: nil, status: .active), "Estimating…")
        XCTAssertEqual(InlineFanOutProgress.etaLabel(eta: 0, status: .active), "Estimating…")
    }

    func test_active_withETA_showsRemaining() {
        XCTAssertEqual(InlineFanOutProgress.etaLabel(eta: 45, status: .active), "45s left")
        XCTAssertEqual(InlineFanOutProgress.etaLabel(eta: 130, status: .active), "2m left")
    }

    func test_nonActive_withNoETA_showsDash() {
        XCTAssertEqual(InlineFanOutProgress.etaLabel(eta: nil, status: .complete), "—")
    }
}
