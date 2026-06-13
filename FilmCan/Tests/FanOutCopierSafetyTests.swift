import XCTest
@testable import FilmCan

/// Thread-safe cancel flag for driving FanOutCopier.Configuration.shouldCancel.
private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func set() { lock.lock(); cancelled = true; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

/// Deliberate-fault and performance tests for the fan-out engine.
/// These hit real temp dirs (and, where noted, a real small disk image) and
/// inject errors to prove the safety contracts hold and that copy throughput
/// has not regressed (e.g. an accidental re-introduction of F_NOCACHE).
final class FanOutCopierSafetyTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fanout-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir = tmpDir {
            // Restore perms in case a test left a dir read-only, so removal works.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: tmpDir.path)
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    // MARK: - Helpers

    /// Fast random fill (per-byte `UInt8.random` is far too slow for >100MB).
    private func randomData(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        return Data(bytes)
    }

    // MARK: - Performance regression

    /// Pure copy throughput (fast verify = no re-read). Catches the F_NOCACHE
    /// regression that capped SSD→SSD at ~160 MB/s. Floor is deliberately well
    /// below real Apple-SSD speed (multi-GB/s) but well above the bug.
    func test_perf_throughput_fastMode_aboveFloor() async throws {
        let sizeBytes = 128 * 1024 * 1024 // 128 MB
        let sourceURL = tmpDir.appendingPathComponent("perf-source.bin")
        try randomData(sizeBytes).write(to: sourceURL)

        let dest = tmpDir.appendingPathComponent("perf-dest")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: dest.path, displayName: "Perf",
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: nil)
            ],
            verifyMode: .fast,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let start = Date()
        let results = try await FanOutCopier(config: config).run()
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)

        let mbps = (Double(sizeBytes) / (1024 * 1024)) / elapsed
        print(String(format: "⏱  fan-out copy throughput: %.0f MB/s (%d MB in %.3fs)",
                     mbps, sizeBytes / (1024 * 1024), elapsed))

        XCTAssertGreaterThan(mbps, 400,
            "Copy throughput \(Int(mbps)) MB/s below floor — possible F_NOCACHE / caching regression")
    }

    // MARK: - Safety: unwritable destination

    /// A read-only destination must abort the run with a clear error and must
    /// NOT leave a partially-copied data file at a good sibling destination.
    func test_safety_unwritableDestination_abortsWithoutCopyingData() async throws {
        let fm = FileManager.default
        let sourceURL = tmpDir.appendingPathComponent("src.bin")
        try randomData(512 * 1024).write(to: sourceURL)

        let goodDest = tmpDir.appendingPathComponent("good-dest")
        let badDest = tmpDir.appendingPathComponent("bad-dest")
        try fm.createDirectory(at: goodDest, withIntermediateDirectories: true)
        try fm.createDirectory(at: badDest, withIntermediateDirectories: true)
        // Make the bad dest read-only so .filmcan/MHL scaffolding can't be created.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: badDest.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: badDest.path) }

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: goodDest.path, displayName: "Good",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: nil),
                DestWriter.Config(destPath: badDest.path, displayName: "Bad",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: nil)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        do {
            _ = try await FanOutCopier(config: config).run()
            XCTFail("Run should throw when a destination is unwritable")
        } catch {
            // Expected — any thrown error is acceptable here.
        }

        // Safety contract: no real data file copied to the good dest on a
        // setup-time failure.
        let copied = goodDest.appendingPathComponent("src.bin")
        XCTAssertFalse(fm.fileExists(atPath: copied.path),
                       "No data must be copied when the run aborts at setup")
        // And no orphaned temp files anywhere under the good dest.
        if let items = try? fm.contentsOfDirectory(atPath: goodDest.path) {
            XCTAssertFalse(items.contains { $0.hasPrefix(".filmcan-") },
                           "No leftover temp files at good dest")
        }
    }

    // MARK: - Safety: cancellation

    /// Cancelling mid-copy must abort promptly and leave NO final file and NO
    /// orphaned temp file at the destination. The cancel flag is flipped on the
    /// first progress emit (called synchronously from the writer), so the writer
    /// hits its pre-finalize cancel check before renaming temp → final.
    func test_cancel_midCopy_abortsWithoutFinalFileOrTemp() async throws {
        let fm = FileManager.default
        let sourceURL = tmpDir.appendingPathComponent("cancel-src.bin")
        try randomData(64 * 1024 * 1024).write(to: sourceURL)

        let dest = tmpDir.appendingPathComponent("cancel-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let box = CancelBox()
        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: dest.path, displayName: "C",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 65536)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: { _ in box.set() },
            shouldCancel: { box.get() }
        )

        let results = try await FanOutCopier(config: config).run()

        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("cancel-src.bin").path),
                       "Cancelled copy must not leave a finalized file")
        let items = (try? fm.contentsOfDirectory(atPath: dest.path)) ?? []
        XCTAssertFalse(items.contains { $0.hasPrefix(".filmcan-") },
                       "Cancelled copy must not leave a temp file (DestWriter.deinit cleans it)")
        XCTAssertTrue(results.allSatisfy { !$0.success },
                      "A cancelled destination must not report success")
    }

    // MARK: - Safety: insufficient space (real small disk image)

    /// Pre-flight must throw `insufficientSpace` and write NOTHING when the
    /// destination volume is too small for the payload. Uses a real ~12 MB
    /// disk image. Skips (not fails) if hdiutil isn't usable in this environment.
    func test_safety_insufficientSpace_onSmallVolume() async throws {
        let fm = FileManager.default

        // 12 MB volume, then try to copy a 40 MB payload into it.
        let imagePath = tmpDir.appendingPathComponent("tiny.dmg").path
        guard let mountPoint = try makeSmallVolume(imagePath: imagePath, megabytes: 12) else {
            throw XCTSkip("hdiutil not available / could not create test volume")
        }
        defer { detachVolume(mountPoint: mountPoint) }

        let sourceURL = tmpDir.appendingPathComponent("big.bin")
        try randomData(40 * 1024 * 1024).write(to: sourceURL)

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: mountPoint, displayName: "Tiny",
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: nil)
            ],
            verifyMode: .fast,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        do {
            _ = try await FanOutCopier(config: config).run()
            XCTFail("Should throw insufficientSpace")
        } catch let err as FanOutCopier.Error {
            switch err {
            case .insufficientSpace(let destPath, let available, let required):
                XCTAssertEqual(destPath, mountPoint)
                XCTAssertLessThan(available, required, "available must be < required")
            default:
                XCTFail("Wrong error: \(err)")
            }
        }

        // Nothing must have been written to the tiny volume.
        let copied = (mountPoint as NSString).appendingPathComponent("big.bin")
        XCTAssertFalse(fm.fileExists(atPath: copied),
                       "No data must be written when pre-flight rejects for space")
    }

    // MARK: - hdiutil helpers

    private func makeSmallVolume(imagePath: String, megabytes: Int) throws -> String? {
        let volName = "FCTiny-\(UUID().uuidString.prefix(8))"
        let create = Process()
        create.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        create.arguments = [
            "create", "-size", "\(megabytes)m", "-fs", "APFS",
            "-volname", String(volName), "-ov", imagePath
        ]
        try? create.run()
        create.waitUntilExit()
        guard create.terminationStatus == 0 else { return nil }

        let attach = Process()
        attach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        attach.arguments = ["attach", imagePath, "-nobrowse"]
        let pipe = Pipe()
        attach.standardOutput = pipe
        try? attach.run()
        attach.waitUntilExit()
        guard attach.terminationStatus == 0 else { return nil }

        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Last whitespace-separated field of the matching line is the mount point.
        for line in out.split(separator: "\n") where line.contains("/Volumes/") {
            if let range = line.range(of: "/Volumes/") {
                return String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func detachVolume(mountPoint: String) {
        let detach = Process()
        detach.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        detach.arguments = ["detach", mountPoint, "-force"]
        try? detach.run()
        detach.waitUntilExit()
    }
}
