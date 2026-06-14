import XCTest
@testable import FilmCan

/// Unit tests for the combined-throughput speed/ETA math (FanOutCopier).
final class CombinedSpeedETATests: XCTestCase {

    private let GB: Int64 = 1_000_000_000

    /// Paranoid: ETA must count the verify pass from the start, so even with
    /// nothing verified yet it reports ~2x the copy-only time — never the
    /// optimistic copy-only estimate.
    func test_paranoid_etaIsHonestFromStart() {
        // 459 GB job, 48 GB copied, 0 verified, 160s elapsed → ~300 MB/s copy.
        let copyTotal = 459 * GB
        let r = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 48 * GB, verifyDone: 0,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 160)

        // Combined throughput = 48GB/160s = 300 MB/s; ÷ factor 2 → 150 MB/s shown.
        XCTAssertEqual(r.speed, 150_000_000, accuracy: 1_000_000)

        // ETA = remaining combined work (918-48=870 GB) / 300 MB/s = 2900s.
        let eta = try! XCTUnwrap(r.eta)
        XCTAssertEqual(eta, 2900, accuracy: 30)

        // It must be ~2x the naive copy-only ETA (remaining copy / copy rate).
        let copyOnlyEta = Double((copyTotal - 48 * GB)) / 300_000_000
        XCTAssertGreaterThan(eta, copyOnlyEta * 1.8)
    }

    /// Fast mode: no verify pass, so factor is 1 — speed is the plain copy rate
    /// and ETA covers copy only.
    func test_fast_factorOne() {
        let copyTotal = 100 * GB
        let r = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 50 * GB, verifyDone: 0,
            copyTotal: copyTotal, verifyTotal: 0, elapsed: 100)
        // 50GB/100s = 500 MB/s, factor 1.
        XCTAssertEqual(r.speed, 500_000_000, accuracy: 1_000_000)
        // ETA = remaining 50GB / 500 MB/s = 100s.
        XCTAssertEqual(try! XCTUnwrap(r.eta), 100, accuracy: 2)
    }

    /// The total throughput is stable across the verify swing, so the ETA does
    /// not lurch: copy-fast/verify-idle vs copy-slow/verify-active produce the
    /// same combined throughput and therefore the same ETA.
    func test_etaStableAcrossVerifySwing() {
        let copyTotal = 100 * GB
        // Snapshot A: copy ran ahead, verify idle. 60 copied, 30 verified, 30s.
        let a = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 60 * GB, verifyDone: 30 * GB,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 30)
        // Snapshot B: same combined work (90 GB) at same elapsed, split
        // differently (verify caught up). ETA must match A.
        let b = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 50 * GB, verifyDone: 40 * GB,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 30)
        XCTAssertEqual(try! XCTUnwrap(a.eta), try! XCTUnwrap(b.eta), accuracy: 0.001)
    }

    /// ETA decreases as combined work advances at a steady throughput (never
    /// climbs).
    func test_etaDecreasesAsWorkAdvances() {
        let copyTotal = 100 * GB
        // Steady 1 GB/s combined throughput at three points in time.
        let t1 = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 10 * GB, verifyDone: 0,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 10)
        let t2 = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 50 * GB, verifyDone: 30 * GB,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 80)
        let t3 = FanOutCopier.computeCombinedSpeedETA(
            copyDone: 100 * GB, verifyDone: 80 * GB,
            copyTotal: copyTotal, verifyTotal: copyTotal, elapsed: 180)
        XCTAssertGreaterThan(try! XCTUnwrap(t1.eta), try! XCTUnwrap(t2.eta))
        XCTAssertGreaterThan(try! XCTUnwrap(t2.eta), try! XCTUnwrap(t3.eta))
    }

    func test_guards_returnNoneBeforeData() {
        XCTAssertNil(FanOutCopier.computeCombinedSpeedETA(
            copyDone: 0, verifyDone: 0, copyTotal: 100, verifyTotal: 100, elapsed: 0).eta)
        XCTAssertNil(FanOutCopier.computeCombinedSpeedETA(
            copyDone: 0, verifyDone: 0, copyTotal: 100, verifyTotal: 100, elapsed: 5).eta)
    }
}
