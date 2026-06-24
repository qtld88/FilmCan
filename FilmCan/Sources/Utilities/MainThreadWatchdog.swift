import Foundation

/// Detects main-thread stalls and logs them to DebugLog (captured by
/// `log stream --predicate 'subsystem == "com.filmcan.app"'`). Detection only —
/// never mutates UI, never blocks main, holds no view references. DEBUG-only use.
///
/// Mechanism: a background timer fires every ~50ms. Each fire, if no ping is
/// outstanding, it stamps a start time and schedules a trivial block on the main
/// queue that clears the ping. If a ping stays outstanding past a tier when the
/// next fire checks, a stall is logged (debounced once per tier per stall).
final class MainThreadWatchdog {
    enum Tier: Int, Equatable { case warn = 0, error = 1 }
    struct StallEvent: Equatable {
        let durationMs: Double
        let region: String
        let tier: Tier
    }

    static let shared = MainThreadWatchdog()

    /// Test seam — defaults to logging. Tests can swap this to capture events.
    var sink: (StallEvent) -> Void = { event in
        let msg = "MainThreadWatchdog: \(event.tier == .error ? "HANG" : "jank") "
            + "\(Int(event.durationMs))ms region='\(event.region)'"
        switch event.tier {
        case .warn:  DebugLog.warn(msg)
        case .error: DebugLog.error(msg)
        }
    }

    private let warnMs: Double = 100
    private let errorMs: Double = 500
    private let queue = DispatchQueue(label: "com.filmcan.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pingOutstanding = false
    private var pingStart = DispatchTime.now()
    private var lastReportedTier: Tier?

    /// Pure decision: given how long the outstanding ping has waited and the
    /// highest tier already reported for this stall, return an event to emit.
    static func evaluate(elapsedMs: Double,
                         lastReportedTier: Tier?,
                         warnMs: Double = 100,
                         errorMs: Double = 500) -> StallEvent? {
        let tier: Tier?
        if elapsedMs >= errorMs { tier = .error }
        else if elapsedMs >= warnMs { tier = .warn }
        else { tier = nil }
        guard let tier else { return nil }
        if let last = lastReportedTier, last.rawValue >= tier.rawValue { return nil }
        return StallEvent(durationMs: elapsedMs, region: "", tier: tier)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 0.05, repeating: 0.05)
            t.setEventHandler { [weak self] in self?.tick() }
            self.timer = t
            t.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func tick() {
        // Runs on `queue`. If a ping is outstanding, check elapsed and maybe emit.
        if pingOutstanding {
            let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- pingStart.uptimeNanoseconds) / 1_000_000
            if var event = Self.evaluate(elapsedMs: elapsedMs,
                                         lastReportedTier: lastReportedTier,
                                         warnMs: warnMs, errorMs: errorMs) {
                event = StallEvent(durationMs: event.durationMs,
                                   region: PerfSignpost.currentRegion,
                                   tier: event.tier)
                lastReportedTier = event.tier
                sink(event)
            }
            return  // wait for the in-flight ping to clear before stamping a new one
        }
        // No ping outstanding: stamp one and schedule its clear on main.
        pingOutstanding = true
        pingStart = DispatchTime.now()
        lastReportedTier = nil
        DispatchQueue.main.async { [weak self] in
            self?.queue.async { self?.pingOutstanding = false }
        }
    }
}
