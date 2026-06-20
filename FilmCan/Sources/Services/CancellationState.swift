import Foundation

/// Thread-safe cancel flag polled cooperatively by the fan-out engine. Cancel
/// only — the fan-out engine has no pause support, so pause is tracked on
/// `CustomCopierService` for the UI and never plumbed here.
final class CancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false

    func update(isCancelled: Bool) {
        lock.lock()
        self.isCancelled = isCancelled
        lock.unlock()
    }

    func isCancelledNow() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCancelled
    }
}
