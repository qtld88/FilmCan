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
        await OrphanCleaner.shared.cleanOrphans(at: [dir])

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(active).path),
            "registered active temp must be preserved")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(stale).path),
            "unregistered stale temp must be removed")

        await OrphanCleaner.shared.unregisterActive(active)
    }
}
