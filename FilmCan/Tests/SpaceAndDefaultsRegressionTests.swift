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

    // Bug 2: liveAvailableBytes must never under-report below the strict statfs
    // free-block count (the metric that excludes APFS purgeable space). On the
    // internal APFS volume it should report at least as much as ImportantUsage.
    func test_liveAvailableBytes_neverUnderReportsStatfs() throws {
        let path = NSTemporaryDirectory()

        let strictStatfs: Int64? = (try? FileManager.default.attributesOfFileSystem(forPath: path))?[.systemFreeSize] as? Int64
        let importantUsage: Int64? = (try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage

        let reported = try XCTUnwrap(DriveUtilities.liveAvailableBytes(for: path),
                                     "expected a live free-space figure for the temp volume")
        XCTAssertGreaterThan(reported, 0)

        // Must track the LARGER of the two metrics (we take the max). The old bug
        // returned the small statfs value when ImportantUsage was GBs larger.
        // 8 MB slack absorbs block-level drift between independent samples; the
        // regression it guards against was multiple GB off.
        let maxExternal = max(strictStatfs ?? 0, importantUsage ?? 0)
        let slack: Int64 = 8 * 1024 * 1024
        XCTAssertGreaterThanOrEqual(reported + slack, maxExternal)
    }
}
