import Foundation

/// Wall-clock and byte accounting for the copy engine's I/O buckets, so a slow
/// destination can be attributed to a specific bucket (write, verify re-read,
/// drive cache flush) instead of guessed at.
///
/// Enabled only when the `FILMCAN_IO_PERF` environment variable is `1`, so a
/// normal run pays one bool read per call site.
///
/// Lock-based rather than an actor on purpose: recording happens inside the
/// per-chunk write loop and inside `DestWriter.finalize`, both synchronous.
/// An actor hop there would perturb the very timings being measured.
final class IOPerfProbe: @unchecked Sendable {
    enum Bucket: String, CaseIterable {
        case sourceRead = "source read"
        case sourceHash = "source hash"
        case destWrite = "dest write"
        case destHash = "dest hash"
        case flush = "cache flush"
        case rename = "rename"
        case tempCreate = "temp create"
        case verifyRead = "verify re-read"
        case verifyHash = "verify hash"
        case mhlRender = "mhl render"
        case settleSleep = "settle sleep"
    }

    struct Stat: Equatable {
        var nanos: UInt64 = 0
        var bytes: Int64 = 0
        var calls: Int = 0
        var maxNanos: UInt64 = 0

        mutating func record(nanos n: UInt64, bytes b: Int64) {
            nanos &+= n
            bytes &+= b
            calls += 1
            if n > maxNanos { maxNanos = n }
        }
    }

    static let shared = IOPerfProbe()

    let isEnabled: Bool

    private let lock = NSLock()
    private var stats: [String: [Bucket: Stat]] = [:]
    private var runStart: DispatchTime?

    init(enabled: Bool = ProcessInfo.processInfo.environment["FILMCAN_IO_PERF"] == "1") {
        self.isEnabled = enabled
    }

    /// Clear counters and start the wall clock for a run.
    func begin() {
        guard isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        stats.removeAll()
        runStart = DispatchTime.now()
    }

    func record(_ bucket: Bucket, key: String, nanos: UInt64, bytes: Int64) {
        guard isEnabled else { return }
        lock.lock(); defer { lock.unlock() }
        stats[key, default: [:]][bucket, default: Stat()].record(nanos: nanos, bytes: bytes)
    }

    @inline(__always)
    func measure<T>(
        _ bucket: Bucket, key: String, bytes: Int64 = 0, _ body: () throws -> T
    ) rethrows -> T {
        guard isEnabled else { return try body() }
        let t0 = DispatchTime.now()
        defer {
            record(bucket, key: key,
                   nanos: DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds,
                   bytes: bytes)
        }
        return try body()
    }

    func measureAsync<T>(
        _ bucket: Bucket, key: String, bytes: Int64 = 0, _ body: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await body() }
        let t0 = DispatchTime.now()
        defer {
            record(bucket, key: key,
                   nanos: DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds,
                   bytes: bytes)
        }
        return try await body()
    }

    func snapshot() -> [String: [Bucket: Stat]] {
        lock.lock(); defer { lock.unlock() }
        return stats
    }

    func elapsedSeconds() -> Double {
        lock.lock(); defer { lock.unlock() }
        guard let runStart else { return 0 }
        return Double(DispatchTime.now().uptimeNanoseconds &- runStart.uptimeNanoseconds) / 1_000_000_000
    }

    /// Pure formatter, so the summary layout is unit-testable without wall-clock timing.
    static func summaryText(stats: [String: [Bucket: Stat]], wallSeconds: Double) -> String {
        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
        }
        var out = String(format: "=== FilmCan I/O perf — wall %.1fs ===\n", wallSeconds)
        for key in stats.keys.sorted() {
            out += "[\(key)]\n"
            let buckets = stats[key] ?? [:]
            for bucket in Bucket.allCases {
                guard let s = buckets[bucket], s.calls > 0 else { continue }
                let sec = Double(s.nanos) / 1_000_000_000
                let meanMs = (Double(s.nanos) / Double(s.calls)) / 1_000_000
                let maxMs = Double(s.maxNanos) / 1_000_000
                var line = "  " + pad(bucket.rawValue, 15)
                line += String(format: "%8.2fs  n=%-6d mean=%8.3fms  max=%9.2fms",
                               sec, s.calls, meanMs, maxMs)
                if s.bytes > 0, sec > 0 {
                    line += String(format: "  %8.1f MB/s", Double(s.bytes) / sec / (1024 * 1024))
                }
                out += line + "\n"
            }
        }
        return out
    }

    func logSummary() {
        guard isEnabled else { return }
        DebugLog.info(Self.summaryText(stats: snapshot(), wallSeconds: elapsedSeconds()))
    }
}
