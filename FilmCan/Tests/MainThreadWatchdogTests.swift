import XCTest
@testable import FilmCan

final class MainThreadWatchdogTests: XCTestCase {

    func test_evaluate_belowWarn_noEvent() {
        XCTAssertNil(MainThreadWatchdog.evaluate(elapsedMs: 50, lastReportedTier: nil))
    }

    func test_evaluate_warnTier() {
        XCTAssertEqual(MainThreadWatchdog.evaluate(elapsedMs: 120, lastReportedTier: nil)?.tier, .warn)
    }

    func test_evaluate_errorTier() {
        XCTAssertEqual(MainThreadWatchdog.evaluate(elapsedMs: 600, lastReportedTier: nil)?.tier, .error)
    }

    func test_evaluate_debounce_sameTier() {
        XCTAssertNil(MainThreadWatchdog.evaluate(elapsedMs: 200, lastReportedTier: .warn))
    }

    func test_evaluate_escalateWarnToError() {
        XCTAssertEqual(MainThreadWatchdog.evaluate(elapsedMs: 600, lastReportedTier: .warn)?.tier, .error)
    }

    func test_evaluate_debounce_errorAlreadyReported() {
        XCTAssertNil(MainThreadWatchdog.evaluate(elapsedMs: 2000, lastReportedTier: .error))
    }
    // MARK: - PowerAssertion

    func test_powerAssertion_refCountsAndReleasesFully() {
        let a = PowerAssertion.shared
        XCTAssertFalse(a.isHeld)
        a.acquire(reason: "unit test")
        XCTAssertTrue(a.isHeld)
        a.acquire(reason: "unit test nested")   // concurrent job
        XCTAssertTrue(a.isHeld)
        a.release()
        XCTAssertTrue(a.isHeld, "still held while a second job runs")
        a.release()
        XCTAssertFalse(a.isHeld, "last one out must release")
    }

    func test_powerAssertion_extraReleaseIsHarmless() {
        let a = PowerAssertion.shared
        XCTAssertFalse(a.isHeld)
        a.release()                              // unbalanced; must not underflow
        XCTAssertFalse(a.isHeld)
        a.acquire(reason: "unit test")
        XCTAssertTrue(a.isHeld)
        a.release()
        XCTAssertFalse(a.isHeld)
    }

}
