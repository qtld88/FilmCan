import XCTest
@testable import FilmCan

private actor VerifyEmitCollector {
    var verify: [Int64] = []
    func add(_ v: Int64) { verify.append(v) }
}

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

        // Verify MHL file per destination (flat-file root: MHL at dest/ascmhl/<generation>.mhl)
        XCTAssertTrue(ascMHLExists(ascmhlDir: dest1.appendingPathComponent("ascmhl")), "MHL should exist in dest1")
        XCTAssertTrue(ascMHLExists(ascmhlDir: dest2.appendingPathComponent("ascmhl")), "MHL should exist in dest2")
        let entries1 = try readLatestASCMHL(ascmhlDir: dest1.appendingPathComponent("ascmhl"))
        XCTAssertEqual(entries1.count, 1)
        XCTAssertEqual(entries1[0].relPath, "source.bin")
        let entries2 = try readLatestASCMHL(ascmhlDir: dest2.appendingPathComponent("ascmhl"))
        XCTAssertEqual(entries2.count, 1)
        XCTAssertEqual(entries2[0].relPath, "source.bin")
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
        // (directory root "CARD": MHL at dest/CARD/ascmhl/<generation>.mhl)
        for dest in [dest1, dest2] {
            let ascmhlDir = dest.appendingPathComponent("CARD/ascmhl")
            XCTAssertTrue(ascMHLExists(ascmhlDir: ascmhlDir), "Missing MHL at \(ascmhlDir.path)")
            let entries = try readLatestASCMHL(ascmhlDir: ascmhlDir)
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
        // loose.bin (flat): dest/ascmhl/<generation>.mhl
        // CARD2 (dir): dest/CARD2/ascmhl/<generation>.mhl
        XCTAssertTrue(ascMHLExists(ascmhlDir: dest.appendingPathComponent("ascmhl")))
        XCTAssertTrue(ascMHLExists(ascmhlDir: dest.appendingPathComponent("CARD2/ascmhl")))

        let looseEntries = try readLatestASCMHL(ascmhlDir: dest.appendingPathComponent("ascmhl"))
        XCTAssertEqual(looseEntries.count, 1)
        let cardEntries = try readLatestASCMHL(ascmhlDir: dest.appendingPathComponent("CARD2/ascmhl"))
        XCTAssertEqual(cardEntries.count, 2)
    }

    func test_verifyBytesCompleted_isMonotonicAcrossFiles() async throws {
        let fm = FileManager.default

        // Create 3 source files of increasing size
        let src1 = tmpDir.appendingPathComponent("clip-a.bin")
        let src2 = tmpDir.appendingPathComponent("clip-b.bin")
        let src3 = tmpDir.appendingPathComponent("clip-c.bin")
        let data1 = Data((0..<256 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data2 = Data((0..<384 * 1024).map { _ in UInt8.random(in: 0...255) })
        let data3 = Data((0..<128 * 1024).map { _ in UInt8.random(in: 0...255) })
        try data1.write(to: src1)
        try data2.write(to: src2)
        try data3.write(to: src3)

        let dest = tmpDir.appendingPathComponent("mono-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        // Thread-safe capture: with the copy/verify pipeline the handler is
        // called from concurrent producers, so plain array appends would race.
        let lock = NSLock()
        var verifyDoneValues: [Int64] = []   // from the serial verify lane (ordered)
        var allVerifyValues: [Int64] = []
        let progressHandler: @Sendable (DestProgress) -> Void = { prog in
            guard prog.verifyBytesTotal > 0 else { return }
            lock.lock()
            allVerifyValues.append(prog.verifyBytesCompleted)
            // Verify-completion emits come from the single serial verify lane in
            // order ("✓ name"); their relative capture order is preserved by the
            // lock, so this subsequence must be monotonic.
            if prog.currentFile.hasPrefix("✓") {
                verifyDoneValues.append(prog.verifyBytesCompleted)
            }
            lock.unlock()
        }

        let config = FanOutCopier.Configuration(
            sources: [src1.path, src2.path, src3.path],
            destinations: [
                DestWriter.Config(destPath: dest.path, displayName: "Mono",
                                  verifyMode: .paranoid, requiresFullFsync: false,
                                  chunkSize: 65536)
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: progressHandler
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].success)
        XCTAssertEqual(results[0].filesTransferred, 3)

        let totalBytes = Int64(data1.count + data2.count + data3.count)

        // No emit may report more verified than the whole job.
        for v in allVerifyValues {
            XCTAssertLessThanOrEqual(v, totalBytes, "verifyBytesCompleted exceeded total")
        }

        // The serial verify lane's completion emits must be monotonic and reach
        // the full job size.
        var last: Int64 = -1
        for v in verifyDoneValues {
            XCTAssertGreaterThanOrEqual(v, last,
                "verify-lane completion decreased from \(last) to \(v)")
            last = v
        }
        XCTAssertEqual(verifyDoneValues.last, totalBytes,
                       "Final verified bytes should equal total bytes of all sources")
    }

    func test_copyBytesCompleted_startsLowMonotonicReachesTotal() async throws {
        let fm = FileManager.default
        let src1 = tmpDir.appendingPathComponent("m-a.bin")
        let src2 = tmpDir.appendingPathComponent("m-b.bin")
        let src3 = tmpDir.appendingPathComponent("m-c.bin")
        let d1 = Data((0..<300 * 1024).map { _ in UInt8.random(in: 0...255) })
        let d2 = Data((0..<400 * 1024).map { _ in UInt8.random(in: 0...255) })
        let d3 = Data((0..<100 * 1024).map { _ in UInt8.random(in: 0...255) })
        try d1.write(to: src1); try d2.write(to: src2); try d3.write(to: src3)
        let dest = tmpDir.appendingPathComponent("copybar-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let total = Int64(d1.count + d2.count + d3.count)

        let lock = NSLock()
        var copyValues: [Int64] = []  // bytesCompleted from copy-phase emits, in order
        let handler: @Sendable (DestProgress) -> Void = { prog in
            // Copy-phase emits carry the bare file name; verify emits are prefixed.
            let cf = prog.currentFile
            guard !cf.hasPrefix("Verifying"), !cf.hasPrefix("✓"),
                  !cf.hasPrefix("✗"), !cf.hasPrefix("Cancelled"), prog.bytesTotal > 0 else { return }
            lock.lock(); copyValues.append(prog.bytesCompleted); lock.unlock()
        }

        let config = FanOutCopier.Configuration(
            sources: [src1.path, src2.path, src3.path],
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "C",
                                             verifyMode: .fast, requiresFullFsync: false, chunkSize: 65536)],
            verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: handler)

        let results = try await FanOutCopier(config: config).run()
        XCTAssertTrue(results[0].success)

        XCTAssertFalse(copyValues.isEmpty)
        // Must start at the first file's bytes, not jump to ~total — the bug
        // emitted a near-total cumulative on the very first tick.
        XCTAssertLessThanOrEqual(copyValues.first ?? .max, Int64(d1.count),
                                 "copy bar started high (\(copyValues.first ?? -1)) instead of near 0")
        XCTAssertLessThan(Int64(d1.count), total)  // sanity: total is well above one file
        var last: Int64 = -1
        for v in copyValues {
            XCTAssertLessThanOrEqual(v, total, "copy bytesCompleted exceeded total")
            XCTAssertGreaterThanOrEqual(v, last, "copy bytesCompleted decreased \(last)→\(v)")
            last = v
        }
        XCTAssertEqual(copyValues.last, total, "copy bar should reach the full job size")
    }

    func test_soundTaggedSource_routesUnderSoundMedia() async throws {
        let fm = FileManager.default
        let cam = tmpDir.appendingPathComponent("A001")
        let snd = tmpDir.appendingPathComponent("SR001")
        try fm.createDirectory(at: cam, withIntermediateDirectories: true)
        try fm.createDirectory(at: snd, withIntermediateDirectories: true)
        try Data((0..<40_000).map { _ in UInt8.random(in: 0...255) }).write(to: cam.appendingPathComponent("a.mxf"))
        try Data((0..<30_000).map { _ in UInt8.random(in: 0...255) }).write(to: snd.appendingPathComponent("s.wav"))
        let dest = tmpDir.appendingPathComponent("nfdest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        var preset = OrganizationPreset()
        preset.name = OrganizationPreset.netflixIngestName
        preset.useFolderTemplate = true
        preset.folderTemplate = "Shoot/Camera_Media"
        preset.soundFolderTemplate = "Shoot/Sound_Media"

        let config = FanOutCopier.Configuration(
            sources: [cam.path, snd.path],
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "D",
                                             verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)],
            verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: nil,
            organizationPreset: preset,
            sourceMediaKinds: [snd.path: .sound])

        _ = try await FanOutCopier(config: config).run()

        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Shoot/Camera_Media/A001/a.mxf").path),
                      "camera source under Camera_Media")
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("Shoot/Sound_Media/SR001/s.wav").path),
                      "sound source under Sound_Media")
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("Shoot/Camera_Media/SR001").path),
                       "sound must not land under Camera_Media")
    }

    // MARK: - ASC MHL helpers

    /// True if a sealed ASC MHL generation exists in the given ascmhl/ folder.
    private func ascMHLExists(ascmhlDir: URL) -> Bool {
        ASCMHLChain.latestManifestPath(ascmhlDir: ascmhlDir) != nil
    }
    /// Read the latest ASC MHL generation manifest in the given ascmhl/ folder.
    private func readLatestASCMHL(ascmhlDir: URL) throws -> [ASCMHLReader.Entry] {
        let latest = try XCTUnwrap(ASCMHLChain.latestManifestPath(ascmhlDir: ascmhlDir),
                                   "no ASC MHL generation in \(ascmhlDir.path)")
        return try ASCMHLReader.read(url: ascmhlDir.appendingPathComponent(latest))
    }

    // MARK: - Resume skip

    private func resumeConfig(card: URL, dest: URL, forceRecopy: Bool = false) -> FanOutCopier.Configuration {
        FanOutCopier.Configuration(
            sources: [card.path],
            destinations: [
                DestWriter.Config(destPath: dest.path, displayName: "R",
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)
            ],
            verifyMode: .fast, mhlBasePath: nil, dryRun: false,
            progressHandler: nil, forceRecopy: forceRecopy
        )
    }

    func test_resume_recopiesIfDestinationFileWasDeleted() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("CARD3")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("a.bin"))
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("b.bin"))
        let dest = tmpDir.appendingPathComponent("rdest3")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        // Delete one destination file (MHL still lists it).
        try fm.removeItem(at: dest.appendingPathComponent("CARD3/a.bin"))

        let r = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r.first?.filesTransferred, 1, "the deleted file is re-copied")
        XCTAssertEqual(r.first?.filesSkipped, 1, "the present file is skipped")
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("CARD3/a.bin").path))
    }

    func test_forceRecopy_recopiesEverything() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("CARD4")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("a.bin"))
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("b.bin"))
        let dest = tmpDir.appendingPathComponent("rdest4")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        let r = try await FanOutCopier(config: resumeConfig(card: card, dest: dest, forceRecopy: true)).run()
        XCTAssertEqual(r.first?.filesTransferred, 2, "force re-copy ignores the hash list")
        XCTAssertEqual(r.first?.filesSkipped, 0)
    }

    func test_resume_skipsAlreadyBackedUpFiles() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<100_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("a.bin"))
        try Data((0..<120_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("b.bin"))
        let dest = tmpDir.appendingPathComponent("rdest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let r1 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r1.first?.filesTransferred, 2)

        // Add a third file and resume.
        try Data((0..<80_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("c.bin"))
        let r2 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r2.first?.filesTransferred, 1, "only the new file is copied")
        XCTAssertEqual(r2.first?.filesSkipped, 2, "two already-backed-up files skipped")

        for name in ["a.bin", "b.bin", "c.bin"] {
            XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("CARD/\(name)").path), "missing \(name)")
        }
        // The hash list retains all three entries (not truncated on resume).
        // Directory root "CARD": MHL at dest/CARD/ascmhl/<generation>.mhl
        let entries = try readLatestASCMHL(ascmhlDir: dest.appendingPathComponent("CARD/ascmhl"))
        XCTAssertEqual(Set(entries.map { $0.relPath }), ["a.bin", "b.bin", "c.bin"])
        // Carried-forward (seeded) entries must keep their real size, not 0.
        for e in entries {
            XCTAssertGreaterThan(e.size ?? 0, 0, "seeded entry \(e.relPath) lost its size")
        }
    }

    /// A carried-forward entry whose destination file was deleted out-of-band must
    /// NOT stay certified in the regenerated manifest.
    func test_resume_dropsManifestEntryForDeletedDestinationFile() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("DROPCARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<50_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("keep.bin"))
        try Data((0..<60_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("gone.bin"))
        let dest = tmpDir.appendingPathComponent("dropdest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        // Delete one already-backed-up file from the destination, then resume.
        try fm.removeItem(at: dest.appendingPathComponent("DROPCARD/gone.bin"))
        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()

        let entries = try readLatestASCMHL(ascmhlDir: dest.appendingPathComponent("DROPCARD/ascmhl"))
        XCTAssertTrue(entries.contains { $0.relPath == "keep.bin" })
        XCTAssertTrue(entries.contains { $0.relPath == "gone.bin" },
                      "gone.bin is re-copied (present on source), so it is back in the manifest")
        // All manifest entries correspond to files that exist on disk.
        for e in entries {
            XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("DROPCARD/\(e.relPath)").path),
                          "manifest certifies a missing file: \(e.relPath)")
        }
    }

    /// A cancelled run writes its generation manifest but does NOT chain it. Resume
    /// must still find that on-disk (partial) manifest and skip the finalized files.
    func test_resume_findsPartialGenerationWhenChainMissing() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("PARTCARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<90_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("p.bin"))
        try Data((0..<110_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("q.bin"))
        let dest = tmpDir.appendingPathComponent("partdest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        // Simulate a cancelled/partial generation: the manifest exists on disk but
        // the chain file is absent.
        let ascDir = dest.appendingPathComponent("PARTCARD/ascmhl")
        try fm.removeItem(at: ascDir.appendingPathComponent("ascmhl_chain.xml"))
        XCTAssertNil(ASCMHLChain.latestManifestPath(ascmhlDir: ascDir), "chain is gone")
        XCTAssertNotNil(ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir), "manifest still on disk")

        let r2 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r2.first?.filesSkipped, 2, "resume must skip via the on-disk manifest")
        XCTAssertEqual(r2.first?.filesTransferred, 0)
    }

    /// On resume the progress bar spans the WHOLE job: total = all bytes, and the
    /// bar starts at the already-present bytes (e.g. 30/500, not 0/470).
    func test_resume_progressSpansFullJobAndStartsAtPresentBytes() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("SPANCARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        let da = Data((0..<100_000).map { _ in UInt8.random(in: 0...255) })
        let db = Data((0..<120_000).map { _ in UInt8.random(in: 0...255) })
        let dc = Data((0..<140_000).map { _ in UInt8.random(in: 0...255) })
        try da.write(to: card.appendingPathComponent("a.bin"))
        try db.write(to: card.appendingPathComponent("b.bin"))
        try dc.write(to: card.appendingPathComponent("c.bin"))
        let dest = tmpDir.appendingPathComponent("spandest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        try fm.removeItem(at: dest.appendingPathComponent("SPANCARD/a.bin"))  // dest now needs only a

        let lock = NSLock()
        var totals: Set<Int64> = []
        var copyVals: [Int64] = []
        let handler: @Sendable (DestProgress) -> Void = { prog in
            let cf = prog.currentFile
            guard !cf.hasPrefix("Verifying"), !cf.hasPrefix("✓"), !cf.hasPrefix("✗"),
                  !cf.hasPrefix("Cancelled"), prog.bytesTotal > 0 else { return }
            lock.lock(); totals.insert(prog.bytesTotal); copyVals.append(prog.bytesCompleted); lock.unlock()
        }
        var cfg = resumeConfig(card: card, dest: dest)
        cfg.progressHandler = handler
        _ = try await FanOutCopier(config: cfg).run()

        // Sizes on disk are block-allocated, so compare structurally, not to logical
        // byte counts. b and c are still present; a is re-copied.
        let presentLogical = Int64(db.count + dc.count)
        XCTAssertEqual(totals.count, 1, "bar total must be a single, whole-job value")
        let total = totals.first ?? 0
        XCTAssertFalse(copyVals.isEmpty)
        XCTAssertGreaterThanOrEqual(copyVals.min() ?? 0, presentLogical, "bar must start at already-present bytes")
        XCTAssertEqual(copyVals.max(), total, "bar must reach the full job total")
        XCTAssertGreaterThan(total, copyVals.min() ?? total, "bar spans from present up to total")
    }

    /// Per-destination resume: a file missing from ONE destination is re-copied only
    /// there; the destination that still has it skips it.
    func test_resume_perDestination_copiesOnlyWhereMissing() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("PDCARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("a.bin"))
        try Data((0..<90_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("b.bin"))
        let dest1 = tmpDir.appendingPathComponent("pd1")
        let dest2 = tmpDir.appendingPathComponent("pd2")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest2, withIntermediateDirectories: true)

        func cfg() -> FanOutCopier.Configuration {
            FanOutCopier.Configuration(
                sources: [card.path],
                destinations: [
                    DestWriter.Config(destPath: dest1.path, displayName: "D1", verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768),
                    DestWriter.Config(destPath: dest2.path, displayName: "D2", verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)
                ],
                verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        }

        _ = try await FanOutCopier(config: cfg()).run()
        // Remove one file from dest1 only.
        try fm.removeItem(at: dest1.appendingPathComponent("PDCARD/a.bin"))

        let r2 = try await FanOutCopier(config: cfg()).run()
        let d1 = r2.first { $0.destinationPath == dest1.path }
        let d2 = r2.first { $0.destinationPath == dest2.path }
        XCTAssertEqual(d1?.filesTransferred, 1, "dest1 re-copies only the missing file")
        XCTAssertEqual(d1?.filesSkipped, 1, "dest1 skips the file it still has")
        XCTAssertEqual(d2?.filesTransferred, 0, "dest2 has both already")
        XCTAssertEqual(d2?.filesSkipped, 2, "dest2 skips both")
        // The missing file is restored at dest1.
        XCTAssertTrue(fm.fileExists(atPath: dest1.appendingPathComponent("PDCARD/a.bin").path))
    }

    func test_resume_allDone_skipsEverythingAndSucceeds() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("CARD2")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<64_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("x.bin"))
        try Data((0..<64_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("y.bin"))
        let dest = tmpDir.appendingPathComponent("rdest2")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        let r2 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()

        XCTAssertEqual(r2.first?.success, true)
        XCTAssertEqual(r2.first?.filesTransferred, 0, "nothing recopied")
        XCTAssertEqual(r2.first?.filesSkipped, 2, "all files skipped")
    }

    func testResumeSkipWithASCMHL() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("ASCMHL_CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("file1.bin"))
        try Data((0..<80_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("file2.bin"))
        let dest = tmpDir.appendingPathComponent("ascmhl-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let r1 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r1.first?.filesTransferred, 2)

        // ASC MHL must exist at <dest>/ASCMHL_CARD/ascmhl/<generation>.mhl
        let ascmhlDir = dest.appendingPathComponent("ASCMHL_CARD/ascmhl")
        XCTAssertTrue(ascMHLExists(ascmhlDir: ascmhlDir), "ASC MHL missing at \(ascmhlDir.path)")
        let entries = try readLatestASCMHL(ascmhlDir: ascmhlDir)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(Set(entries.map { $0.relPath }), ["file1.bin", "file2.bin"])

        // Second run with same config must skip all files
        let r2 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r2.first?.filesSkipped, 2, "all files should be skipped on second run")
        XCTAssertEqual(r2.first?.filesTransferred, 0, "nothing should be transferred on second run")
    }

    func testResumeSkipLegacyFallback() async throws {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("LEGACY_CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try Data((0..<70_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("alpha.bin"))
        try Data((0..<80_000).map { _ in UInt8.random(in: 0...255) }).write(to: card.appendingPathComponent("beta.bin"))
        let dest = tmpDir.appendingPathComponent("legacy-dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        _ = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()

        // Delete the ASC MHL folder, hand-write a legacy manifest instead
        let ascmhlDir = dest.appendingPathComponent("LEGACY_CARD/ascmhl")
        try fm.removeItem(at: ascmhlDir)

        let legacyDir = dest.appendingPathComponent(".filmcan/hashlists")
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        let legacyMHL = legacyDir.appendingPathComponent("LEGACY_CARD.mhl")
        let legacyXML = """
            <?xml version="1.0" encoding="UTF-8"?>
            <hashlist version="1.0" source="LEGACY_CARD"><file name="alpha.bin"><hash>deadbeef</hash></file><file name="beta.bin"><hash>deadbeef</hash></file></hashlist>
            """
        try legacyXML.write(to: legacyMHL, atomically: true, encoding: .utf8)

        // Second run: legacy fallback should cause both files to be skipped
        let r2 = try await FanOutCopier(config: resumeConfig(card: card, dest: dest)).run()
        XCTAssertEqual(r2.first?.filesSkipped, 2, "legacy fallback: both files should be skipped")
        XCTAssertEqual(r2.first?.filesTransferred, 0, "legacy fallback: nothing should be transferred")
    }

    func test_paranoidVerify_reportsContinuousVerifyBytes() async throws {
        let fm = FileManager.default

        // One large file (32 MiB) so its re-read crosses several report intervals (16 MiB each).
        let sourceURL = tmpDir.appendingPathComponent("big.bin")
        let sourceData = Data((0..<(32 * 1024 * 1024)).map { _ in UInt8.random(in: 0...255) })
        try sourceData.write(to: sourceURL)

        let dest1 = tmpDir.appendingPathComponent("d1")
        try fm.createDirectory(at: dest1, withIntermediateDirectories: true)

        // Capture every emitted verifyBytesCompleted value, in order.
        let emits = VerifyEmitCollector()

        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(destPath: dest1.path, displayName: "D1",
                                  verifyMode: .paranoid, requiresFullFsync: false,
                                  chunkSize: 65536)
            ],
            verifyMode: .paranoid,
            mhlBasePath: tmpDir.path,
            dryRun: false,
            progressHandler: { prog in
                Task { await emits.add(prog.verifyBytesCompleted) }
            }
        )

        let results = try await FanOutCopier(config: config).run()
        XCTAssertTrue(results.allSatisfy { $0.success })

        // Allow the detached emit Tasks to drain.
        try await Task.sleep(for: .milliseconds(200))
        let verify = await emits.verify

        // Distinct increasing verify values BETWEEN 0 and the full file size prove
        // the signal is continuous, not a single whole-file jump.
        let mid = verify.filter { $0 > 0 && $0 < Int64(32 * 1024 * 1024) }
        XCTAssertFalse(mid.isEmpty, "expected sub-file verify progress, got steps: \(Set(verify).sorted())")
        XCTAssertEqual(verify, verify.sorted(), "verify bytes must be monotonic")
    }
}
