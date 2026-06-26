import XCTest
@testable import FilmCan

final class RereadProgressTests: XCTestCase {

    private actor Collector {
        var values: [Int64] = []
        func add(_ v: Int64) { values.append(v) }
    }

    func test_rereadHashDetached_reportsIncreasingCumulativeBytes() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("reread-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 4 MiB of data, reporting every 1 MiB → expect ≥2 progress reports.
        let size = 4 * 1024 * 1024
        let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        try data.write(to: tmp)

        let collector = Collector()
        let hash = await FanOutCopier.rereadHashDetached(
            url: tmp, chunkSz: 64 * 1024,
            reportEveryBytes: 1 * 1024 * 1024,
            onProgress: { await collector.add($0) }
        )

        let values = await collector.values
        XCTAssertNotNil(hash, "hash should be produced")
        XCTAssertGreaterThanOrEqual(values.count, 2, "should report progress more than once")
        XCTAssertEqual(values, values.sorted(), "cumulative bytes must be non-decreasing")
        XCTAssertEqual(values.last, Int64(size), "final report must equal file size")
    }
}
