import XCTest
@testable import FilmCan

final class SpeedAdviceTests: XCTestCase {
    private let gb: Int64 = 1_000_000_000

    private func info(ssd: Bool = false, bus: DriveBus = .usb3plus, network: Bool = false,
                      uuid: String? = UUID().uuidString) -> DriveInfo {
        DriveInfo(isSSD: ssd, bus: bus, filesystem: .apfs, isInternal: false, isExFAT: false,
                  isNetwork: network, volumeUUID: uuid)
    }

    private func ssd(_ name: String, bus: DriveBus = .usb3plus, hub: UInt64? = nil,
                     capacity: Int64? = nil, available: Int64? = nil) -> SpeedDrive {
        SpeedDrive(path: "/Volumes/\(name)", name: name, role: .destination,
                   info: info(ssd: true, bus: bus, uuid: name), hubID: hub,
                   capacityBytes: capacity, availableBytes: available, isRotational: false)
    }

    private func hdd(_ name: String, bus: DriveBus = .usb3plus, hub: UInt64? = nil) -> SpeedDrive {
        SpeedDrive(path: "/Volumes/\(name)", name: name, role: .destination,
                   info: info(ssd: false, bus: bus, uuid: name), hubID: hub, isRotational: true)
    }

    private func card(_ name: String, bus: DriveBus = .usb3plus, hub: UInt64? = nil) -> SpeedDrive {
        SpeedDrive(path: "/Volumes/\(name)", name: name, role: .source,
                   info: info(ssd: true, bus: bus, uuid: name), hubID: hub)
    }

    // MARK: - Same sequential rule as before

    func test_copyPlan_keepsTheRunsRule() {
        let a = info(uuid: "A"), b = info(uuid: "B")
        XCTAssertFalse(DestinationCopyPlan.isSequential(mode: .sequential, destinations: [a]))
        XCTAssertFalse(DestinationCopyPlan.isSequential(mode: .parallel, destinations: [a, info(network: true)]))
        XCTAssertTrue(DestinationCopyPlan.isSequential(mode: .sequential, destinations: [a, b]))
        XCTAssertFalse(DestinationCopyPlan.isSequential(mode: .automatic, destinations: [a, b]))
        XCTAssertTrue(DestinationCopyPlan.isSequential(mode: .automatic, destinations: [a, info(network: true)]))
        XCTAssertTrue(DestinationCopyPlan.isSequential(mode: .automatic, destinations: [a, info(uuid: "A")]))
        // Unknown volume ids are not "the same volume".
        XCTAssertFalse(DestinationCopyPlan.isSequential(mode: .automatic,
                                                        destinations: [info(uuid: nil), info(uuid: nil)]))
        // A hard drive next to an SSD is still copied at the same time in automatic.
        var spinning = info(ssd: false, uuid: "H")
        spinning.isSSD = false
        XCTAssertFalse(DestinationCopyPlan.isSequential(mode: .automatic, destinations: [info(ssd: true, uuid: "S"), spinning]))
    }

    // MARK: - Before the copy

    func test_hardDriveAndSSD_atOnce_adviseCopyingToTheSSDFirst() {
        let advices = SpeedAdvisor.advices(sources: [card("A001")],
                                           destinations: [hdd("LaCie"), ssd("T7")],
                                           bytesToCopy: 200 * gb, mode: .automatic)
        let advice = try? XCTUnwrap(advices.first { $0.kind == .slowAndFastAtOnce })
        XCTAssertNotNil(advice)
        XCTAssertEqual(advice?.action, .copyFirst(paths: ["/Volumes/T7"], name: "\u{2018}T7\u{2019}"))
        XCTAssertTrue(advice?.title.contains("LaCie") ?? false)
    }

    func test_actionMakesTheMovieCopyOneAtATime_fastDriveFirst() async {
        await MainActor.run {
            var config = BackupConfiguration()
            config.destinationPaths = ["/Volumes/LaCie", "/Volumes/T7", "/Volumes/Other"]
            let model = BackupEditorViewModel(config: config)
            model.applySpeedAdvice(.copyFirst(paths: ["/Volumes/T7"], name: "T7"))
            XCTAssertEqual(model.config.destinationCopyMode, .sequential)
            XCTAssertEqual(model.config.destinationPaths, ["/Volumes/T7", "/Volumes/LaCie", "/Volumes/Other"])
        }
    }

