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
    /// Measured on a USB HDD, 25 043 MB over 10 mixed-size clips, same drive and source
    /// throughout (runs #4 and #5, 2026-08-01):
    ///
    /// | depth | wall | dest write | verify re-read | dest aggregate |
    /// |---|---|---|---|---|
    /// | 4 | 560.8 s | 55.9 MB/s | 63.8 MB/s | 89.31 MB/s |
    /// | 1 | **513.1 s** | **71.2 MB/s** | **84.5 MB/s** | **97.63 MB/s** |
    ///
    /// Both destination lanes gained ~30 % while `source read` stayed flat at 89.6 →
    /// 89.7 MB/s, which locates the contention at the destination head rather than the
    /// bus or the source. Net −8.5 % wall, 1.97× → 1.80× versus Finder.
    ///
    /// Only the rotational classes get the low depth. A depth of 1 has **not** been
    /// measured on SSD or NVMe, where there is no seek penalty to avoid and serialising
    /// could only cost overlap, so those keep the historical 64. `.unknown` is grouped
    /// with the rotational classes for the same reason `chunkBytes` does it: an
    /// unidentified enclosure is assumed slow.
    ///
    /// `FILMCAN_VERIFY_RUNAHEAD` still overrides everything, for further A/Bs.
    static func verifyRunAheadFiles(
        forSlowestDest dest: SlowestDestClass,
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int {
        if let raw = env["FILMCAN_VERIFY_RUNAHEAD"], let n = Int(raw), n >= 1 { return n }
        switch dest {
        case .hdd, .exfat, .unknown: return 1
        case .ssdLocal, .nvmeLocal, .network: return 64
        }
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
