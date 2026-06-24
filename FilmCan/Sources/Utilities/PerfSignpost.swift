import Foundation
import os

/// Names time spent in a nav region for both Instruments (os_signpost) and the
/// unified log. Exposes the currently-open region so MainThreadWatchdog can
/// label a stall with *what* froze. Logging a region's duration is gated to the
/// warn threshold so healthy paths stay quiet.
enum PerfSignpost {
    private static let log = OSLog(subsystem: "com.filmcan.app", category: "perf")
    private static let lock = NSLock()
    private static var _currentRegion = "idle"

    /// The currently-open region name, or "idle". Thread-safe.
    static var currentRegion: String {
        lock.lock(); defer { lock.unlock() }
        return _currentRegion
    }

    /// Pure gate so the threshold logic is unit-testable without wall-clock timing.
    static func shouldLogDuration(ms: Double, warnMs: Double = 100) -> Bool {
        ms >= warnMs
    }

    @discardableResult
    static func region<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        let label = name.withUTF8Buffer { String(decoding: $0, as: UTF8.self) }
        let previous = swapRegion(label)
        let start = DispatchTime.now()
        defer {
            _ = swapRegion(previous)
            os_signpost(.end, log: log, name: name, signpostID: id)
            let ms = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
            if shouldLogDuration(ms: ms) {
                DebugLog.warn("Perf region '\(label)' took \(Int(ms))ms")
            }
        }
        return try body()
    }

    private static func swapRegion(_ new: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let old = _currentRegion
        _currentRegion = new
        return old
    }
}
