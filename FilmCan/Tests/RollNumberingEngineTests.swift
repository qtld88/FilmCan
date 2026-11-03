import XCTest
@testable import FilmCan

final class RollNumberingEngineTests: XCTestCase {
    var tmpDir: URL!
    let fm = FileManager.default

    override func setUp() async throws {
        tmpDir = fm.temporaryDirectory.appendingPathComponent("rollnum-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir { try? fm.removeItem(at: tmpDir) }
    }

    private func makeCard(_ name: String, under parent: String = "src", files: Int = 3) throws -> URL {
        let card = tmpDir.appendingPathComponent(parent).appendingPathComponent(name)
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        for i in 1...files {
            try Data((0..<20_000).map { _ in UInt8.random(in: 0...255) })
                .write(to: card.appendingPathComponent("clip-\(i).bin"))
        }
        return card
    }

    private func makeDest(_ name: String = "dest") throws -> URL {
        let d = tmpDir.appendingPathComponent(name)
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private func config(sources: [URL], dest: URL, rollNames: [String: String],
                        preset: OrganizationPreset? = nil, metadata: ShootMetadata = .empty,
                        copyFolderContents: Bool = false) -> FanOutCopier.Configuration {
        FanOutCopier.Configuration(
            sources: sources.map(\.path),
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "D",
                                             verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)],
            verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: nil,
            organizationPreset: preset, copyFolderContents: copyFolderContents,
            shootMetadata: metadata, rollNames: rollNames)
    }

    private func ascMHLExists(_ dir: URL) -> Bool {
        ASCMHLChain.latestManifestPath(ascmhlDir: dir) != nil
    }

    func test_assignedName_replacesVolumeName() async throws {
        let card = try makeCard("Untitled")
        let dest = try makeDest()
        let results = try await FanOutCopier(config: config(sources: [card], dest: dest, rollNames: [card.path: "A001"])).run()
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A001/clip-1.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("Untitled").path))
        XCTAssertTrue(ascMHLExists(dest.appendingPathComponent("A001/ascmhl")))
    }

    func test_assignedName_withNetflixPreset_rollFolderEndsWithName() async throws {
        let card = try makeCard("Untitled")
        let dest = try makeDest()
        let meta = ShootMetadata(episode: "EP103", day: "Day05", unit: "MU", cameraFormat: "ARRI")
        let results = try await FanOutCopier(config: config(
            sources: [card], dest: dest, rollNames: [card.path: "A001"],
            preset: .netflixIngest(), metadata: meta)).run()
        XCTAssertTrue(results.allSatisfy { $0.success })
        let enumerator = fm.enumerator(atPath: dest.path)
        var found: String?
        while let rel = enumerator?.nextObject() as? String {
            if rel.hasSuffix("/A001/clip-1.bin") { found = rel }
        }
        let rel = try XCTUnwrap(found, "no A001 roll folder under the Netflix layout")
        XCTAssertTrue(rel.contains("Camera_Media"))
        XCTAssertFalse(rel.contains("Untitled"))
    }

    func test_secondRun_resumesIntoSameRoll() async throws {
        let card = try makeCard("Untitled")
        let dest = try makeDest()
        let cfg = config(sources: [card], dest: dest, rollNames: [card.path: "A001"])
        _ = try await FanOutCopier(config: cfg).run()
        let second = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(second.first?.filesSkipped, 3)
        XCTAssertEqual(second.first?.filesTransferred, 0)
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("A001-2").path))
    }

    func test_twoSourcesSameBasename_getDistinctAssignedNames() async throws {
        let a = try makeCard("Untitled", under: "cardA")
        let b = try makeCard("Untitled", under: "cardB")
        let dest = try makeDest()
        _ = try await FanOutCopier(config: config(
            sources: [a, b], dest: dest, rollNames: [a.path: "A001", b.path: "A002"])).run()
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A001/clip-1.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A002/clip-1.bin").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("A001-2").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("Untitled-2").path))
    }

    func test_emptyRollNames_keepsTodaysLayout() async throws {
        let card = try makeCard("Untitled")
        let dest = try makeDest()
        _ = try await FanOutCopier(config: config(sources: [card], dest: dest, rollNames: [:])).run()
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Untitled/clip-1.bin").path))
        XCTAssertTrue(ascMHLExists(dest.appendingPathComponent("Untitled/ascmhl")))
    }

    func test_assignedNameWithRenameTemplate_isNotMisSplit() async throws {
        let card = try makeCard("A")
        let dest = try makeDest()
        var preset = OrganizationPreset()
        preset.name = "Custom"
        preset.useRenameTemplate = true
        preset.renameTemplate = "{source}_{date}"
        _ = try await FanOutCopier(config: config(
            sources: [card], dest: dest, rollNames: [card.path: "A003"], preset: preset)).run()
        var found = false
        let enumerator = fm.enumerator(atPath: dest.path)
        while let rel = enumerator?.nextObject() as? String {
            if rel.hasSuffix("clip-1.bin") {
                found = true
                XCTAssertTrue(rel.hasPrefix("A003/") || rel.contains("/A003/"), "got \(rel)")
            }
        }
        XCTAssertTrue(found)
    }
}
