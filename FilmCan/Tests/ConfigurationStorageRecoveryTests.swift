import XCTest
@testable import FilmCan

@MainActor
final class ConfigurationStorageRecoveryTests: XCTestCase {

    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func test_corruptConfig_isQuarantinedNotErased() throws {
        try "{ this is not json".write(to: dir.appendingPathComponent("configs.json"),
                                       atomically: true, encoding: .utf8)
        let storage = ConfigurationStorage(baseDirectory: dir)

        XCTAssertNotNil(storage.lastLoadError, "the failure must be visible, not silent")
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("configs.json.corrupt-") },
                      "the unreadable file must be preserved: \(names)")
    }

    func test_saveIsBlockedAfterACorruptLoad() throws {
        try "{ nope".write(to: dir.appendingPathComponent("configs.json"),
                           atomically: true, encoding: .utf8)
        let storage = ConfigurationStorage(baseDirectory: dir)
        storage.add(BackupConfiguration())

        // The quarantined copy still exists and holds the original bytes.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let quarantined = try XCTUnwrap(names.first { $0.hasPrefix("configs.json.corrupt-") })
        let bytes = try String(contentsOf: dir.appendingPathComponent(quarantined), encoding: .utf8)
        XCTAssertEqual(bytes, "{ nope")
    }

    func test_firstLaunch_isNotTreatedAsCorruption() {
        let storage = ConfigurationStorage(baseDirectory: dir)
        XCTAssertNil(storage.lastLoadError, "an absent file is a normal first launch")
        XCTAssertTrue(storage.configurations.isEmpty)
    }

    func test_healthyRoundTrip_isUnaffected() {
        let storage = ConfigurationStorage(baseDirectory: dir)
        var c = BackupConfiguration(); c.name = "Movie A"
        storage.add(c)
        let reloaded = ConfigurationStorage(baseDirectory: dir)
        XCTAssertEqual(reloaded.configurations.map(\.name), ["Movie A"])
        XCTAssertNil(reloaded.lastLoadError)
    }
}
