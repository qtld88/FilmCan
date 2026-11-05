import XCTest
@testable import FilmCan

final class BackupConfigurationCodableTests: XCTestCase {
    // New metadata fields must be optional/defaulted so OLD saved configs still decode.
    func testLegacyConfigWithoutMetadataDecodes() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertEqual(cfg.episode, "")
        XCTAssertEqual(cfg.day, "")
        XCTAssertEqual(cfg.unit, "")
        XCTAssertEqual(cfg.cameraFormat, "")
    }

    func testMetadataRoundTrips() throws {
        var cfg = BackupConfiguration()
        cfg.name = "Shoot"
        cfg.episode = "EP103"; cfg.day = "Day05"; cfg.unit = "MU"; cfg.cameraFormat = "ARRI"
        let data = try JSONEncoder().encode(cfg)
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: data)
        XCTAssertEqual(back.episode, "EP103")
        XCTAssertEqual(back.day, "Day05")
        XCTAssertEqual(back.unit, "MU")
        XCTAssertEqual(back.cameraFormat, "ARRI")
    }

    func testPayloadWithoutSchemaVersionDecodesTo1() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertEqual(cfg.schemaVersion, 1, "payload without schemaVersion must default to 1")
    }

    func testReportEnabledDefaultsFalseAndRoundTrips() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertFalse(legacy.reportEnabled)
        var cfg = BackupConfiguration()
        cfg.reportEnabled = true
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: JSONEncoder().encode(cfg))
        XCTAssertTrue(back.reportEnabled)
    }

    func testLegacyConfigWithoutRollFieldsDecodesToDefaults() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertEqual(cfg.rollNumbering, RollNumbering())
        XCTAssertFalse(cfg.rollNumbering.enabled)
        XCTAssertFalse(cfg.dayAutoAdvance)
        XCTAssertFalse(cfg.cardAutoDetectEnabled)
        XCTAssertTrue(cfg.runRollNames.isEmpty)
    }

    func testRollFieldsRoundTrip_andRunRollNamesIsNotEncoded() throws {
        var cfg = BackupConfiguration()
        cfg.rollNumbering.enabled = true
        cfg.rollNumbering.cameraStart = 45
        cfg.dayAutoAdvance = true
        cfg.cardAutoDetectEnabled = true
        cfg.runRollNames = ["/Volumes/X": "A001"]
        let data = try JSONEncoder().encode(cfg)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("runRollNames"))
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: data)
        XCTAssertTrue(back.rollNumbering.enabled)
        XCTAssertEqual(back.rollNumbering.cameraStart, 45)
        XCTAssertTrue(back.dayAutoAdvance)
        XCTAssertTrue(back.cardAutoDetectEnabled)
        XCTAssertTrue(back.runRollNames.isEmpty)
    }

    func testLegacyRunContextWithoutRollNamesDecodes() throws {
        let json = #"{"copyFolderContents":false,"sourceMediaKinds":{},"duplicatePolicy":"ask","hashListStyle":"ascMHL"}"#.data(using: .utf8)!
        let ctx = try JSONDecoder().decode(RunContext.self, from: json)
        XCTAssertTrue(ctx.rollNames.isEmpty)
        let back = try JSONDecoder().decode(RunContext.self, from: try JSONEncoder().encode(
            RunContext(organizationPresetId: nil, cameraFolderTemplate: nil, soundFolderTemplate: nil,
                       copyFolderContents: false, sourceMediaKinds: [:], duplicatePolicy: .ask,
                       hashListStyle: .ascMHL, rollNames: ["/a": "A001"])))
        XCTAssertEqual(back.rollNames, ["/a": "A001"])
    }
}

extension BackupConfigurationCodableTests {
    func testExcludedPathsDefaultEmptyRoundTripAndAreDroppedForTheRun() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertTrue(legacy.excludedSourcePaths.isEmpty)
        XCTAssertTrue(legacy.excludedDestinationPaths.isEmpty)

        var cfg = BackupConfiguration()
        cfg.sourcePaths = ["/Volumes/A", "/Volumes/B", "/Volumes/C"]
        cfg.destinationPaths = ["/Volumes/S1", "/Volumes/S2"]
        cfg.excludedSourcePaths = ["/Volumes/B"]
        cfg.excludedDestinationPaths = ["/Volumes/S2"]
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.excludedSourcePaths, ["/Volumes/B"])
        XCTAssertEqual(back.excludedDestinationPaths, ["/Volumes/S2"])

        let run = back.restrictedToIncluded()
        XCTAssertEqual(run.sourcePaths, ["/Volumes/A", "/Volumes/C"])
        XCTAssertEqual(run.destinationPaths, ["/Volumes/S1"])
        XCTAssertEqual(back.sourcePaths.count, 3, "the stored list keeps unchecked drives")
    }
}
