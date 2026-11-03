import XCTest
@testable import FilmCan

final class MediaCatalogTests: XCTestCase {

    private func copy(_ uuid: String?, name: String = "SSD", path: String? = nil,
                      verified: Bool = true, date: Date = Date()) -> CatalogCopy {
        CatalogCopy(destVolumeUUID: uuid, destVolumeName: name,
                    rollFolderPath: path ?? "/Volumes/\(uuid ?? name)/A001",
                    verified: verified, date: date)
    }

    private func roll(copies: [CatalogCopy], files: [CatalogFile] = [],
                      rollName: String = "A001", sourceUUID: String? = "SRC") -> CatalogRoll {
        CatalogRoll(configId: nil, projectName: "Proj", shootDay: "Day 1", rollName: rollName,
                    mediaKind: .camera, sourceVolumeUUID: sourceUUID, sourcePath: "/Volumes/CARD",
                    firstBackedUp: Date(timeIntervalSince1970: 1_000), files: files, copies: copies)
    }

    func test_coverage_twoDistinctUUIDs_isSafe() {
        let r = roll(copies: [copy("A"), copy("B")])
        XCTAssertEqual(r.coverage, .safe(drives: 2))
    }

    func test_coverage_sameUUIDTwice_isSingle() {
        let r = roll(copies: [copy("A", path: "/Volumes/X/A001"), copy("A", path: "/Volumes/X/B/A001")])
        XCTAssertEqual(r.coverage, .single)
    }

    func test_coverage_twoDrivesBothNamedUntitled_differentUUIDs_isSafe() {
        let r = roll(copies: [copy("A", name: "Untitled"), copy("B", name: "Untitled")])
        XCTAssertEqual(r.coverage, .safe(drives: 2))
    }

    func test_coverage_unverifiedCopyDoesNotCount() {
        let r = roll(copies: [copy("A"), copy("B", verified: false)])
        XCTAssertEqual(r.coverage, .single)
    }

    func test_merge_sameIdentity_upsertsCopyByDrive() {
        let first = roll(copies: [copy("A")])
        var merged = MediaCatalog.merge(first, into: [])
        merged = MediaCatalog.merge(roll(copies: [copy("B")]), into: merged)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].copies.count, 2)

        let later = Date(timeIntervalSince1970: 9_999)
        merged = MediaCatalog.merge(roll(copies: [copy("B", date: later)]), into: merged)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].copies.count, 2)
        XCTAssertEqual(merged[0].copies.first { $0.destVolumeUUID == "B" }?.date, later)
    }

    func test_merge_differentSourceUUID_sameRollName_keepsTwoRolls() {
        var merged = MediaCatalog.merge(roll(copies: [copy("A")], sourceUUID: "S1"), into: [])
        merged = MediaCatalog.merge(roll(copies: [copy("A")], sourceUUID: "S2"), into: merged)
        XCTAssertEqual(merged.count, 2)
    }

    func test_search_matchesBasenameCaseInsensitive() {
        let r = roll(copies: [copy("A")], files: [
            CatalogFile(relPath: "Clip/C0042.MP4", size: 1),
            CatalogFile(relPath: "Clip/C0043.MP4", size: 1),
        ])
        let hits = MediaCatalog.search("c0042", in: [r])
        XCTAssertEqual(hits.map(\.file.relPath), ["Clip/C0042.MP4"])
    }

    func test_search_emptyQuery_returnsNothing() {
        let r = roll(copies: [copy("A")], files: [CatalogFile(relPath: "C0042.MP4", size: 1)])
        XCTAssertTrue(MediaCatalog.search("  ", in: [r]).isEmpty)
        XCTAssertTrue(MediaCatalog.search("", in: [r]).isEmpty)
    }

    // MARK: - Store

    @MainActor
    func test_store_roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = MediaCatalogStore(fileURL: url)
        store.merge(roll(copies: [copy("A")], files: [CatalogFile(relPath: "C0001.MP4", size: 5)]))
        store.save()
        let reloaded = MediaCatalogStore(fileURL: url)
        XCTAssertEqual(reloaded.rolls.count, 1)
        XCTAssertEqual(reloaded.rolls[0].files, [CatalogFile(relPath: "C0001.MP4", size: 5)])
        XCTAssertEqual(reloaded.rolls[0].copies.count, 1)
    }

    @MainActor
    func test_store_corruptFile_startsEmptyAndQuarantines() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("catalog-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("catalog.json")
        try Data("{not json".utf8).write(to: url)
        let store = MediaCatalogStore(fileURL: url)
        XCTAssertTrue(store.rolls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("catalog.json.corrupt-") })
    }

    @MainActor
    func test_record_fromRealFanOutRun() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("catalog-run-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let card = tmp.appendingPathComponent("CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        for name in ["C0001.bin", "C0002.bin", "C0003.bin"] {
            try Data((0..<8 * 1024).map { _ in UInt8.random(in: 0...255) })
                .write(to: card.appendingPathComponent(name))
        }
        let d1 = tmp.appendingPathComponent("d1"), d2 = tmp.appendingPathComponent("d2")
        try fm.createDirectory(at: d1, withIntermediateDirectories: true)
        try fm.createDirectory(at: d2, withIntermediateDirectories: true)

        let cfg = FanOutCopier.Configuration(
            sources: [card.path],
            destinations: [
                DestWriter.Config(destPath: d1.path, displayName: "D1",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768),
                DestWriter.Config(destPath: d2.path, displayName: "D2",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .paranoid, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        let destResults = try await FanOutCopier(config: cfg).run()

        let now = Date()
        var fanOut = TransferResult(configurationName: "Proj", destination: d1.path,
                                    startTime: now, endTime: now, success: true)
        fanOut.destinationResults = destResults
        let vm = TransferViewModel()
        let exploded = vm.explodeFanOutResult(fanOut, configName: "Proj")

        let url = tmp.appendingPathComponent("catalog.json")
        let store = MediaCatalogStore(fileURL: url)
        var config = BackupConfiguration()
        config.name = "Proj"
        await store.record(config: config, sources: [card.path], results: exploded, runDate: now)

        XCTAssertEqual(store.rolls.count, 1)
        XCTAssertEqual(store.rolls[0].files.count, 3)
        XCTAssertEqual(store.rolls[0].copies.count, 2)
        XCTAssertEqual(store.rolls[0].rollName, "CARD")
        // Both temp dests live on one disk, so they count as a single drive: expected.
        XCTAssertEqual(store.rolls[0].coverage, .single)
        XCTAssertEqual(MediaCatalogStore(fileURL: url).rolls.count, 1)
    }
}
