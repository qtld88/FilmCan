import XCTest
@testable import FilmCan

/// A file never lands under its final name when incomplete, and a verification
/// that could not be performed is a failure, never a success.
/// Real temp dirs; faults are injected through the DEBUG seams of
/// `FanOutCopier.Configuration` (`_testSourceReadFailsFileNames`,
/// `_testNilSourceRereadFileNames`, `_testCorruptSourceRereadFileNames`).
final class FanOutCopierReadFailureTests: XCTestCase {

    var tmpDir: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        tmpDir = fm.temporaryDirectory
            .appendingPathComponent("fanout-readfail-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir { try? fm.removeItem(at: tmpDir) }
    }

    // MARK: - Helpers

    private func randomData(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, $0.count) }
        return Data(bytes)
    }

    private func makeDir(_ name: String) throws -> URL {
        let u = tmpDir.appendingPathComponent(name)
        try fm.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func config(sources: [String], dests: [URL],
                        verify: VerifyMode = .paranoid) -> FanOutCopier.Configuration {
        FanOutCopier.Configuration(
            sources: sources,
            destinations: dests.map {
                DestWriter.Config(destPath: $0.path, displayName: $0.lastPathComponent,
                                  verifyMode: verify, requiresFullFsync: false, chunkSize: nil)
            },
            verifyMode: verify,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )
    }

    /// Every `.filmcan-*` temp under `root`, recursively.
    private func tempFiles(under root: URL) -> [String] {
        let e = fm.enumerator(atPath: root.path)
        var out: [String] = []
        while let p = e?.nextObject() as? String {
            if (p as NSString).lastPathComponent.hasPrefix(".filmcan-") { out.append(p) }
        }
        return out
    }

    // MARK: - 1. Source read fails mid-file

    func test_sourceReadFailsMidFile_noFinalFileNoTemp_perDestFailure_otherFilesCopied() async throws {
        let card = try makeDir("A001")
        // Larger than the biggest chunk (16 MiB) so the first chunk is a strict prefix.
        try randomData(40 * 1024 * 1024).write(to: card.appendingPathComponent("broken.mov"))
        try randomData(256 * 1024).write(to: card.appendingPathComponent("good.mov"))
        let d1 = try makeDir("d1"), d2 = try makeDir("d2")

        var cfg = config(sources: [card.path], dests: [d1, d2])
        cfg._testSourceReadFailsFileNames = ["broken.mov"]

        // A read error on one file is a failure for that file, not a run-level throw.
        let results = try await FanOutCopier(config: cfg).run()

        XCTAssertEqual(results.count, 2, "one result per destination")
        for d in [d1, d2] {
            XCTAssertFalse(fm.fileExists(atPath: d.appendingPathComponent("A001/broken.mov").path),
                           "a truncated file must never be renamed to its final name (\(d.lastPathComponent))")
            XCTAssertTrue(fm.fileExists(atPath: d.appendingPathComponent("A001/good.mov").path),
                          "other files of the run still copy (\(d.lastPathComponent))")
            XCTAssertEqual(tempFiles(under: d), [], "no temp file may remain (\(d.lastPathComponent))")
            let r = try XCTUnwrap(results.first { $0.destinationPath == d.path })
            XCTAssertFalse(r.success, "a destination that missed a file is not a success")
            XCTAssertEqual(r.filesTransferred, 1, "only good.mov was transferred")
        }
    }

    // MARK: - 1b. finalize refuses a size mismatch

    func test_destWriterFinalize_refusesWhenBytesWrittenDifferFromExpected() async throws {
        let dir = try makeDir("w")
        let target = dir.appendingPathComponent("clip.mov")
        let writer = try await DestWriter(destPath: target.path, displayName: "w",
                                          verifyMode: .paranoid, requiresFullFsync: false,
                                          sharedMHLWriter: nil)
        try await writer.write(data: Data(repeating: 0xAB, count: 3))
        do {
            _ = try await writer.finalize(fileHash: "", sourceSize: 10)
            XCTFail("finalize must refuse 3 bytes written for 10 expected")
        } catch {}
        XCTAssertFalse(fm.fileExists(atPath: target.path), "no final file on size mismatch")
        XCTAssertEqual(tempFiles(under: dir), [], "temp removed on size mismatch")
    }

    // MARK: - 1c. a failed rename leaves no temp behind

    func test_destWriterFinalize_renameFailure_leavesNoTempFile() async throws {
        let dir = try makeDir("w2")
        // The final name is taken by a non-empty folder: rename(2) of a file onto it fails.
        let target = dir.appendingPathComponent("clip.mov")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data([0x01]).write(to: target.appendingPathComponent("inside.txt"))
        let writer = try await DestWriter(destPath: target.path, displayName: "w",
                                          verifyMode: .paranoid, requiresFullFsync: false,
                                          sharedMHLWriter: nil)
        try await writer.write(data: Data(repeating: 0xAB, count: 3))
        do {
            _ = try await writer.finalize(fileHash: "", sourceSize: 3)
            XCTFail("finalize must throw when the rename fails")
        } catch {}
        XCTAssertEqual(tempFiles(under: dir), [], "the temp is removed when the rename fails")
    }

    // MARK: - 2. Paranoid source re-read that yields nothing

    func test_paranoid_sourceRereadNil_isVerifyFailure() async throws {
        let card = try makeDir("A001")
        try randomData(128 * 1024).write(to: card.appendingPathComponent("clip.mov"))
        let d = try makeDir("d")

        var cfg = config(sources: [card.path], dests: [d])
        cfg._testNilSourceRereadFileNames = ["clip.mov"]

        let results = try await FanOutCopier(config: cfg).run()

        let r = try XCTUnwrap(results.first)
        XCTAssertFalse(r.success, "an impossible source re-read must fail verification")
        XCTAssertEqual(r.failureReason, .verify)
        XCTAssertFalse(fm.fileExists(atPath: d.appendingPathComponent("A001/clip.mov").path),
                       "the unverified copy is removed so the manifest and resume never trust it")
    }

    /// A real mid-file read error (EISDIR on a directory) must surface as an
    /// error, not be mistaken for end-of-file and hashed as an empty file.
    func test_rereadHashDetached_readError_throws() async throws {
        let dir = try makeDir("not-a-file")
        do {
            let h = try await FanOutCopier.rereadHashDetached(url: dir, chunkSz: 64 * 1024)
            XCTFail("a read error must throw, got hash \(String(describing: h))")
        } catch {}
    }

    // MARK: - 3. Source corruption never deletes a file this run did not write

    func test_sourceCorruption_keepsPreexistingSkippedFile() async throws {
        let card = try makeDir("A001")
        try randomData(64 * 1024).write(to: card.appendingPathComponent("clip.mov"))
        let d = try makeDir("d")
        // Unmanifested file already at the target; the Skip policy keeps it.
        let target = d.appendingPathComponent("A001/clip.mov")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(repeating: 0x77, count: 99)
        try original.write(to: target)

        var cfg = config(sources: [card.path], dests: [d])
        cfg.duplicatePolicy = .skip
        cfg._testCorruptSourceRereadFileNames = ["clip.mov"]

        do { _ = try await FanOutCopier(config: cfg).run() } catch {}

        XCTAssertTrue(fm.fileExists(atPath: target.path), "a skipped pre-existing file is not ours to delete")
        XCTAssertEqual(try? Data(contentsOf: target), original)
    }

    /// Skip + an IDENTICAL pre-existing file: the engine adopts it (counted as
    /// transferred) but did not write it, so source corruption must not delete it.
    func test_sourceCorruption_keepsPreexistingIdenticalAdoptedFile() async throws {
        let card = try makeDir("A001")
        let content = randomData(64 * 1024)
        try content.write(to: card.appendingPathComponent("clip.mov"))
        let d = try makeDir("d")
        let target = d.appendingPathComponent("A001/clip.mov")
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: target)

        var cfg = config(sources: [card.path], dests: [d])
        cfg.duplicatePolicy = .skip
        cfg._testCorruptSourceRereadFileNames = ["clip.mov"]

        do {
            _ = try await FanOutCopier(config: cfg).run()
            XCTFail("source corruption still aborts the run")
        } catch FanOutCopier.Error.sourceCorruption {}

        XCTAssertEqual(try? Data(contentsOf: target), content,
                       "an adopted pre-existing file was not written by this run: never delete it")
    }

    // MARK: - 4. Manifests are finalized on every exit of run()

    func test_sourceCorruption_throws_butManifestFinalizedAsPartial() async throws {
        let card = try makeDir("A001")
        try randomData(64 * 1024).write(to: card.appendingPathComponent("good.mov"))
        try randomData(64 * 1024).write(to: card.appendingPathComponent("bad.mov"))
        let d = try makeDir("d")

        var cfg = config(sources: [card.path], dests: [d])
        cfg._testCorruptSourceRereadFileNames = ["bad.mov"]

        do {
            _ = try await FanOutCopier(config: cfg).run()
            XCTFail("source corruption still aborts the run")
        } catch let FanOutCopier.Error.sourceCorruption(path) {
            XCTAssertTrue(path.hasSuffix("bad.mov"))
        }

        let ascDir = d.appendingPathComponent("A001/ascmhl")
        let latest = try XCTUnwrap(ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir),
                                   "the verified file's manifest must be written, not lost")
        let xml = try String(contentsOf: ascDir.appendingPathComponent(latest), encoding: .utf8)
        XCTAssertTrue(xml.contains("filmcan:partial"), "an aborted run writes a PARTIAL manifest")
        XCTAssertTrue(xml.contains("good.mov"))
        XCTAssertFalse(xml.contains("bad.mov"))
        XCTAssertTrue(ASCMHLChain.read(ascmhlDir: ascDir).isEmpty,
                      "a partial generation is never recorded in the chain")
    }
}
