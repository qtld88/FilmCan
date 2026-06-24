import XCTest
@testable import FilmCan

@MainActor
final class DriveInfoCacheTests: XCTestCase {

    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "drivecache-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    func test_miss_returnsNil() {
        let cache = DriveInfoCache()
        XCTAssertNil(cache.info(for: tempDir()))
    }

    func test_prime_thenHit() async {
        let cache = DriveInfoCache()
        let path = tempDir()
        await cache.populateNow(path: path)
        let info = cache.info(for: path)
        XCTAssertNotNil(info)
        XCTAssertFalse(info?.summary.name.isEmpty ?? true)
    }

    func test_capacityStale() {
        let cache = DriveInfoCache()
        let fresh = Date()
        XCTAssertFalse(cache.isCapacityStale(fetchedAt: fresh, ttl: 5))
        XCTAssertTrue(cache.isCapacityStale(fetchedAt: fresh.addingTimeInterval(-10), ttl: 5))
    }

    func test_invalidate() async {
        let cache = DriveInfoCache()
        let path = tempDir()
        await cache.populateNow(path: path)
        XCTAssertNotNil(cache.info(for: path))
        cache.invalidate(path: path)
        XCTAssertNil(cache.info(for: path))
    }

    func test_populateFailure_placeholder() async {
        let cache = DriveInfoCache()
        let bogus = "/nonexistent-volume-\(UUID().uuidString)"
        await cache.populateNow(path: bogus)
        let info = cache.info(for: bogus)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.summary.name, "Drive")
    }

    // Root-cause regression: the cache must key by PATH, not by volume id.
    // Keying by volume id forced `info(for:)`/`prime`/`invalidate` to call
    // DriveUtilities.driveId -> summary(for:) — a synchronous disk stat on the
    // main thread on every lookup, which defeated the cache and re-introduced the
    // nav hangs. Two distinct paths on the SAME volume (two temp dirs) must be
    // independent cache entries: invalidating one must not evict the other.
    func test_keyedByPath_notVolumeId() async {
        let cache = DriveInfoCache()
        let a = tempDir()
        let b = tempDir()   // same volume as `a`, different path
        await cache.populateNow(path: a)
        await cache.populateNow(path: b)
        XCTAssertNotNil(cache.info(for: a))
        XCTAssertNotNil(cache.info(for: b))
        cache.invalidate(path: a)
        XCTAssertNil(cache.info(for: a))
        XCTAssertNotNil(cache.info(for: b))
    }
}
