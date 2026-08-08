import XCTest
@testable import FilmCan

/// Regression guards for two shipped-in-1.3.2 defects:
///  - new configs silently defaulted to Paranoid verify
///  - disk-space preflight under-reported free space on APFS (purgeable),
///    falsely blocking valid backups
final class SpaceAndDefaultsRegressionTests: XCTestCase {

    // Bug 1: a brand-new backup must default to Fast verify, not Paranoid.
    func test_newBackup_defaultsToFastVerify() {
        XCTAssertEqual(EngineOptions().verificationMode, .fast)
        XCTAssertEqual(BackupConfiguration().engineOptions.verificationMode, .fast)
    }

    // Bug 2 (final design — Optimistic + no-fail): the user-facing figure is
    // optimistic (Finder/ImportantUsage, includes purgeable) so we don't
    // false-block; the engine separately reclaims purgeable space before writing.
    // Guards: liveAvailableBytes tracks the LARGER (purgeable-inclusive) figure,
    // while immediatelyWritableBytes is the conservative statfs number, and the
    // optimistic figure is never smaller than the conservative one.
    func test_spaceMetrics_optimisticVsImmediatelyWritable() throws {
        let path = NSTemporaryDirectory()

        let strictStatfs = try XCTUnwrap(
            (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemFreeSize] as? Int64,
            "expected statfs free size on the temp volume")
        let importantUsage: Int64? = (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage

        let optimistic = try XCTUnwrap(DriveUtilities.liveAvailableBytes(for: path))
        let writableNow = try XCTUnwrap(DriveUtilities.immediatelyWritableBytes(for: path))
        XCTAssertGreaterThan(optimistic, 0)
        XCTAssertGreaterThan(writableNow, 0)

        let slack: Int64 = 8 * 1024 * 1024
        // Conservative metric tracks statfs.
        XCTAssertLessThanOrEqual(abs(writableNow - strictStatfs), slack)
        // Optimistic is never smaller than immediately-writable.
        XCTAssertGreaterThanOrEqual(optimistic + slack, writableNow)
        // When purgeable exists, optimistic should track the larger ImportantUsage.
        if let importantUsage {
            XCTAssertGreaterThanOrEqual(optimistic + slack, importantUsage)
        }
    }
    // MARK: - verify run-ahead depth

    func test_verifyRunAhead_rotationalClassesSerialiseByDefault() {
        // Measured -8.5% on HDD (runs #4 vs #5). Unknown is grouped with rotational,
        // matching chunkBytes: an unidentified enclosure is assumed slow.
        for dest in [Constants.SlowestDestClass.hdd, .exfat, .unknown] {
            XCTAssertEqual(Constants.verifyRunAheadFiles(forSlowestDest: dest, env: [:]), 1,
                           "\(dest) should bound the verify run-ahead")
        }
    }

    func test_verifyRunAhead_fastClassesKeepHistoricalDepth() {
        // Never measured on flash; serialising there could only cost overlap.
        for dest in [Constants.SlowestDestClass.ssdLocal, .nvmeLocal, .network] {
            XCTAssertEqual(Constants.verifyRunAheadFiles(forSlowestDest: dest, env: [:]), 64,
                           "\(dest) should keep the unbounded depth")
        }
    }

    func test_verifyRunAhead_envOverridesEveryClass() {
        let all: [Constants.SlowestDestClass] = [.hdd, .exfat, .unknown, .ssdLocal, .nvmeLocal, .network]
        for dest in all {
            XCTAssertEqual(
                Constants.verifyRunAheadFiles(
                    forSlowestDest: dest, env: ["FILMCAN_VERIFY_RUNAHEAD": "8"]), 8)
        }
    }

    func test_verifyRunAhead_garbageEnvFallsBackToTheClassDefault() {
        for bad in ["0", "-3", "", "abc", "2.5"] {
            XCTAssertEqual(
                Constants.verifyRunAheadFiles(
                    forSlowestDest: .hdd, env: ["FILMCAN_VERIFY_RUNAHEAD": bad]), 1,
                "env value \(bad) must not stall the pipeline")
            XCTAssertEqual(
                Constants.verifyRunAheadFiles(
                    forSlowestDest: .ssdLocal, env: ["FILMCAN_VERIFY_RUNAHEAD": bad]), 64)
        }
    }

}
