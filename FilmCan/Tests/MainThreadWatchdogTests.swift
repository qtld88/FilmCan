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
}
