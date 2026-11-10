import XCTest
@testable import FilmCan

final class FilmDriveDetectorTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("film-drives-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    @discardableResult
    private func volume(_ name: String, folders: [String] = []) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        for folder in folders {
            try fm.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        return url
    }

    private func detect(_ film: BackupConfiguration, _ volumes: [URL],
                        cards: [String: CardRole] = [:]) -> FilmDriveDetector.Detected {
        FilmDriveDetector.detect(film: film, volumes: volumes, cardRole: { cards[$0] })
    }

    func test_ownPaths_onlyMountedAndIncluded() throws {
        let a = try volume("A001")
        let b = try volume("A002")
        let ssd = try volume("SSD1")
        var film = BackupConfiguration()
        film.sourcePaths = [a.path, b.path, "/Volumes/GONE_CARD"]
        film.excludedSourcePaths = [b.path]
        film.destinationPaths = [ssd.path, "/Volumes/GONE_SSD"]
        film.sourceMediaKinds = [a.path: .sound]
        let d = detect(film, [])
        XCTAssertEqual(d.sources, [.init(path: a.path, kind: .sound)])
        XCTAssertEqual(d.destinations, [ssd.path])
    }

    func test_autoDetectRules_addMatchingDrives() throws {
        let a = try volume("A003")
        let zoom = try volume("SOUND_01", folders: ["ZOOM"])
        let ssd = try volume("RAID_A")
        let other = try volume("Backup Disk")
        var film = BackupConfiguration()
        film.sourceAutoDetectEnabled = true
        film.sourceAutoDetectPatterns = ["A0*"]
        film.soundAutoDetectEnabled = true
        film.soundAutoDetectPatterns = ["SOUND*/ZOOM"]
        film.destinationAutoDetectEnabled = true
        film.destinationAutoDetectPatterns = ["RAID*"]
        let d = detect(film, [a, zoom, ssd, other])
        XCTAssertEqual(d.sources, [.init(path: a.path, kind: nil),
                                   .init(path: zoom.appendingPathComponent("ZOOM").path, kind: .sound)])
        XCTAssertEqual(d.destinations, [ssd.path])
    }

    func test_cards_skipNotACard_andDestinations() throws {
        let card = try volume("UNTITLED")
        let rec = try volume("REC")
        let junk = try volume("THUMB")
        let ssd = try volume("SSD")
        var film = BackupConfiguration()
        film.cardAutoDetectEnabled = true
        film.destinationPaths = [ssd.path]
        let d = detect(film, [card, rec, junk, ssd],
                       cards: [card.path: .camera, rec.path: .sound, junk.path: .notACard, ssd.path: .camera])
        XCTAssertEqual(d.sources, [.init(path: card.path, kind: .camera), .init(path: rec.path, kind: .sound)])
        XCTAssertEqual(d.destinations, [ssd.path])
    }

    func test_ruleMatching() {
        XCTAssertTrue(FilmDriveDetector.matches("a001", pattern: "A0*"))
        XCTAssertFalse(FilmDriveDetector.matches("B001", pattern: "A0*"))
        XCTAssertTrue(FilmDriveDetector.matches("SSD", pattern: " ssd "))
        let (drive, folder) = FilmDriveDetector.splitRule("SOUND* / ZOOM")
        XCTAssertEqual(drive, "SOUND*")
        XCTAssertEqual(folder, "ZOOM")
    }
}
