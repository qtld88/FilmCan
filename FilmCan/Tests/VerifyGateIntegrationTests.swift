import XCTest
@testable import FilmCan

/// The copy/verify completion gate makes the copy lane block until the verify lane
/// finishes each file. Every one of these tests is a deadlock probe: the verify lane
/// must emit exactly one token per file it dequeues, on every path, or the copy lane
/// waits forever. `XCTestCase` would hang rather than fail, so each test is wrapped in
/// an explicit timeout that turns a hang into a readable failure.
final class VerifyGateIntegrationTests: XCTestCase {

    private func makeTree(_ label: String, files: Int, bytes: Int) throws
        -> (tmp: URL, src: URL, dst: URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-gate-\(label)-\(UUID().uuidString)")
        let src = tmp.appendingPathComponent("src")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        for i in 0..<files {
            try Data(repeating: UInt8(i & 0xFF), count: bytes)
                .write(to: src.appendingPathComponent(String(format: "A%03d.mov", i)))
        }
        return (tmp, src, dst)
    }

    private func gatedConfig(src: URL, dst: URL,
                             verifyMode: VerifyMode = .paranoid) -> FanOutCopier.Configuration {
        var cfg = FanOutCopier.Configuration(
            sources: [src.path],
            destinations: [DestWriter.Config(
                destPath: dst.path, displayName: "dst",
                verifyMode: verifyMode, requiresFullFsync: false, chunkSize: nil)],
            verifyMode: verifyMode, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        cfg._testForceVerifyGate = true
        return cfg
    }

    struct DeadlockTimeout: Error {}

    /// Reports a wedged copy lane as a test failure instead of hanging the suite.
    ///
    /// The work runs in a **detached, deliberately un-awaited** task. A task group
    /// cannot be used here: `BoundedChannel` parks on `withCheckedContinuation`, which
    /// ignores cancellation, so a deadlocked child is unreapable and the group would
    /// hang at scope exit waiting for it — swallowing the very failure being probed.
    /// (Confirmed by sabotaging the token emit: the task-group version hung, this one
    /// fails.) Leaking the stuck task is the price of getting a readable result.
    private func withDeadlockTimeout<T: Sendable>(
        _ seconds: Double = 45,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let box = ResultBox<T>()
        Task.detached {
            do { box.set(.success(try await body())) }
            catch { box.set(.failure(error)) }
        }
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let r = box.value { return try r.get() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("copy lane did not finish in \(seconds)s — the verify lane skipped a "
                + "completion token and the gate deadlocked", file: file, line: line)
        throw DeadlockTimeout()
    }

    // MARK: - happy path

    func test_gatedRun_copiesAndVerifiesEveryFile() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let t = try makeTree("ok", files: 6, bytes: 64 * 1024)
        defer { try? FileManager.default.removeItem(at: t.tmp) }

        let cfg = gatedConfig(src: t.src, dst: t.dst)
        let results = try await withDeadlockTimeout { try await FanOutCopier(config: cfg).run() }

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success, "gated run should succeed like an ungated one")
        XCTAssertEqual(results[0].filesTransferred, 6,
                       "the gate must not drop files from the pipeline")
    }

    /// The gate must not change *what* lands on disk, only when. Same tree, gate off,
    /// must produce the same file set and bytes.
    func test_gatedRun_producesTheSameBytesAsUngated() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let gated = try makeTree("cmp-on", files: 4, bytes: 32 * 1024)
        let plain = try makeTree("cmp-off", files: 4, bytes: 32 * 1024)
        defer {
            try? FileManager.default.removeItem(at: gated.tmp)
            try? FileManager.default.removeItem(at: plain.tmp)
        }

        let onCfg = gatedConfig(src: gated.src, dst: gated.dst)
        var offCfg = gatedConfig(src: plain.src, dst: plain.dst)
        offCfg._testForceVerifyGate = false

        let onResults = try await withDeadlockTimeout { try await FanOutCopier(config: onCfg).run() }
        let offResults = try await FanOutCopier(config: offCfg).run()

        XCTAssertEqual(onResults[0].filesTransferred, offResults[0].filesTransferred)
        XCTAssertEqual(onResults[0].bytesTransferred, offResults[0].bytesTransferred)

        func fileNames(_ root: URL) throws -> [String] {
            try FileManager.default
                .subpathsOfDirectory(atPath: root.path)
                .filter { !$0.hasPrefix(".") && !$0.contains("/.") && $0.hasSuffix(".mov") }
                .sorted()
        }
        XCTAssertEqual(try fileNames(gated.dst).map { ($0 as NSString).lastPathComponent },
                       try fileNames(plain.dst).map { ($0 as NSString).lastPathComponent })
    }

    // MARK: - the paths that skip the normal end of the verify body

    /// Before the gate, `drainVerifies` used `continue` to short-circuit the MHL-append
    /// failure case. Under the gate that early exit would skip the completion token and
    /// wedge the copy lane, which is why the body was factored into `verifyOne`.
    func test_gatedRun_mhlAppendFailureStillReleasesTheCopyLane() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let t = try makeTree("mhlfail", files: 4, bytes: 32 * 1024)
        defer { try? FileManager.default.removeItem(at: t.tmp) }

        var cfg = gatedConfig(src: t.src, dst: t.dst)
        cfg._testForceMHLAppendFailure = true

        let results = try await withDeadlockTimeout { try await FanOutCopier(config: cfg).run() }
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success,
                       "a failed manifest write must still be reported as a failure")
    }

    /// A destination that cannot be read back fails verification for every file. The
    /// lane must keep emitting tokens through all of them.
    func test_gatedRun_verifyFailureOnEveryFileDoesNotWedge() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let t = try makeTree("verifyfail", files: 4, bytes: 32 * 1024)
        defer { try? FileManager.default.removeItem(at: t.tmp) }

        var cfg = gatedConfig(src: t.src, dst: t.dst)
        cfg._testForceDestReadHashNil = true

        let results = try await withDeadlockTimeout { try await FanOutCopier(config: cfg).run() }
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success,
                       "unverifiable destination reads must fail the destination")
    }

    // MARK: - cancel

    /// Cancelling stops `enqueueNext` from starting new files, but files already in
    /// flight still hand off to the verify lane. The gate must not turn that drain
    /// into a hang.
    func test_gatedRun_cancelMidRunTerminates() async throws {
        guard XXH128StreamingHasher() != nil else { throw XCTSkip("no libxxhash") }
        let t = try makeTree("cancel", files: 12, bytes: 256 * 1024)
        defer { try? FileManager.default.removeItem(at: t.tmp) }

        let cancelAfter = 2
        let seen = Counter()
        var cfg = gatedConfig(src: t.src, dst: t.dst)
        cfg.shouldCancel = { seen.value >= cancelAfter }
        cfg.progressHandler = { _ in seen.bump() }

        _ = try? await withDeadlockTimeout { try await FanOutCopier(config: cfg).run() }
        // Reaching here at all is the assertion: a wedged lane would have tripped the
        // timeout and thrown out of `withDeadlockTimeout` as a failure, not a cancel.
    }
}

/// Minimal thread-safe counter — the progress handler is called from the copier's
/// tasks, and `shouldCancel` is read from another.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
}

/// Hand-off slot between the detached work task and the polling deadline loop.
private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<T, Error>?
    var value: Result<T, Error>? { lock.lock(); defer { lock.unlock() }; return stored }
    func set(_ r: Result<T, Error>) { lock.lock(); stored = r; lock.unlock() }
}
