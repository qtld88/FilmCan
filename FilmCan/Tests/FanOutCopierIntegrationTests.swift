import XCTest
@testable import FilmCan

final class FanOutCopierIntegrationTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fanout-int-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir = tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    func test_fanOut_toTwoDestinations() async throws {
        let fm = FileManager.default

        // Create source file (1MB of random data)
        let sourceURL = tmpDir.appendingPathComponent("source.bin")
        let sourceData = Data((0..<1024*1024).map { _ in UInt8.random(in: 0...255) })
        try sourceData.write(to: sourceURL)

        // Create two destination directories
        let dest1 = tmpDir.appendingPathComponent("dest1")
        let dest2 = tmpDir.appendingPathComponent("dest2")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest2, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: dest1.path, displayName: "Dest1",
                                 verifyMode: .paranoid, requiresFullFsync: false,
                                 chunkSize: 65536),
                DestWriter.Config(destPath: dest2.path, displayName: "Dest2",
                                 verifyMode: .fast, requiresFullFsync: false,
                                 chunkSize: 65536)
            ],
            verifyMode: .paranoid,
            mhlBasePath: tmpDir.path,
            dryRun: false,
            progressHandler: nil
        )

        let copier = FanOutCopier(config: config)
        let results = try await copier.run()

        // Verify both succeeded
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results[0].success, "Dest1 should succeed")
        XCTAssertTrue(results[1].success, "Dest2 should succeed")

        // Verify files exist with correct content
        let file1 = dest1.appendingPathComponent("source.bin")
        let file2 = dest2.appendingPathComponent("source.bin")
        XCTAssertTrue(fm.fileExists(atPath: file1.path), "File should exist in dest1")
        XCTAssertTrue(fm.fileExists(atPath: file2.path), "File should exist in dest2")

        let data1 = try Data(contentsOf: file1)
        let data2 = try Data(contentsOf: file2)
        XCTAssertEqual(data1, sourceData, "Dest1 content should match source")
        XCTAssertEqual(data2, sourceData, "Dest2 content should match source")

        // Verify no temp files remain
        let contents1 = try fm.contentsOfDirectory(atPath: dest1.path)
        let contents2 = try fm.contentsOfDirectory(atPath: dest2.path)
        XCTAssertFalse(contents1.contains { $0.hasPrefix(".filmcan-") }, "No temp files in dest1")
        XCTAssertFalse(contents2.contains { $0.hasPrefix(".filmcan-") }, "No temp files in dest2")

        // Verify MHL file per destination
        let mhl1 = dest1.appendingPathComponent(".filmcan/hashlists/source.bin.mhl")
        let mhl2 = dest2.appendingPathComponent(".filmcan/hashlists/source.bin.mhl")
        XCTAssertTrue(fm.fileExists(atPath: mhl1.path), "MHL should exist in dest1")
        XCTAssertTrue(fm.fileExists(atPath: mhl2.path), "MHL should exist in dest2")
        let entries1 = try MHLReader.read(url: mhl1)
        XCTAssertEqual(entries1.count, 1)
        XCTAssertEqual(entries1[0].fileName, "source.bin")
        let entries2 = try MHLReader.read(url: mhl2)
        XCTAssertEqual(entries2.count, 1)
        XCTAssertEqual(entries2[0].fileName, "source.bin")
    }

    func test_fanOut_sourceNotFound() async throws {
        let config = FanOutCopier.Configuration(
            sources: ["/nonexistent/path/file.bin"],
            destinations: [
                DestWriter.Config(destPath: tmpDir.path, displayName: "Dest",
                                 verifyMode: .paranoid, requiresFullFsync: false,
                                 chunkSize: nil)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let copier = FanOutCopier(config: config)
        do {
            _ = try await copier.run()
            XCTFail("Should throw sourceNotFound")
        } catch let err as FanOutCopier.Error {
            switch err {
            case .sourceNotFound: break // Expected
            default: XCTFail("Wrong error: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fanOut_multipleSources_allCopiedToAllDests() async throws {
        let fm = FileManager.default
        let src1 = tmpDir.appendingPathComponent("clip-a.bin")
        let src2 = tmpDir.appendingPathComponent("clip-b.bin")
        let src3 = tmpDir.appendingPathComponent("clip-c.bin")
        let data1 = Data((0..<256 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data2 = Data((0..<256 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data3 = Data((0..<256 * 1024).map { _ in UInt8.random(in: 0...255) })
        try data1.write(to: src1)
        try data2.write(to: src2)
        try data3.write(to: src3)

        let dest1 = tmpDir.appendingPathComponent("multi-dest1")
        let dest2 = tmpDir.appendingPathComponent("multi-dest2")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest2, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [src1.path, src2.path, src3.path],
            destinations: [
                DestWriter.Config(destPath: dest1.path, displayName: "D1",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768),
                DestWriter.Config(destPath: dest2.path, displayName: "D2",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertTrue(results.allSatisfy { $0.filesTransferred == 3 })

        for (name, expected) in [("clip-a.bin", data1), ("clip-b.bin", data2), ("clip-c.bin", data3)] {
            let d1 = try Data(contentsOf: dest1.appendingPathComponent(name))
            let d2 = try Data(contentsOf: dest2.appendingPathComponent(name))
            XCTAssertEqual(d1, expected, "\(name) at dest1 should match source")
            XCTAssertEqual(d2, expected, "\(name) at dest2 should match source")
        }
    }

    func test_fanOut_fastMode_succeedsAndProducesIdenticalBytes() async throws {
        let fm = FileManager.default
        let sourceURL = tmpDir.appendingPathComponent("fast-source.bin")
        let sourceData = Data((0..<512 * 1024).map { _ in UInt8.random(in: 0...255) })
        try sourceData.write(to: sourceURL)

        let dest1 = tmpDir.appendingPathComponent("fast-dest1")
        let dest2 = tmpDir.appendingPathComponent("fast-dest2")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest2, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: dest1.path, displayName: "D1",
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768),
                DestWriter.Config(destPath: dest2.path, displayName: "D2",
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .fast,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.success })

        let f1 = try Data(contentsOf: dest1.appendingPathComponent("fast-source.bin"))
        let f2 = try Data(contentsOf: dest2.appendingPathComponent("fast-source.bin"))
        XCTAssertEqual(f1, sourceData)
        XCTAssertEqual(f2, sourceData)
    }

    func test_fanOut_noDestinations() async throws {
        let config = FanOutCopier.Configuration(
            sources: ["/some/file.bin"],
            destinations: [],
            verifyMode: .paranoid, mhlBasePath: nil, dryRun: false,
            progressHandler: nil
        )
        let copier = FanOutCopier(config: config)
        do {
            _ = try await copier.run()
            XCTFail("Should throw noDestinations")
        } catch let err as FanOutCopier.Error {
            switch err {
            case .noDestinations: break
            default: XCTFail("Wrong error: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_fanOut_directorySource_copiesTreeToBothDests() async throws {
        let fm = FileManager.default

        // Build source tree: <root>/CARD with three files directly at root
        let cardRoot = tmpDir.appendingPathComponent("CARD")
        try fm.createDirectory(at: cardRoot, withIntermediateDirectories: true)

        let clip1 = cardRoot.appendingPathComponent("clip-001.bin")
        let clip2 = cardRoot.appendingPathComponent("clip-002.bin")
        let clip3 = cardRoot.appendingPathComponent("clip-003.bin")
        let data1 = Data((0..<128 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data2 = Data((0..<256 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data3 = Data((0..<64 * 1024).map { _ in UInt8.random(in: 0...255) })
        try data1.write(to: clip1)
        try data2.write(to: clip2)
        try data3.write(to: clip3)

        let dest1 = tmpDir.appendingPathComponent("dir-dest1")
        let dest2 = tmpDir.appendingPathComponent("dir-dest2")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest2, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [cardRoot.path],
            destinations: [
                DestWriter.Config(destPath: dest1.path, displayName: "D1",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768),
                DestWriter.Config(destPath: dest2.path, displayName: "D2",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertTrue(results.allSatisfy { $0.filesTransferred == 3 },
                      "Each dest should report 3 files transferred (got \(results.map(\.filesTransferred)))")

        // Mirror layout: dest/CARD/{clip-001, clip-002, clip-003}.bin
        for dest in [dest1, dest2] {
            let f1 = dest.appendingPathComponent("CARD/clip-001.bin")
            let f2 = dest.appendingPathComponent("CARD/clip-002.bin")
            let f3 = dest.appendingPathComponent("CARD/clip-003.bin")
            XCTAssertTrue(fm.fileExists(atPath: f1.path), "Missing \(f1.path)")
            XCTAssertTrue(fm.fileExists(atPath: f2.path), "Missing \(f2.path)")
            XCTAssertTrue(fm.fileExists(atPath: f3.path), "Missing \(f3.path)")
            XCTAssertEqual(try Data(contentsOf: f1), data1)
            XCTAssertEqual(try Data(contentsOf: f2), data2)
            XCTAssertEqual(try Data(contentsOf: f3), data3)
        }

        // One MHL per source root per dest, with all 3 files aggregated
        for dest in [dest1, dest2] {
            let mhl = dest.appendingPathComponent(".filmcan/hashlists/CARD.mhl")
            XCTAssertTrue(fm.fileExists(atPath: mhl.path), "Missing MHL at \(mhl.path)")
            let entries = try MHLReader.read(url: mhl)
            XCTAssertEqual(entries.count, 3, "MHL should aggregate all 3 files in the source root")
        }
    }

    func test_fanOut_mixedFlatAndDirectorySources() async throws {
        let fm = FileManager.default

        // Flat file source
        let loose = tmpDir.appendingPathComponent("loose.bin")
        let looseData = Data((0..<200 * 1024).map { _ in UInt8.random(in: 0...255) })
        try looseData.write(to: loose)

        // Directory source with two files
        let card = tmpDir.appendingPathComponent("CARD2")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        let a = card.appendingPathComponent("a.bin")
        let b = card.appendingPathComponent("b.bin")
        let aData = Data((0..<128 * 1024).map { _ in UInt8.random(in: 0...255) })
        let bData = Data((0..<384 * 1024).map { _ in UInt8.random(in: 0...255) })
        try aData.write(to: a)
        try bData.write(to: b)

        let dest = tmpDir.appendingPathComponent("mixed-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let config = FanOutCopier.Configuration(
            sources: [loose.path, card.path],
            destinations: [
                DestWriter.Config(destPath: dest.path, displayName: "MD",
                                  verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].filesTransferred, 3)

        // Layout: dest/loose.bin and dest/CARD2/{a,b}.bin
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("loose.bin")), looseData)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD2/a.bin")), aData)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD2/b.bin")), bData)

        // Two MHLs: one per source root
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(".filmcan/hashlists/loose.bin.mhl").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(".filmcan/hashlists/CARD2.mhl").path))

        let looseEntries = try MHLReader.read(url: dest.appendingPathComponent(".filmcan/hashlists/loose.bin.mhl"))
        XCTAssertEqual(looseEntries.count, 1)
        let cardEntries = try MHLReader.read(url: dest.appendingPathComponent(".filmcan/hashlists/CARD2.mhl"))
        XCTAssertEqual(cardEntries.count, 2)
    }
}
