import XCTest
@testable import FilmCan

final class CopyEnginePersistenceTests: XCTestCase {
    // Old history entries may carry copyEngine = "rsync" — must decode as-is (string preserved).
    func testLegacyRsyncCopyEngineDecodesInSnapshot() throws {
        let json = """
        {"copyFolderContents":false,"runInParallel":false,"logEnabled":true,
         "copyEngine":"rsync","duplicatePolicy":"increment",
         "duplicateCounterTemplate":"_001","useChecksum":false,
         "checksumChoice":"xxh128","postVerify":false,"onlyCopyChanged":false,
         "reuseOrganizedFiles":false,"allowResume":false,"deleteExtraFiles":false,
         "updateInPlace":false,"customArgs":""}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(TransferOptionsSnapshot.self, from: json)
        XCTAssertEqual(snapshot.copyEngine, "rsync")
    }

    // New runs always record copyEngine = "custom".
    func testNewSnapshotRecordsCopyEngineAsCustom() throws {
        var config = BackupConfiguration()
        config.engineOptions = EngineOptions()
        let snapshot = TransferOptionsSnapshot(config: config, presetName: nil)
        XCTAssertEqual(snapshot.copyEngine, "custom")
    }

    // EngineOptions Codable round-trip.
    func testEngineOptionsRoundTrips() throws {
        var opts = EngineOptions()
        opts.postVerify = false
        opts.allowResume = false
        let data = try JSONEncoder().encode(opts)
        let decoded = try JSONDecoder().decode(EngineOptions.self, from: data)
        XCTAssertEqual(opts, decoded)
    }

    // BackupConfiguration with missing engineOptions key falls back to defaults.
    func testBackupConfigurationMissingEngineOptionsUsesDefaults() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Test","sources":[],"destinations":[]}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertEqual(config.engineOptions, EngineOptions())
    }

    func testEntitlementsIsValidPlist() throws {
        let here = URL(fileURLWithPath: #filePath)
        let entitlements = here
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/FilmCan.entitlements")
        let data = try Data(contentsOf: entitlements)
        let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        XCTAssertNotNil(obj as? [String: Any])
    }

    @MainActor
    func testSaveEncodesAllBeforeWriting() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filmcan-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ConfigurationStorage(baseDirectory: dir)
        var cfg = BackupConfiguration()
        cfg.name = "Cfg A"
        store.add(cfg)
        XCTAssertTrue(store.save())

        let reloaded = ConfigurationStorage(baseDirectory: dir)
        reloaded.load()
        XCTAssertEqual(reloaded.configurations.map(\.name), ["Cfg A"])
    }
}