    func test_oneAtATime_fastDriveAlreadyFirst_saysNothing_slowFirst_advises() {
        let fastFirst = SpeedAdvisor.advices(sources: [], destinations: [ssd("T7"), hdd("LaCie")],
                                             bytesToCopy: 200 * gb, mode: .sequential)
        XCTAssertFalse(fastFirst.contains { $0.kind == .slowDriveFirst || $0.kind == .slowAndFastAtOnce })

        let slowFirst = SpeedAdvisor.advices(sources: [], destinations: [hdd("LaCie"), ssd("T7")],
                                             bytesToCopy: 200 * gb, mode: .sequential)
        XCTAssertEqual(slowFirst.first?.kind, .slowDriveFirst)
        XCTAssertEqual(slowFirst.first?.action, .copyFirst(paths: ["/Volumes/T7"], name: "\u{2018}T7\u{2019}"))
    }

    func test_driveNotReportedAsSSD_isNeverCalledSlow() {
        // macOS often reports external SSDs as not solid state; without a "Rotational"
        // report the drive's speed is unknown and no order advice is built on it.
        var unknown = ssd("Samsung")
        unknown.info.isSSD = false
        unknown.isRotational = nil
        let advices = SpeedAdvisor.advices(sources: [], destinations: [unknown, ssd("T7")],
                                           bytesToCopy: 200 * gb, mode: .automatic)
        XCTAssertTrue(advices.isEmpty)
    }

    func test_twoFoldersOnOneDrive_countOnce() {
        var other = ssd("T7")
        other.path = "/Volumes/T7/Backup2"
        let advices = SpeedAdvisor.advices(sources: [], destinations: [ssd("T7"), other],
                                           bytesToCopy: 200 * gb, mode: .automatic)
        XCTAssertTrue(advices.isEmpty)
    }

    func test_usb2_sharedHub_nearlyFull() {
        let advices = SpeedAdvisor.advices(
            sources: [card("A001", bus: .usb2)],
            destinations: [ssd("T7", hub: 42, capacity: 1000 * gb, available: 250 * gb),
                           ssd("X10", hub: 42)],
            bytesToCopy: 200 * gb, mode: .automatic)
        XCTAssertEqual(Set(advices.map(\.kind)), [.usb2, .sharedHub, .nearlyFullSSD])
        XCTAssertEqual(advices.first?.kind, .usb2, "most costly first")
    }

    func test_atMostThree_mostCostlyFirst() {
        let advices = SpeedAdvisor.advices(
            sources: [card("A001", bus: .usb2, hub: 7), card("B001", bus: .usb2, hub: 7)],
            destinations: [hdd("LaCie"), ssd("T7", capacity: 1000 * gb, available: 210 * gb)],
            bytesToCopy: 200 * gb, mode: .automatic)
        XCTAssertEqual(advices.count, 3)
        XCTAssertEqual(advices.map(\.costSeconds), advices.map(\.costSeconds).sorted(by: >))
    }

    func test_dismissed_doesNotComeBackForTheSameDrives_butDoesForOthers() {
        let suite = "filmcan.tests.speedAdvice"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let store = SpeedAdviceDismissals(defaults: UserDefaults(suiteName: suite)!)

        let first = SpeedAdvisor.advices(sources: [], destinations: [hdd("LaCie"), ssd("T7")],
                                         bytesToCopy: 200 * gb, mode: .automatic)
        store.dismiss(first[0])
        let again = SpeedAdvisor.advices(sources: [], destinations: [hdd("LaCie"), ssd("T7")],
                                         bytesToCopy: 200 * gb, mode: .automatic, dismissed: store.keys)
        XCTAssertTrue(again.isEmpty)
        let otherPair = SpeedAdvisor.advices(sources: [], destinations: [hdd("G-Drive"), ssd("T7")],
                                             bytesToCopy: 200 * gb, mode: .automatic, dismissed: store.keys)
        XCTAssertEqual(otherPair.count, 1)
    }

