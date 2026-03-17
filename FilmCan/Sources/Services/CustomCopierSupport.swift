import Foundation

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
}

final class ProgressThrottle {
    private let interval: TimeInterval
    private var lastUpdate: Date = .distantPast
    private let lock = NSLock()

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func shouldEmit(now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if now.timeIntervalSince(lastUpdate) >= interval {
            lastUpdate = now
            return true
        }
        return false
    }
}

actor VerificationByteCounter {
    private var completed: Int64 = 0

    func add(_ delta: Int64) -> Int64 {
        completed += delta
        return completed
    }

    func value() -> Int64 {
        completed
    }
}

actor VerificationProgressCounter {
    private var completed: Int = 0

    func increment(by delta: Int = 1) -> Int {
        completed += delta
        return completed
    }

    func value() -> Int {
        completed
    }
}

actor VerificationActivityCounter {
    private var active: Int = 0

    func increment() -> Int {
        active += 1
        return active
    }

    func decrement() -> Int {
        active = max(0, active - 1)
        return active
    }

    func value() -> Int {
        active
    }
}

actor CopyProgressTracker {
    private var total: Int64
    private var lastByFile: [String: Int64] = [:]
    private var finished: Set<String> = []

    init(startingBytes: Int64) {
        self.total = startingBytes
    }

    func update(fileId: String, bytes: Int64) -> Int64 {
        if finished.contains(fileId) { return total }
        let last = lastByFile[fileId] ?? 0
        guard bytes >= last else { return total }
        let delta = bytes - last
        lastByFile[fileId] = bytes
        total += delta
        return total
    }

    func finish(fileId: String) {
        lastByFile.removeValue(forKey: fileId)
        finished.insert(fileId)
    }

    func value() -> Int64 {
        total
    }
}

actor CopyFileCounter {
    private var total: Int

    init(startingFiles: Int) {
        self.total = startingFiles
    }

    func increment() -> Int {
        total += 1
        return total
    }

    func increment(by delta: Int) -> Int {
        total += delta
        return total
    }

    func value() -> Int {
        total
    }
}

actor PathCollector {
    private var paths: [String] = []

    func append(_ path: String) {
        paths.append(path)
    }

    func all() -> [String] {
        paths
    }
}

actor FailureCollector {
    private var failures: [String] = []

    func append(_ failure: String) {
        failures.append(failure)
    }

    func all() -> [String] {
        failures
    }
}

actor WarningCollector {
    private var warnings: [String] = []

    func append(_ warning: String) {
        warnings.append(warning)
    }

    func all() -> [String] {
        warnings
    }
}

actor CopyAbortState {
    private var errorMessage: String? = nil

    func setError(_ message: String) {
        if errorMessage == nil {
            errorMessage = message
        }
    }

    func message() -> String? {
        errorMessage
    }

    func shouldAbort() -> Bool {
        errorMessage != nil
    }
}

actor JobQueue {
    private let jobs: [CopyJob]
    private var index: Int = 0

    init(jobs: [CopyJob]) {
        self.jobs = jobs
    }

    func next() -> CopyJob? {
        guard index < jobs.count else { return nil }
        defer { index += 1 }
        return jobs[index]
    }
}

struct CopyJob {
    let entry: SourceFileEntry
    let destinationPath: String

    var fileName: String {
        (entry.sourcePath as NSString).lastPathComponent
    }
}
