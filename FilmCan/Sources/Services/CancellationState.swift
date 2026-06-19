import Foundation

/// Thread-safe cancel/pause flag polled cooperatively by the fan-out engine.
final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var isPaused = false

    func update(isCancelled: Bool, isPaused: Bool) {
        lock.lock()
        self.isCancelled = isCancelled
        self.isPaused = isPaused
        lock.unlock()
    }

    func shouldCancel() -> Bool {
        lock.lock()
        let result = isCancelled || isPaused
        lock.unlock()
        return result
    }

    /// Cancel only (ignores pause). The fan-out engine has no pause support, so
    /// it must abort on a real cancel but must NOT abort merely because paused.
    func isCancelledNow() -> Bool {
        lock.lock()
        let result = isCancelled
        lock.unlock()
        return result
    }
}
