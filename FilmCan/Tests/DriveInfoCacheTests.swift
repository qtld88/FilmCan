import XCTest
@testable import FilmCan

@MainActor
final class DriveInfoCacheTests: XCTestCase {

    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "drivecache-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    // A miss leaves the cache empty (no synchronous populate) ...
    func test_miss_cacheEmpty() {
        let cache = DriveInfoCache()
        XCTAssertNil(cache.cachedSnapshot(for: tempDir()))
    }

    // ... but info(for:) still returns a usable, disk-free placeholder.
    func test_miss_returnsPlaceholder() {
        let cache = DriveInfoCache()
        let info = cache.info(for: tempDir())
        XCTAssertTrue(info.isPlaceholder)
        XCTAssertNil(info.totalBytes)
        XCTAssertFalse(info.summary.name.isEmpty)
    }

    // Placeholder derives a sensible name from a /Volumes path without disk.
    func test_placeholder_nameFromVolumePath() {
        let snap = DriveInfoSnapshot.placeholder(for: "/Volumes/CARD_A001/DCIM")
        XCTAssertEqual(snap.summary.name, "CARD_A001")
        XCTAssertTrue(snap.summary.isExternal)
        XCTAssertTrue(snap.isPlaceholder)
    }

    func test_prime_thenHit() async {
        let cache = DriveInfoCache()
        let path = tempDir()
        await cache.populateNow(path: path)
        let snap = cache.cachedSnapshot(for: path)
        XCTAssertNotNil(snap)
        XCTAssertFalse(snap?.isPlaceholder ?? true)
        XCTAssertFalse(snap?.summary.name.isEmpty ?? true)
    }

    func test_invalidate() async {
        let cache = DriveInfoCache()
        let path = tempDir()
        await cache.populateNow(path: path)
        XCTAssertNotNil(cache.cachedSnapshot(for: path))
        cache.invalidate(path: path)
        XCTAssertNil(cache.cachedSnapshot(for: path))
    }

    func test_populateFailure_placeholderName() async {
        let cache = DriveInfoCache()
        let bogus = "/nonexistent-volume-\(UUID().uuidString)"
        await cache.populateNow(path: bogus)
        let snap = cache.cachedSnapshot(for: bogus)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.summary.name, "Drive")
        XCTAssertFalse(snap?.pathExists ?? true)
    }

    // Root-cause regression: the cache must key by PATH, not volume id. Two
    // distinct paths on the SAME volume (two temp dirs) must be independent
    // entries: invalidating one must not evict the other. (Keying by volume id
    // forced a synchronous summary() disk stat on every lookup.)
    func test_keyedByPath_notVolumeId() async {
        let cache = DriveInfoCache()
        let a = tempDir()
        let b = tempDir()   // same volume as `a`, different path
        await cache.populateNow(path: a)
        await cache.populateNow(path: b)
        XCTAssertNotNil(cache.cachedSnapshot(for: a))
        XCTAssertNotNil(cache.cachedSnapshot(for: b))
        cache.invalidate(path: a)
        XCTAssertNil(cache.cachedSnapshot(for: a))
        XCTAssertNotNil(cache.cachedSnapshot(for: b))
    }
}
