import XCTest
@testable import FilmCan

final class IOPerfProbeTests: XCTestCase {
    func testDisabledProbeRunsBodyAndRecordsNothing() {
        let probe = IOPerfProbe(enabled: false)
        var ran = false
        probe.measure(.destWrite, key: "d", bytes: 10) { ran = true }
        XCTAssertTrue(ran)
        XCTAssertTrue(probe.snapshot().isEmpty)
    }

    func testEnabledProbeRecordsCallsBytesAndMax() {
        let probe = IOPerfProbe(enabled: true)
        probe.begin()
        probe.record(.flush, key: "HDD", nanos: 5_000_000, bytes: 0)
        probe.record(.flush, key: "HDD", nanos: 15_000_000, bytes: 0)
        let stat = probe.snapshot()["HDD"]?[.flush]
        XCTAssertEqual(stat?.calls, 2)
        XCTAssertEqual(stat?.nanos, 20_000_000)
        XCTAssertEqual(stat?.maxNanos, 15_000_000)
    }

    func testMeasurePropagatesThrownError() {
        struct Boom: Error {}
        let probe = IOPerfProbe(enabled: true)
        XCTAssertThrowsError(try probe.measure(.destWrite, key: "d") { throw Boom() })
        XCTAssertEqual(probe.snapshot()["d"]?[.destWrite]?.calls, 1)
    }

    func testSummaryTextReportsBucketsAndThroughput() {
        var stat = IOPerfProbe.Stat()
        stat.record(nanos: 2_000_000_000, bytes: 200 * 1024 * 1024)
        let text = IOPerfProbe.summaryText(
            stats: ["HDD": [.destWrite: stat]], wallSeconds: 10)
        XCTAssertTrue(text.contains("[HDD]"))
        XCTAssertTrue(text.contains("dest write"))
        XCTAssertTrue(text.contains("MB/s"))
    }

    func testSummaryTextSkipsEmptyBuckets() {
        let text = IOPerfProbe.summaryText(
            stats: ["HDD": [.flush: IOPerfProbe.Stat()]], wallSeconds: 1)
        XCTAssertFalse(text.contains("cache flush"))
    }
}
