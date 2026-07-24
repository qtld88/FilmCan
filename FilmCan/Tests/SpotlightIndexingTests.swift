import XCTest
@testable import FilmCan

final class SpotlightIndexingTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_writeMarker_createsEmptyNeverIndexFile() {
        let ok = SpotlightIndexing.writeMarker(atVolumeRoot: root.path)
        XCTAssertTrue(ok)
        let marker = root.appendingPathComponent(SpotlightIndexing.markerName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        let data = try? Data(contentsOf: marker)
        XCTAssertEqual(data?.count, 0)
    }

    func test_writeMarker_isIdempotent() {
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
    }

    func test_writeMarker_doesNotClobberExistingMarker() throws {
        let marker = root.appendingPathComponent(SpotlightIndexing.markerName)
        try Data("keep".utf8).write(to: marker)
        XCTAssertTrue(SpotlightIndexing.writeMarker(atVolumeRoot: root.path))
        XCTAssertEqual(try Data(contentsOf: marker), Data("keep".utf8))
    }

    func test_shouldDisable_defaultsTrueWhenUnset() {
        let d = UserDefaults(suiteName: "spotlight-test-\(UUID().uuidString)")!
        XCTAssertTrue(SpotlightIndexing.shouldDisable(defaults: d))
    }

    func test_shouldDisable_respectsStoredFalse() {
        let d = UserDefaults(suiteName: "spotlight-test-\(UUID().uuidString)")!
        d.set(false, forKey: SpotlightIndexing.defaultsKey)
        XCTAssertFalse(SpotlightIndexing.shouldDisable(defaults: d))
    }
}
