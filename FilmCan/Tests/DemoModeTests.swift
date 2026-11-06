#if DEBUG
import XCTest
@testable import FilmCan

final class DemoModeTests: XCTestCase {
    private let total: Int64 = 14_750_000_000
    private let speed = 500_000_000.0

    func test_copying60_bytesAndEtaAreConsistent() {
        let s = DemoRunSnapshot.make(state: .copying, totalBytes: total, progress: 0.6, speedBytesPerSecond: speed)
        XCTAssertEqual(s.copiedBytes, 8_850_000_000)
        XCTAssertEqual(s.eta ?? 0, 11.8, accuracy: 0.01)
        XCTAssertEqual(s.filesCompleted, 9)
        XCTAssertEqual(s.currentFile, "A003C010_R1KD.mov")
        XCTAssertLessThan(s.verifiedBytes, s.copiedBytes)
    }

    func test_verifying_copyIsFullAndDestIsVerifyOnly() {
        let s = DemoRunSnapshot.make(state: .verifying, totalBytes: total, progress: 0.5, speedBytesPerSecond: speed)
        XCTAssertEqual(s.copiedBytes, total)
        XCTAssertEqual(s.verifiedBytes, 7_375_000_000)
        XCTAssertEqual(s.eta ?? 0, 14.75, accuracy: 0.01)
        let dest = s.destProgress(id: "/d", displayName: "d", verifyMode: .paranoid)
        XCTAssertTrue(dest.isVerifyOnly)
        XCTAssertTrue(dest.isActive)
    }

    func test_done_isCompleteWithoutEta() {
        let s = DemoRunSnapshot.make(state: .done, totalBytes: total, progress: 0.2, speedBytesPerSecond: speed)
        XCTAssertEqual(s.copiedBytes, total)
        XCTAssertEqual(s.verifiedBytes, total)
        XCTAssertNil(s.eta)
        let dest = s.destProgress(id: "/d", displayName: "d", verifyMode: .paranoid)
        XCTAssertTrue(dest.isComplete)
        XCTAssertFalse(dest.isVerifyOnly)
    }

    func test_verifyOff_hasNoVerifyBytes() {
        let s = DemoRunSnapshot.make(state: .copying, totalBytes: total, progress: 0.4, speedBytesPerSecond: speed)
        let dest = s.destProgress(id: "/d", displayName: "d", verifyMode: .off)
        XCTAssertEqual(dest.verifyBytesTotal, 0)
        XCTAssertEqual(dest.verifyBytesCompleted, 0)
    }

    func test_progressIsClampedAndZeroSpeedHasNoEta() {
        let over = DemoRunSnapshot.make(state: .copying, totalBytes: total, progress: 3, speedBytesPerSecond: speed)
        XCTAssertEqual(over.copiedBytes, total)
        XCTAssertEqual(over.currentFile, "A003C015_R1KD.mov")
        let still = DemoRunSnapshot.make(state: .copying, totalBytes: total, progress: 0.5, speedBytesPerSecond: 0)
        XCTAssertNil(still.eta)
    }

    func test_parse_absentVariablesMeansInactive() {
        XCTAssertNil(DemoSettings.parse([:]))
        XCTAssertNil(DemoSettings.parse(["FILMCAN_DEMO_STATE": "bogus"]))
    }

    func test_parse_readsAllVariables() throws {
        let s = try XCTUnwrap(DemoSettings.parse([
            "FILMCAN_DEMO_STATE": "Verifying",
            "FILMCAN_DEMO_PROGRESS": "0.77",
            "FILMCAN_DEMO_SPEED_MBPS": "420",
            "FILMCAN_DEMO_TOTAL_GB": "20",
            "FILMCAN_DEMO_QUICKCOPY": "/Volumes/A, /Volumes/B",
            "FILMCAN_DEMO_QUICKCOPY_DEST": "/Volumes/C",
        ]))
        XCTAssertEqual(s.state, .verifying)
        XCTAssertEqual(s.progress, 0.77, accuracy: 0.0001)
        XCTAssertEqual(s.speedBytesPerSecond, 420_000_000)
        XCTAssertEqual(s.totalBytes, 20_000_000_000)
        XCTAssertEqual(s.quickCopySources, ["/Volumes/A", "/Volumes/B"])
        XCTAssertEqual(s.quickCopyDestinations, ["/Volumes/C"])
    }

    func test_parse_quickCopyWithoutStateDefaultsToSetup() throws {
        let s = try XCTUnwrap(DemoSettings.parse(["FILMCAN_DEMO_QUICKCOPY": "/Volumes/A"]))
        XCTAssertEqual(s.state, .setup)
    }

    @MainActor
    func test_applyDemoRun_done_setsGreenResultsAndStopsTransferring() {
        let vm = TransferViewModel(isBackgroundWorker: true)
        var settings = DemoSettings()
        settings.state = .done
        vm.applyDemoRun(configId: UUID(), sources: ["/s"], destinations: ["/d1", "/d2"],
                        verifyMode: .paranoid, settings: settings)
        XCTAssertFalse(vm.isTransferring)
        XCTAssertEqual(vm.results.count, 2)
        XCTAssertTrue(vm.results.allSatisfy { $0.success && $0.wasVerified })
        XCTAssertTrue(vm.progress.perDestProgress.allSatisfy { $0.isComplete })
    }

    @MainActor
    func test_applyDemoRun_copying_isActiveWithoutResults() {
        let vm = TransferViewModel(isBackgroundWorker: true)
        vm.applyDemoRun(configId: UUID(), sources: [], destinations: ["/d1"],
                        verifyMode: .fast, settings: DemoSettings())
        XCTAssertTrue(vm.isTransferring)
        XCTAssertTrue(vm.results.isEmpty)
        XCTAssertEqual(vm.progress.perDestProgress.first?.bytesCompleted, 8_850_000_000)
    }
}
#endif
