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
}
