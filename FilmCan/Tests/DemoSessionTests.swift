import XCTest
@testable import FilmCan

@MainActor
final class DemoSessionTests: XCTestCase {
    private var tmp: URL!
    private var defaults: UserDefaults!
    private let suite = "filmcan.tests.demoSession"
    private var storage: ConfigurationStorage!
    private var catalog: MediaCatalogStore!
    private var rollStore: RollNumberingStore!
    private var root: URL { tmp.appendingPathComponent("Demo") }
    private let clipBytes = 64 * 1024

    override func setUp() async throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        UserDefaults().removePersistentDomain(forName: suite)
        defaults = UserDefaults(suiteName: suite)
        storage = ConfigurationStorage(baseDirectory: tmp.appendingPathComponent("data"))
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("data"), withIntermediateDirectories: true)
        catalog = MediaCatalogStore(fileURL: tmp.appendingPathComponent("catalog.json"))
        rollStore = RollNumberingStore(fileURL: tmp.appendingPathComponent("roll-numbering.json"))
    }

    override func tearDown() async throws {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: tmp)
    }

    private func start() throws -> BackupConfiguration {
        try DemoSession.start(storage: storage, catalog: catalog, rollStore: rollStore,
                              root: root, clipBytes: clipBytes, defaults: defaults)
    }

    private func stop() {
        DemoSession.stop(storage: storage, catalog: catalog, rollStore: rollStore, root: root, defaults: defaults)
    }

    private func historyEntry(for configId: UUID?) -> TransferHistoryEntry {
        TransferHistoryEntry(
            configId: configId, configName: "x", startedAt: Date(), endedAt: Date(), success: true,
            sources: [], destinations: [], results: [],
            options: TransferOptionsSnapshot(config: BackupConfiguration(), presetName: nil),
            hashListPath: nil)
    }

    private func catalogRoll(for configId: UUID?, name: String) -> CatalogRoll {
        CatalogRoll(configId: configId, projectName: name, shootDay: "Day01", rollName: "A001",
                    mediaKind: .camera, sourceVolumeUUID: nil, sourcePath: "/src/\(name)",
                    firstBackedUp: Date(), files: [], copies: [])
    }

    func test_start_createsTheMadeUpCardsDrivesAndMovie() throws {
        let config = try start()
        let layout = DemoSession.Layout(root: root)
        let fm = FileManager.default

        XCTAssertEqual(try fm.contentsOfDirectory(atPath: layout.cameraCard.path).count, DemoSession.cameraClipCount)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: layout.soundCard.path).count, DemoSession.soundClipCount)
        for drive in layout.drives {
            XCTAssertEqual(try fm.contentsOfDirectory(atPath: drive.path), [])
        }
        let clip = layout.cameraCard.appendingPathComponent("A001C001_DEMO.mov")
        XCTAssertEqual(try fm.attributesOfItem(atPath: clip.path)[.size] as? Int, clipBytes)

        XCTAssertEqual(config.name, DemoSession.movieName)
        XCTAssertEqual(config.sourcePaths, [layout.cameraCard.path, layout.soundCard.path])
        XCTAssertEqual(config.sourceMediaKinds, [layout.soundCard.path: .sound])
        XCTAssertEqual(config.destinationPaths, layout.drives.map(\.path))
        XCTAssertEqual(config.engineOptions.verificationMode, .paranoid)

        XCTAssertTrue(storage.configurations.contains { $0.id == config.id })
        XCTAssertTrue(DemoSession.isDemo(config.id, defaults: defaults))
        XCTAssertTrue(DemoSession.isRunning(storage: storage, defaults: defaults))
        XCTAssertFalse(DemoSession.isDemo(UUID(), defaults: defaults))
        XCTAssertFalse(DemoSession.isDemo(nil, defaults: defaults))
    }

    func test_stop_removesEverythingOfTheDemo_andNothingElse() throws {
        var real = BackupConfiguration()
        real.name = "Citizen K"
        storage.add(real)
        let demo = try start()

        let countBefore = storage.totalTransferCount
        defer { storage.totalTransferCount = countBefore }
        storage.appendHistory(historyEntry(for: real.id), retentionLimit: 200)
        let countWithRealRun = storage.totalTransferCount
        storage.appendHistory(historyEntry(for: demo.id), retentionLimit: 200)
        storage.appendHistory(historyEntry(for: demo.id), retentionLimit: 200)
        catalog.merge(catalogRoll(for: real.id, name: "Citizen K"))
        catalog.merge(catalogRoll(for: demo.id, name: "Demo"))
        var state = RollNumberingStore.ConfigState()
        state.assignments = ["k|": "A001"]
        rollStore.update(state, for: real.id)
        rollStore.update(state, for: demo.id)

        stop()

        XCTAssertEqual(storage.configurations.map(\.id), [real.id])
        XCTAssertEqual(storage.transferHistory.map(\.configId), [real.id])
        XCTAssertEqual(storage.totalTransferCount, countWithRealRun, "demo runs are not counted as backups")
        XCTAssertEqual(catalog.rolls.map(\.configId), [real.id])
        XCTAssertEqual(rollStore.state(for: real.id).assignments, ["k|": "A001"])
        XCTAssertTrue(rollStore.state(for: demo.id).assignments.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertNil(DemoSession.demoConfigId(defaults: defaults))
        XCTAssertFalse(DemoSession.isRunning(storage: storage, defaults: defaults))

        // Saved: a relaunch does not bring the demo back.
        let reloaded = ConfigurationStorage(baseDirectory: tmp.appendingPathComponent("data"))
        XCTAssertEqual(reloaded.configurations.map(\.id), [real.id])
        XCTAssertEqual(reloaded.transferHistory.map(\.configId), [real.id])
        XCTAssertEqual(MediaCatalogStore(fileURL: tmp.appendingPathComponent("catalog.json")).rolls.map(\.configId), [real.id])
    }

    func test_stop_withoutADemo_changesNothing() {
        var real = BackupConfiguration()
        real.name = "Citizen K"
        storage.add(real)
        stop()
        XCTAssertEqual(storage.configurations.map(\.id), [real.id])
    }

    func test_startAgain_replacesAnEarlierDemo() throws {
        let first = try start()
        let second = try start()
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(storage.configurations.map(\.id), [second.id])
        XCTAssertTrue(DemoSession.isDemo(second.id, defaults: defaults))
    }

    func test_demoMovieDeletedByHand_isNotRunning_andStopStillCleansUp() throws {
        let demo = try start()
        storage.delete(demo)
        XCTAssertFalse(DemoSession.isRunning(storage: storage, defaults: defaults))
        stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        XCTAssertNil(DemoSession.demoConfigId(defaults: defaults))
    }

    func test_muted_switchesOffPhoneAndWebhookOnly() {
        let settings = NotificationSettings(
            notifyOnComplete: true, notifyOnError: true, ntfyEnabled: true, ntfyURL: "https://example.invalid/t",
            ntfyTitleTemplate: "t", ntfyMessageTemplate: "m", webhookEnabled: true,
            webhookURL: "https://example.invalid/h", webhookIncludeFullPaths: false)
        let muted = DemoSession.muted(settings)
        XCTAssertFalse(muted.ntfyEnabled)
        XCTAssertFalse(muted.webhookEnabled)
        XCTAssertTrue(muted.notifyOnComplete)
        XCTAssertTrue(muted.notifyOnError)
    }

    /// The made-up cards go through the real engine, with the full check, to both drives.
    func test_theDemoCopyIsARealVerifiedCopy() async throws {
        let config = try start()
        let layout = DemoSession.Layout(root: root)
        let cfg = FanOutCopier.Configuration(
            sources: config.sourcePaths,
            destinations: layout.drives.enumerated().map { index, drive in
                DestWriter.Config(destPath: drive.path, displayName: "D\(index + 1)",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)
            },
            verifyMode: .paranoid, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.count, 2)

        let fm = FileManager.default
        for drive in layout.drives {
            for card in [layout.cameraCard, layout.soundCard] {
                let copied = drive.appendingPathComponent(card.lastPathComponent)
                for name in try fm.contentsOfDirectory(atPath: card.path) {
                    XCTAssertTrue(fm.contentsEqual(atPath: card.appendingPathComponent(name).path,
                                                   andPath: copied.appendingPathComponent(name).path),
                                  "\(name) on \(drive.lastPathComponent)")
                }
            }
        }
        stop()
        XCTAssertFalse(fm.fileExists(atPath: root.path))
    }
}
