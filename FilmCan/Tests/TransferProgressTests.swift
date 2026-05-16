import XCTest
@testable import FilmCan

@MainActor
final class TransferProgressTests: XCTestCase {

    // MARK: - overallProgress

    func test_overallProgress_whenFinishedAndNotRunning_returns1() {
        let p = TransferProgress()
        p.isRunning = false
        p.phase = .finished
        p.hasError = false
        p.isCancelled = false
        p.isPaused = false
        XCTAssertEqual(p.overallProgress, 1.0)
    }

    func test_overallProgress_whenRunningWithBytes_returnsFraction() {
        let p = TransferProgress()
        p.isRunning = true
        p.phase = .copying
        p.totalBytes = 1000
        p.cumulativeBytes = 500
        p.filesTotal = 10
        p.filesCompleted = 5
        let result = p.overallProgress
        XCTAssertGreaterThan(result, 0.0)
        XCTAssertLessThan(result, 1.0)
    }

    func test_overallProgress_whenNoTotals_returns0() {
        let p = TransferProgress()
        p.isRunning = true
        p.phase = .copying
        XCTAssertEqual(p.overallProgress, 0.0)
    }

    func test_overallProgress_cancelledDoesNotReturn1WhenFinished() {
        let p = TransferProgress()
        p.isRunning = false
        p.phase = .finished
        p.isCancelled = true
        XCTAssertNotEqual(p.overallProgress, 1.0)
    }

    // MARK: - verificationWeightedProgress

    func test_verificationWeightedProgress_whenNoTotals_returns0() {
        let p = TransferProgress()
        XCTAssertEqual(p.verificationWeightedProgress, 0.0)
    }

    func test_verificationWeightedProgress_whenFilesOnlyHalfDone_returnsFraction() {
        let p = TransferProgress()
        p.verificationFilesTotal = 10
        p.verificationFilesCompleted = 5
        let result = p.verificationWeightedProgress
        XCTAssertGreaterThan(result, 0.0)
        XCTAssertLessThan(result, 1.0)
    }

    func test_verificationWeightedProgress_clampedTo1() {
        let p = TransferProgress()
        p.verificationFilesTotal = 5
        p.verificationFilesCompleted = 10
        XCTAssertEqual(p.verificationWeightedProgress, 1.0)
    }

    func test_verificationWeightedProgress_withBytesAndFiles_combinesBoth() {
        let p = TransferProgress()
        p.verificationBytesTotal = 100 * 1024 * 1024
        p.verificationBytesCompleted = 50 * 1024 * 1024
        p.verificationFilesTotal = 10
        p.verificationFilesCompleted = 5
        let result = p.verificationWeightedProgress
        XCTAssertEqual(result, 0.5, accuracy: 0.01)
    }

    // MARK: - verificationProgress (file-count only)

    func test_verificationProgress_noneCompleted_returns0() {
        let p = TransferProgress()
        p.verificationFilesTotal = 10
        p.verificationFilesCompleted = 0
        XCTAssertEqual(p.verificationProgress, 0.0)
    }

    func test_verificationProgress_allCompleted_returns1() {
        let p = TransferProgress()
        p.verificationFilesTotal = 10
        p.verificationFilesCompleted = 10
        XCTAssertEqual(p.verificationProgress, 1.0)
    }

    // MARK: - resetProgress

    func test_resetProgress_clearsAllState() {
        let p = TransferProgress()
        p.isRunning = true
        p.phase = .verifying
        p.verificationHasStarted = true
        p.verificationIsActive = true
        p.verificationBytesCompleted = 999
        p.verificationFilesCompleted = 5
        p.resetProgress()
        XCTAssertFalse(p.isRunning)
        XCTAssertEqual(p.phase, .idle)
        XCTAssertFalse(p.verificationHasStarted)
        XCTAssertFalse(p.verificationIsActive)
        XCTAssertEqual(p.verificationBytesCompleted, 0)
        XCTAssertEqual(p.verificationFilesCompleted, 0)
    }

    // MARK: - Verification flag behavior

    func test_verificationFlags_afterReset_areFalse() {
        let p = TransferProgress()
        p.verificationHasStarted = true
        p.verificationIsActive = true
        p.resetProgress()
        XCTAssertFalse(p.verificationHasStarted, "resetProgress must clear verificationHasStarted")
        XCTAssertFalse(p.verificationIsActive, "resetProgress must clear verificationIsActive")
    }

    // MARK: - Bytes-only verification

    func test_verificationWeightedProgress_withOnlyBytesNoFiles_returnsByteProgress() {
        let p = TransferProgress()
        p.verificationBytesTotal = 1000
        p.verificationBytesCompleted = 250
        let result = p.verificationWeightedProgress
        XCTAssertEqual(result, 0.25, accuracy: 0.01)
    }

    // MARK: - 1 GB+ file weight tier

    func test_verificationWeightedProgress_veryLargeFiles_bytesDominate() {
        // Average file = 2 GB → fileWeight = 0.05 (95% bytes weight)
        // bytes 100%, files 0% — maximises difference between old/new threshold.
        // Old fileWeight = 0.1:  0.9 × 1.0 + 0.1 × 0.0 = 0.90  → fails assert > 0.93
        // New fileWeight = 0.05: 0.95 × 1.0 + 0.05 × 0.0 = 0.95 → passes
        let p = TransferProgress()
        p.verificationBytesTotal = 10 * 1024 * 1024 * 1024  // 10 GB total (avg 2 GB/file)
        p.verificationBytesCompleted = 10 * 1024 * 1024 * 1024  // 100% bytes done
        p.verificationFilesTotal = 5
        p.verificationFilesCompleted = 0  // 0% files — stresses the blend
        XCTAssertGreaterThan(p.verificationWeightedProgress, 0.93)
    }
}