    func test_nothingToCopy_noAdvice() {
        XCTAssertTrue(SpeedAdvisor.advices(sources: [card("A001", bus: .usb2)], destinations: [ssd("T7")],
                                           bytesToCopy: 0, mode: .automatic).isEmpty)
    }

    // MARK: - After the copy

    private func dest(_ drive: SpeedDrive, gb count: Int64, seconds: TimeInterval = 0,
                      success: Bool = true) -> SpeedRunMeasure.Dest {
        .init(drive: drive, bytes: count * gb, seconds: seconds, success: success)
    }

    func test_note_oneAtATime_namesTheSlowestMeasuredDrive() {
        let run = SpeedRunMeasure(sources: [card("A001")],
                                  destinations: [dest(ssd("T7"), gb: 100, seconds: 256),
                                                 dest(hdd("LaCie"), gb: 100, seconds: 1176)],
                                  sequential: true, wallSeconds: 1432, rereads: false, cancelled: false)
        XCTAssertEqual(SpeedNote.sentence(for: run),
                       "\u{2018}LaCie\u{2019} was the slowest drive: 85 MB/s, against 391 MB/s for \u{2018}T7\u{2019}.")
    }

    func test_note_atOnce_namesTheSlowestLink_whenTheSpeedMatchesIt() {
        let run = SpeedRunMeasure(sources: [card("A001")],
                                  destinations: [dest(ssd("T7"), gb: 100), dest(hdd("LaCie"), gb: 100)],
                                  sequential: false, wallSeconds: 2000, rereads: true, cancelled: false)
        XCTAssertEqual(SpeedNote.sentence(for: run),
                       "This copy ran at 50 MB/s, read-back check included. The slowest link was \u{2018}LaCie\u{2019} (hard drive).")
    }

    func test_note_atOnce_farBelowEveryDrive_blamesTheSetup() {
        let run = SpeedRunMeasure(sources: [card("A001")],
                                  destinations: [dest(ssd("T7"), gb: 10), dest(ssd("X10"), gb: 10)],
                                  sequential: false, wallSeconds: 1000, rereads: false, cancelled: false)
        XCTAssertEqual(SpeedNote.sentence(for: run),
                       "This copy ran at 10 MB/s, slower than these drives allow. A shared hub, a long cable or a busy Mac may have held it back.")
    }

    func test_note_none_forSmallFailedCancelledOrUnknownRuns() {
        let small = SpeedRunMeasure(sources: [], destinations: [dest(ssd("T7"), gb: 0)],
                                    sequential: false, wallSeconds: 100, rereads: false, cancelled: false)
        XCTAssertNil(SpeedNote.sentence(for: small))
        let failed = SpeedRunMeasure(sources: [], destinations: [dest(ssd("T7"), gb: 50, success: false)],
                                     sequential: false, wallSeconds: 100, rereads: false, cancelled: false)
        XCTAssertNil(SpeedNote.sentence(for: failed))
        let cancelled = SpeedRunMeasure(sources: [], destinations: [dest(ssd("T7"), gb: 50)],
                                        sequential: false, wallSeconds: 100, rereads: false, cancelled: true)
        XCTAssertNil(SpeedNote.sentence(for: cancelled))
        var unknown = ssd("Samsung")
        unknown.info.isSSD = false
        unknown.isRotational = nil
        let slowUnknown = SpeedRunMeasure(sources: [], destinations: [dest(unknown, gb: 10)],
                                          sequential: false, wallSeconds: 1000, rereads: false, cancelled: false)
        XCTAssertNil(SpeedNote.sentence(for: slowUnknown), "never blames a setup whose drives are unknown")
        let knownCardUnknownDrive = SpeedRunMeasure(sources: [card("A001")], destinations: [dest(unknown, gb: 10)],
                                                    sequential: false, wallSeconds: 1000, rereads: false, cancelled: false)
        XCTAssertNil(SpeedNote.sentence(for: knownCardUnknownDrive),
                     "a slow run is not blamed on the setup while one drive's speed is unknown")
    }

    func test_reordered_keepsEachGroupsOrder() {
        XCTAssertEqual(SpeedAdvisor.reordered(["a", "b", "c", "d"], first: ["d", "b"]), ["b", "d", "a", "c"])
    }
}
