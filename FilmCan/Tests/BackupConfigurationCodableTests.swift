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

    // MARK: - New-film defaults

    func testNewFilmTurnsOnCardDetectionAndPDFReport() {
        let film = BackupConfiguration.newFilm(name: "Movie 1")
        XCTAssertEqual(film.name, "Movie 1")
        XCTAssertTrue(film.cardAutoDetectEnabled)
        XCTAssertTrue(film.reportEnabled)
        XCTAssertTrue(film.logEnabled, "the PDF report needs the log to be on")
    }

    func testNewFilmDiffersFromEmptyOnlyByTheTwoDefaults() {
        var film = BackupConfiguration.newFilm(name: "X")
        var plain = BackupConfiguration()
        plain.name = "X"
        film.id = plain.id
        film.createdAt = plain.createdAt
        film.organizationCustomDate = plain.organizationCustomDate
        film.offOrganizationCustomDate = plain.offOrganizationCustomDate
        film.cardAutoDetectEnabled = false
        film.reportEnabled = false
        XCTAssertEqual(film, plain)
    }

    /// A film saved before these defaults existed keeps both switches off.
    func testFilmSavedWithoutTheTwoKeysStaysOff() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old","sourcePaths":["/Volumes/A001"]}"#.data(using: .utf8)!
        let old = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertFalse(old.cardAutoDetectEnabled)
        XCTAssertFalse(old.reportEnabled)
    }

    /// A film whose owner switched them off stays off across save/load.
    func testNewFilmSwitchedOffStaysOffAfterRoundTrip() throws {
        var film = BackupConfiguration.newFilm(name: "X")
        film.cardAutoDetectEnabled = false
        film.reportEnabled = false
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: JSONEncoder().encode(film))
        XCTAssertFalse(back.cardAutoDetectEnabled)
        XCTAssertFalse(back.reportEnabled)
    }

    /// Plain init (Quick Copy's temporary config, history recall) is unchanged.
    func testPlainInitKeepsBothOff() {
        XCTAssertFalse(BackupConfiguration().cardAutoDetectEnabled)
        XCTAssertFalse(BackupConfiguration().reportEnabled)
        XCTAssertFalse(BackupConfiguration.empty.reportEnabled)
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

    func testGenericRollNamesRoundTrip() throws {
        var cfg = BackupConfiguration()
        cfg.genericRollNames = ["uuid-1|": "Untitled_01", "uuid-2|": "Untitled_02"]
        let back = try JSONDecoder().decode(BackupConfiguration.self, from: JSONEncoder().encode(cfg))
        XCTAssertEqual(back.genericRollNames, cfg.genericRollNames)
    }

    func testLegacyConfigWithoutGenericRollNamesDecodesEmpty() throws {
        let json = #"{"id":"\#(UUID().uuidString)","name":"Old"}"#.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(BackupConfiguration.self, from: json)
        XCTAssertEqual(cfg.genericRollNames, [:])
    }

    func testWithGenericRollNamesFillsOnlyMissingPaths() {
        var cfg = BackupConfiguration()
        cfg.sourcePaths = ["/Volumes/Untitled", "/Volumes/Untitled 1", "/Volumes/Other"]
        cfg.genericRollNames = ["k-a": "Untitled_01", "k-b": "Untitled_02", "k-x": ""]
        cfg.runRollNames = ["/Volumes/Untitled 1": "Kept"]
        let keys = ["/Volumes/Untitled": "k-a", "/Volumes/Untitled 1": "k-b", "/Volumes/Other": "k-x"]
        let run = cfg.withGenericRollNames(keyFor: { keys[$0] ?? "" })
        XCTAssertEqual(run.runRollNames, ["/Volumes/Untitled": "Untitled_01", "/Volumes/Untitled 1": "Kept"])
    }

    func testWithGenericRollNamesDoesNothingWhenRollNumberingIsOn() {
        var cfg = BackupConfiguration()
        cfg.sourcePaths = ["/Volumes/Untitled"]
        cfg.genericRollNames = ["k-a": "Untitled_01"]
        cfg.rollNumbering.enabled = true
        XCTAssertEqual(cfg.withGenericRollNames(keyFor: { _ in "k-a" }).runRollNames, [:])
    }
}
