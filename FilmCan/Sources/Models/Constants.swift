import Foundation

enum Constants {
    enum SlowestDestClass {
        case nvmeLocal
        case ssdLocal
        case hdd
        case exfat
        case network
        case unknown
    }

    static let speedDisparityWarnRatio: Double = 3.0
    static let freeSpaceHeadroomMultiplier: Double = 1.05
    static let localDestTimeoutSec: TimeInterval = 30.0
    static let networkDestTimeoutSec: TimeInterval = 120.0
    static let paranoidSourceSpeedThresholdMBps: Double = 100.0
    static let mhlFlushEveryFiles: Int = 5
    static let mhlFlushEveryBytes: Int64 = 5 * 1024 * 1024 * 1024

    static func ringCapBytesPerDest(
        physRamBytes: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> Int {
        // Buffer only needs to smooth read/write I/O jitter; a few tens of MB is
        // plenty. Capped low to keep the in-flight footprint small (this is per
        // destination, so it multiplies in parallel fan-out).
        let scaled = Int(physRamBytes / 128)
        let max = 96 * 1024 * 1024
        let min = 32 * 1024 * 1024
        if scaled > max { return max }
        if scaled < min { return min }
        return scaled
    }

    /// Flush the destination's dirty pages to the device every this many bytes
    /// during a large copy. Cached writes are fast but accumulate dirty pages in
    /// RAM; without periodic flushing a multi-hundred-GB copy creates system-wide
    /// memory pressure. Plain fsync (not F_FULLFSYNC) keeps this cheap.
    static let writeFlushEveryBytes: Int64 = 256 * 1024 * 1024

    /// How many finished files the copy lane may run ahead of the verify lane.
    ///
    /// The verify lane re-reads each destination from disk while the copy lane is still
    /// writing the next files. On one spindle both streams share a head, and run #2 of
    /// the HDD perf investigation measured 813 s of destination work inside a 555 s wall
    /// — proof they overlap, with both lanes losing ~45 % of their uncontended
    /// throughput. Lowering this bounds that overlap.
    ///
    /// Whether bounding it actually helps is **not yet measured**: phase separation and
    /// per-file alternation predict opposite results, and alternation may win because
    /// the head is already parked on the bytes just written. Default stays at the
    /// historical 64 (effectively unbounded) so shipped behaviour is unchanged; override
    /// with `FILMCAN_VERIFY_RUNAHEAD` to A/B it. See `docs/perf-hdd-fast-mode.md`.
    static func verifyRunAheadFiles(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        guard let raw = env["FILMCAN_VERIFY_RUNAHEAD"], let n = Int(raw), n >= 1 else {
            return 64
        }
        return n
    }

    static func chunkBytes(forSlowestDest dest: SlowestDestClass) -> Int {
        switch dest {
        case .nvmeLocal: return 16 * 1024 * 1024
        case .ssdLocal: return 8 * 1024 * 1024
        case .network: return 8 * 1024 * 1024
        case .hdd: return 4 * 1024 * 1024
        case .exfat: return 4 * 1024 * 1024
        case .unknown: return 4 * 1024 * 1024
        }
    }
}
