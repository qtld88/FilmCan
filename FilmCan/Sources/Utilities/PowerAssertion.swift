import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac, and the drives attached to it, awake for the duration of a backup.
///
/// Without this a long copy is at the mercy of Energy Saver: the system sleeps while
/// idle (nobody touches the keyboard during a 3-hour offload), external drives spin
/// down, and on wake the transfer crawls while every drive spins back up. Observed
/// 2026-08-01: a run showing a 3-minute ETA reported 40+ minutes after a sleep/wake.
///
/// Two mechanisms, because they cover different things:
/// - `ProcessInfo.beginActivity` blocks idle *system* sleep and opts the app out of App
///   Nap, which would otherwise throttle a backgrounded app's timers and I/O.
/// - An `IOPMAssertion` of type `PreventDiskIdle` blocks idle *disk* spin-down, which
///   the activity API does not cover.
///
/// Neither prevents sleep from closing the lid or from the Apple menu. That is correct:
/// an explicit user request to sleep must still win.
final class PowerAssertion {
    static let shared = PowerAssertion()

    private let lock = NSLock()
    private var depth = 0
    private var activityToken: NSObjectProtocol?
    private var diskAssertionID: IOPMAssertionID = IOPMAssertionID(0)

    private init() {}

    /// Reference-counted so concurrent jobs each hold one and the last one out releases.
    /// Always pair with `release()`, ideally through `defer`.
    func acquire(reason: String = "FilmCan backup in progress") {
        lock.lock()
        defer { lock.unlock() }
        depth += 1
        guard depth == 1 else { return }

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: reason
        )

        // "PreventDiskIdle" is the assertion type behind `caffeinate -m`. Spelled out
        // because the Swift overlay does not surface a constant for it.
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            "PreventDiskIdle" as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if status == kIOReturnSuccess {
            diskAssertionID = id
        } else {
            // Not fatal: the system-sleep half still holds. Say so rather than pretend.
            DebugLog.warn("PreventDiskIdle assertion failed (IOReturn \(status)); drives may still spin down")
            diskAssertionID = IOPMAssertionID(0)
        }
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        guard depth > 0 else { return }
        depth -= 1
        guard depth == 0 else { return }

        if let token = activityToken {
            ProcessInfo.processInfo.endActivity(token)
            activityToken = nil
        }
        if diskAssertionID != IOPMAssertionID(0) {
            IOPMAssertionRelease(diskAssertionID)
            diskAssertionID = IOPMAssertionID(0)
        }
    }

    /// Test hook: whether an assertion is currently held.
    var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return depth > 0
    }
}
