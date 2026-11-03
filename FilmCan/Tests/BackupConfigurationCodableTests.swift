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
}
