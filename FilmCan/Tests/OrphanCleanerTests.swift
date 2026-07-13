import XCTest
@testable import FilmCan

final class OrphanCleanerTests: XCTestCase {
    func testCleanOrphansSkipsRegisteredActiveTemps() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-orphan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let active = ".filmcan-ACTIVE-clip.mov"
        let stale = ".filmcan-STALE-clip.mov"
        try Data().write(to: dir.appendingPathComponent(active))
        try Data().write(to: dir.appendingPathComponent(stale))

        await OrphanCleaner.shared.registerActive(active)
        await OrphanCleaner.shared.cleanOrphans(rollFolders: [dir], destRoots: [])

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(active).path),
            "registered active temp must be preserved")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(stale).path),
            "unregistered stale temp must be removed")

        await OrphanCleaner.shared.unregisterActive(active)
    }

    /// Cleanup is scoped to the job's roll folders (recursive) plus a shallow pass
    /// over each dest root — it must NOT walk the whole destination volume. A stale
    /// temp buried in unrelated dest content (a prior backup) is left untouched, so a
    /// full SSD doesn't pay a full-tree walk during "Preparing".
    func testCleanOrphansScopesToRollFoldersAndDestRootShallow() async throws {
        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-scope-\(UUID().uuidString)")
        let roll = dest.appendingPathComponent("DJI")
        let rollNested = roll.appendingPathComponent("DCIM/100MEDIA")
        let unrelated = dest.appendingPathComponent("OLD_BACKUP/clip_archive")
        for d in [rollNested, unrelated] {
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: dest) }

        let rootTemp = dest.appendingPathComponent(".filmcan-writeprobe")
        let rollTemp = rollNested.appendingPathComponent(".filmcan-STALE-A001.mov")
        let unrelatedTemp = unrelated.appendingPathComponent(".filmcan-STALE-OLD.mov")
        for t in [rootTemp, rollTemp, unrelatedTemp] { try Data().write(to: t) }

        await OrphanCleaner.shared.cleanOrphans(rollFolders: [roll], destRoots: [dest])

        XCTAssertFalse(FileManager.default.fileExists(atPath: rootTemp.path),
            "dest-root temp removed by shallow pass")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rollTemp.path),
            "nested roll-folder temp removed by recursive pass")
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedTemp.path),
            "temp in unrelated dest content must be left untouched (no full-volume walk)")
    }
}
