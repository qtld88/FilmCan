import XCTest
@testable import FilmCan

final class DayFolderResolverTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default
    let nov9 = DateComponents(calendar: .current, year: 2026, month: 11, day: 9, hour: 10).date!
    let nov10 = DateComponents(calendar: .current, year: 2026, month: 11, day: 10, hour: 1).date!

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("day-folder-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func card(_ name: String, _ folders: [String]) throws -> URL {
        let url = tmp.appendingPathComponent(name)
        for folder in folders {
            try fm.createDirectory(at: url.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        return url
    }

    func test_dayKey_formats() {
        XCTAssertEqual(DayFolderResolver.dayKey("26Y11M09"), 20261109)
        XCTAssertEqual(DayFolderResolver.dayKey("26y11m09"), 20261109)
        XCTAssertEqual(DayFolderResolver.dayKey("20261109"), 20261109)
        XCTAssertEqual(DayFolderResolver.dayKey("2026-11-09"), 20261109)
        XCTAssertEqual(DayFolderResolver.dayKey("2026_11_09"), 20261109)
        XCTAssertEqual(DayFolderResolver.dayKey("261109"), 20261109)
        XCTAssertNil(DayFolderResolver.dayKey("HAWAII"))
        XCTAssertNil(DayFolderResolver.dayKey("A001"))
        XCTAssertNil(DayFolderResolver.dayKey("26Y13M09"))
        XCTAssertNil(DayFolderResolver.dayKey("123456"))
    }

    func test_pick_todayElseLatestPastElseLatest() {
        let c: [(path: String, key: Int)] = [("a", 20261107), ("b", 20261108), ("c", 20261112)]
        XCTAssertEqual(DayFolderResolver.pick(c + [("d", 20261109)], today: 20261109), ["d"])
        XCTAssertEqual(DayFolderResolver.pick(c, today: 20261109), ["b"])
        XCTAssertEqual(DayFolderResolver.pick([("c", 20261112)], today: 20261109), ["c"])
        XCTAssertEqual(DayFolderResolver.pick([], today: 20261109), [])
    }

    func test_find_projectDateSubfolder() throws {
        let sd = try card("688 SD", ["LA_DERNIERE_FRONTR/26Y11M08/HAWAII", "LA_DERNIERE_FRONTR/26Y11M09/HAWAII"])
        XCTAssertEqual(DayFolderResolver.findDayFolders(in: sd.path, today: nov9),
                       [sd.appendingPathComponent("LA_DERNIERE_FRONTR/26Y11M09").path])
    }

    func test_find_projectSubfolderDate() throws {
        let sd = try card("688 SD", ["LA_DERNIERE_FRONTR/HAWAII/26Y11M08", "LA_DERNIERE_FRONTR/HAWAII/26Y11M09"])
        XCTAssertEqual(DayFolderResolver.findDayFolders(in: sd.path, today: nov9),
                       [sd.appendingPathComponent("LA_DERNIERE_FRONTR/HAWAII/26Y11M09").path])
    }

    func test_find_afterMidnight_takesPreviousDay() throws {
        let sd = try card("688 SD", ["PROJ/26Y11M08", "PROJ/26Y11M09"])
        XCTAssertEqual(DayFolderResolver.findDayFolders(in: sd.path, today: nov10),
                       [sd.appendingPathComponent("PROJ/26Y11M09").path])
    }

    func test_find_noDatedFolder_isEmpty() throws {
        let sd = try card("ZOOM", ["FOLDER01"])
        XCTAssertEqual(DayFolderResolver.findDayFolders(in: sd.path, today: nov9), [])
    }

    func test_ruleToken_resolvesDayFolder() throws {
        let sd = try card("688 SD", ["LA_DERNIERE_FRONTR/26Y11M08/HAWAII", "LA_DERNIERE_FRONTR/26Y11M09/HAWAII"])
        // The `*` matcher lists children through URL APIs, which expand /var to /private/var.
        func resolve(_ subpath: String) -> [String] {
            FilmDriveDetector.resolveSubpathMatches(rootURL: sd, subpath: subpath, today: nov9)
                .map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        }
        func expected(_ rel: String) -> [String] {
            [sd.appendingPathComponent(rel).resolvingSymlinksInPath().path]
        }
        XCTAssertEqual(resolve("*/{jour}/HAWAII"), expected("LA_DERNIERE_FRONTR/26Y11M09/HAWAII"))
        XCTAssertEqual(resolve("LA_DERNIERE_FRONTR/{jour}"), expected("LA_DERNIERE_FRONTR/26Y11M09"))
        XCTAssertEqual(resolve("*/{JOUR}"), expected("LA_DERNIERE_FRONTR/26Y11M09"))
    }

    func test_replacingStaleDays_dropsRootAndOlderDay() {
        let vol = "/Volumes/688 SD"
        let sources = ["/Volumes/A001", vol, "\(vol)/P/26Y11M08", "\(vol)/P/NOTES"]
        let fresh = ["\(vol)/P/26Y11M09"]
        XCTAssertEqual(DayFolderResolver.replacingStaleDays(in: sources, volumePath: vol, fresh: fresh),
                       ["/Volumes/A001", "\(vol)/P/NOTES", "\(vol)/P/26Y11M09"])
        XCTAssertEqual(DayFolderResolver.replacingStaleDays(in: sources, volumePath: vol, fresh: []), sources)
    }

    func test_detector_soundCard_addsDayFolderWhenEnabled() throws {
        let sd = try card("688 SD", ["LA_DERNIERE_FRONTR/26Y11M08", "LA_DERNIERE_FRONTR/26Y11M09"])
        var film = BackupConfiguration()
        film.cardAutoDetectEnabled = true

        var detected = FilmDriveDetector.detect(film: film, volumes: [sd], cardRole: { _ in .sound }, today: nov9)
        XCTAssertEqual(detected.sources.map(\.path), [sd.path])

        film.soundDayFolderAutoDetect = true
        detected = FilmDriveDetector.detect(film: film, volumes: [sd], cardRole: { _ in .sound }, today: nov9)
        XCTAssertEqual(detected.sources, [.init(path: sd.appendingPathComponent("LA_DERNIERE_FRONTR/26Y11M09").path, kind: .sound)])
    }

    func test_config_roundTripsDayFolderFlag() throws {
        var film = BackupConfiguration()
        film.soundDayFolderAutoDetect = true
        let decoded = try JSONDecoder().decode(BackupConfiguration.self, from: JSONEncoder().encode(film))
        XCTAssertTrue(decoded.soundDayFolderAutoDetect)
    }
}
