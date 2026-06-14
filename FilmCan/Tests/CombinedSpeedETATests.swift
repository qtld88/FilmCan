import XCTest
@testable import FilmCan

/// Unit tests for the combined-throughput speed/ETA math (FanOutCopier).
/// `throughput` is the measured combined (copy+verify) bytes/sec from the
/// sliding window; these test the pure conversion to displayed speed and ETA.
final class CombinedSpeedETATests: XCTestCase {

    private let GB: Int64 = 1_000_000_000

    /// Paranoid: combinedTotal is 2x data, so the ETA counts the verify pass —
    /// never the optimistic copy-only estimate — and the speed is the effective
    /// copy rate (throughput ÷ 2), not the measured throughput.
    func test_paranoid_speedHalvedAndEtaCountsVerify() {
        let copyTotal = 459 * GB
        // 300 MB/s combined throughput, 48 GB combined done.
        let r = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 48 * GB, combinedTotal: 2 * copyTotal,
            copyTotal: copyTotal, throughput: 300_000_000)

        // Effective copy rate = 300 / 2 = 150 MB/s.
        XCTAssertEqual(r.speed, 150_000_000, accuracy: 1_000_000)
        // ETA = remaining combined (918-48=870 GB) / 300 MB/s = 2900s.
        XCTAssertEqual(try XCTUnwrap(r.eta), 2900, accuracy: 1)
        // ~2x the naive copy-only ETA (remaining copy / throughput).
        let copyOnly = Double(copyTotal - 48 * GB) / 300_000_000
        XCTAssertGreaterThan(try XCTUnwrap(r.eta), copyOnly * 1.8)
    }

    /// Fast mode: combinedTotal == copyTotal (factor 1) — speed equals the
    /// measured throughput and the ETA covers copy only.
    func test_fast_factorOne() {
        let copyTotal = 100 * GB
        let r = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 50 * GB, combinedTotal: copyTotal,
            copyTotal: copyTotal, throughput: 500_000_000)
        XCTAssertEqual(r.speed, 500_000_000, accuracy: 1_000_000)
        XCTAssertEqual(try XCTUnwrap(r.eta), 100, accuracy: 1) // 50GB / 500MB/s
    }

    /// At a steady throughput the ETA decreases as combined work advances.
    func test_etaDecreasesAsWorkAdvances() {
        let copyTotal = 100 * GB
        let total = 2 * copyTotal
        let a = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 10 * GB, combinedTotal: total, copyTotal: copyTotal, throughput: 1_000_000_000)
        let b = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 80 * GB, combinedTotal: total, copyTotal: copyTotal, throughput: 1_000_000_000)
        let c = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 180 * GB, combinedTotal: total, copyTotal: copyTotal, throughput: 1_000_000_000)
        XCTAssertGreaterThan(try XCTUnwrap(a.eta), try XCTUnwrap(b.eta))
        XCTAssertGreaterThan(try XCTUnwrap(b.eta), try XCTUnwrap(c.eta))
    }

    /// The ETA depends only on remaining work and throughput, not on how the
    /// done work splits between copy and verify — so it is stable across the
    /// verify swing (same combinedDone + throughput → same ETA).
    func test_etaStableRegardlessOfCopyVerifySplit() {
        let copyTotal = 100 * GB
        let total = 2 * copyTotal
        let a = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 90 * GB, combinedTotal: total, copyTotal: copyTotal, throughput: 3_000_000_000)
        let b = FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 90 * GB, combinedTotal: total, copyTotal: copyTotal, throughput: 3_000_000_000)
        XCTAssertEqual(try XCTUnwrap(a.eta), try XCTUnwrap(b.eta), accuracy: 0.001)
    }

    func test_guards_returnNoneOnZeroThroughput() {
        XCTAssertNil(FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 10, combinedTotal: 100, copyTotal: 100, throughput: 0).eta)
        XCTAssertNil(FanOutCopier.computeCombinedSpeedETA(
            combinedDone: 0, combinedTotal: 100, copyTotal: 100, throughput: 100).eta)
    }
}
