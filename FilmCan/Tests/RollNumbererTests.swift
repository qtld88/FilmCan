import XCTest
@testable import FilmCan

@MainActor
final class RollNumbererTests: XCTestCase {
    private func run(_ sources: [String], kinds: [String: SourceMediaKind] = [:],
                     settings: RollNumbering = RollNumbering(), existing: [String: String] = [:],
                     signatures: [String: CardSignature] = [:],
                     isDir: @escaping (String) -> Bool = { _ in true })
        -> (names: [String: String], assignments: [String: String])
    {
        RollNumberer.assign(sources: sources, isDirectory: isDir, kinds: kinds, settings: settings,
                            existing: existing, keyFor: { "k:" + $0 }, signatureFor: { signatures[$0] })
    }

    func test_threeCameraOneSound() {
        let r = run(["/v/1", "/v/2", "/v/3", "/v/snd"], kinds: ["/v/snd": .sound])
        XCTAssertEqual(r.names["/v/1"], "A001")
        XCTAssertEqual(r.names["/v/2"], "A002")
        XCTAssertEqual(r.names["/v/3"], "A003")
        XCTAssertEqual(r.names["/v/snd"], "S001")
    }

    func test_rerunSameKeys_isStable() {
        let first = run(["/v/1", "/v/2"])
        let second = run(["/v/1", "/v/2"], existing: first.assignments)
        XCTAssertEqual(first.names, second.names)
        XCTAssertEqual(first.assignments, second.assignments)
    }

    func test_newCardAfterThree_isA004() {
        let first = run(["/v/1", "/v/2", "/v/3"])
        let second = run(["/v/1", "/v/2", "/v/3", "/v/4"], existing: first.assignments)
        XCTAssertEqual(second.names["/v/4"], "A004")
    }

    func test_cameraStart() {
        var s = RollNumbering(); s.cameraStart = 45
        XCTAssertEqual(run(["/v/1"], settings: s).names["/v/1"], "A045")
    }

    func test_redReelKept_orNumberedWhenDisabled() {
        let sig = ["/v/red": CardSignature(brand: .red, reelName: "A003_R1AB")]
        XCTAssertEqual(run(["/v/red"], signatures: sig).names["/v/red"], "A003_R1AB")
        var s = RollNumbering(); s.keepCameraReelNames = false
        XCTAssertEqual(run(["/v/red"], settings: s, signatures: sig).names["/v/red"], "A001")
    }

    func test_flatFile_noName() {
        let r = run(["/v/file.mov"], isDir: { _ in false })
        XCTAssertTrue(r.names.isEmpty)
        XCTAssertTrue(r.assignments.isEmpty)
    }

    func test_cardKey() {
        XCTAssertEqual(RollNumberer.cardKey(volumeUUID: "U", sourcePath: "/Volumes/X", volumeRoot: "/Volumes/X"), "U|")
        XCTAssertEqual(RollNumberer.cardKey(volumeUUID: nil, sourcePath: "/Volumes/X/a/b", volumeRoot: "/Volumes/X"), "nouuid|a/b")
    }

    func test_shootDayCounter() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let d1 = Date(timeIntervalSince1970: 1_700_000_000)
        let d2 = d1.addingTimeInterval(86_400)
        XCTAssertEqual(ShootDayCounter.advance(day: "Day01", lastRun: d1, now: d2, calendar: cal), "Day02")
        XCTAssertEqual(ShootDayCounter.advance(day: "D9", lastRun: d1, now: d2, calendar: cal), "D10")
        XCTAssertEqual(ShootDayCounter.advance(day: "Day099", lastRun: d1, now: d2, calendar: cal), "Day100")
        XCTAssertEqual(ShootDayCounter.advance(day: "", lastRun: d1, now: d2, calendar: cal), "Day01")
        XCTAssertEqual(ShootDayCounter.advance(day: "Prep", lastRun: d1, now: d2, calendar: cal), "Prep")
        XCTAssertEqual(ShootDayCounter.advance(day: "Day01", lastRun: nil, now: d2, calendar: cal), "Day01")
        XCTAssertEqual(ShootDayCounter.advance(day: "Day01", lastRun: d1, now: d1.addingTimeInterval(60), calendar: cal), "Day01")
    }

    func test_storeRoundTrip_andReset() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rn-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let id = UUID()
        let store = RollNumberingStore(fileURL: url)
        let s = RollNumberingStore.ConfigState(assignments: ["k": "A001"], currentDay: "Day03",
                                               lastRunDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.update(s, for: id)
        let reloaded = RollNumberingStore(fileURL: url)
        XCTAssertEqual(reloaded.state(for: id), s)
        reloaded.resetNumbering(for: id)
        XCTAssertEqual(reloaded.state(for: id).assignments, [:])
        XCTAssertEqual(reloaded.state(for: id).currentDay, "Day03")
    }
}
