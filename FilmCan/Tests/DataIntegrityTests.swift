import XCTest
@testable import FilmCan

// MARK: - Harness

struct DataIntegrityHarness {
    struct Result {
        let success: Bool
        let filesTransferred: Int
    }

    static func run(
        sources: [String],
        dest: String,
        reVerify: Bool = false,
        policy: OrganizationPreset.DuplicatePolicy = .overwrite,
        forceVerifyHashNil: Bool = false
    ) async throws -> Result {
        var config = FanOutCopier.Configuration(
            sources: sources,
            destinations: [
                DestWriter.Config(
                    destPath: dest,
                    displayName: "Test",
                    verifyMode: .paranoid,
                    requiresFullFsync: false,
                    chunkSize: nil
                )
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )
        config.reVerifyExistingOnResume = reVerify
        config.duplicatePolicy = policy
        config._testForceDestReadHashNil = forceVerifyHashNil

        let copier = FanOutCopier(config: config)
        let results = try await copier.run()
        let success = results.allSatisfy { $0.success }
        let transferred = results.reduce(0) { $0 + $1.filesTransferred }
        return Result(success: success, filesTransferred: transferred)
    }
}

// MARK: - Tests

final class DataIntegrityTests: XCTestCase {

    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Task 1: mtime round-trip

    func test_ascMHL_roundTripsMtime() async throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ascDir = dir.appendingPathComponent("ascmhl")
        let writer = try ASCMHLWriter(ascmhlDir: ascDir, rollName: "A001")
        try await writer.append(relPath: "A001/clip.mov", size: 1234, hash: "deadbeef", mtime: 1_700_000_000)
        try await writer.seal()

        guard let latest = ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir) else {
            return XCTFail("no manifest written")
        }
        let entries = try ASCMHLReader.read(url: ascDir.appendingPathComponent(latest))
        XCTAssertEqual(entries.first?.mtime, 1_700_000_000)
    }

    // MARK: Task 2: resume gate validates size+mtime

    func test_resume_recopiesWhenSourceModifiedSameName() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let clip = card.appendingPathComponent("clip.mov")
        try Data(repeating: 0xAB, count: 4096).write(to: clip)

        _ = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path)

        // Modify source: different size + mtime
        try Data(repeating: 0xCD, count: 8192).write(to: clip)

        let result = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path)
        XCTAssertGreaterThanOrEqual(result.filesTransferred, 1,
            "modified source must be recopied, not skipped")

        let copied = try Data(contentsOf: dst.appendingPathComponent("A001/clip.mov"))
        XCTAssertEqual(copied.count, 8192, "destination must hold the updated content")
    }

    func test_resume_reVerify_recopiesWhenContentDiffersButSizeMtimeSame() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let clip = card.appendingPathComponent("clip.mov")
        try Data(repeating: 0xAB, count: 4096).write(to: clip)
        let attrs = try FileManager.default.attributesOfItem(atPath: clip.path)
        let savedDate = attrs[.modificationDate] as! Date

        _ = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path, reVerify: true)

        // Same size, restore mtime, but different bytes
        try Data(repeating: 0xCD, count: 4096).write(to: clip)
        try FileManager.default.setAttributes([.modificationDate: savedDate], ofItemAtPath: clip.path)

        let result = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path, reVerify: true)
        XCTAssertGreaterThanOrEqual(result.filesTransferred, 1,
            "re-verify must catch same-size same-mtime content change")
    }

    // MARK: Task 4: ConflictScanner

    func test_conflictScanner_flagsUnmanifestedExistingFile() throws {
        let dst = tempDir()
        defer { try? FileManager.default.removeItem(at: dst) }
        let existing = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 16).write(to: existing)

        let conflicts = ConflictScanner.scan(
            plannedTargets: [ConflictScanner.Target(
                destPath: dst.path, rootName: "A001",
                fileName: "A001/clip.mov", resolvedPath: existing.path)],
            manifestedRelPathsByDestRoot: ["\(dst.path)\0A001": Set<String>()]
        )
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts.first?.resolvedPath, existing.path)
    }

    func test_conflictScanner_ignoresManifestedFile() throws {
        let dst = tempDir()
        defer { try? FileManager.default.removeItem(at: dst) }
        let existing = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 16).write(to: existing)

        let conflicts = ConflictScanner.scan(
            plannedTargets: [ConflictScanner.Target(
                destPath: dst.path, rootName: "A001",
                fileName: "A001/clip.mov", resolvedPath: existing.path)],
            manifestedRelPathsByDestRoot: ["\(dst.path)\0A001": Set(["A001/clip.mov"])]
        )
        XCTAssertTrue(conflicts.isEmpty)
    }

    // MARK: Task 5: finalize honors conflict directive

    func test_skipPolicy_doesNotOverwriteUnmanifestedFile() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 32).write(to: card.appendingPathComponent("clip.mov"))

        // Pre-place a DIFFERENT, unmanifested file at the target
        let target = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let original = Data(repeating: 0x77, count: 99)
        try original.write(to: target)

        _ = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path, policy: .skip)

        let after = try Data(contentsOf: target)
        XCTAssertEqual(after, original,
            "skip policy must leave the existing unmanifested file untouched")
    }

    func test_overwritePolicy_replacesUnmanifestedFile() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data(repeating: 0x22, count: 32).write(to: card.appendingPathComponent("clip.mov"))

        let target = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x77, count: 99).write(to: target)

        _ = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path, policy: .overwrite)

        let after = try Data(contentsOf: target)
        XCTAssertEqual(after.count, 32,
            "overwrite policy must replace the file with the new content")
    }

    // MARK: Task 6: MHL only after verify; nil-hash deletes file

    func test_paranoidVerify_nilHash_deletesFileAndWritesNoEntry() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        let clip = card.appendingPathComponent("clip.mov")
        try Data(repeating: 0x5A, count: 4096).write(to: clip)

        let result = try await DataIntegrityHarness.run(
            sources: [card.path], dest: dst.path, forceVerifyHashNil: true)

        XCTAssertFalse(result.success, "nil verify hash must fail the destination")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: dst.appendingPathComponent("A001/clip.mov").path),
            "a file that failed verification with nil hash must be deleted")

        let ascDir = dst.appendingPathComponent("A001/ascmhl")
        if let latest = ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir),
           let entries = try? ASCMHLReader.read(url: ascDir.appendingPathComponent(latest)) {
            XCTAssertFalse(entries.contains { $0.relPath.hasSuffix("clip.mov") },
                "no manifest entry for an unverified file")
        }
    }

    func test_manifestNotTrustedWhenWrittenBeforeVerify() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 4096).write(to: card.appendingPathComponent("clip.mov"))

        _ = try? await DataIntegrityHarness.run(
            sources: [card.path], dest: dst.path, forceVerifyHashNil: true)
        let result = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path)
        XCTAssertGreaterThanOrEqual(result.filesTransferred, 1,
            "unverified file must not be trusted on resume")
    }

    // MARK: Task 7: duplicate source basenames auto-disambiguate (no merge)

    func test_twoSourcesSameBasename_autoDisambiguates() async throws {
        let srcA = tempDir(); let srcB = tempDir(); let dst = tempDir()
        defer { [srcA, srcB, dst].forEach { try? FileManager.default.removeItem(at: $0) } }
        for base in [srcA, srcB] {
            let card = base.appendingPathComponent("A001")
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try Data(repeating: 0x01, count: 16).write(to: card.appendingPathComponent("clip.mov"))
        }
        let result = try await DataIntegrityHarness.run(
            sources: [srcA.appendingPathComponent("A001").path,
                      srcB.appendingPathComponent("A001").path],
            dest: dst.path)
        XCTAssertTrue(result.success, "two same-named cards copy successfully")

        let fm = FileManager.default
        // Both cards land in DISTINCT roll folders (A001 + A001-2), each with its files
        // and its own ascmhl/ — never merged. (Which card gets which suffix depends on
        // sorted source path, so assert on the set, not a fixed mapping.)
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("A001/clip.mov").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("A001-2/clip.mov").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("A001/ascmhl").path))
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("A001-2/ascmhl").path))
    }

    // MARK: P0 Bug 3.2 — increment policy must not clobber original via paranoid verify

    func test_incrementPolicy_paranoidVerify_doesNotDeleteOriginalFile() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        // Source card
        let card = src.appendingPathComponent("A001")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try Data("source content".utf8).write(to: card.appendingPathComponent("clip.mov"))

        // Pre-existing unmanifested file at destination — same relative path, different content
        let target = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let originalData = Data("old content".utf8)
        try originalData.write(to: target)

        // DataIntegrityHarness.run(sources:dest:policy:) sets config.duplicatePolicy = policy
        _ = try await DataIntegrityHarness.run(sources: [card.path], dest: dst.path, policy: .increment)

        // Original must be untouched
        let afterOriginal = try Data(contentsOf: target)
        XCTAssertEqual(afterOriginal, originalData,
                       "increment mode must not delete or modify the pre-existing file")

        // Suffix template "_001" inserts before extension: clip.mov → clip_001.mov
        let suffixed = dst.appendingPathComponent("A001/clip_001.mov")
        XCTAssertTrue(FileManager.default.fileExists(atPath: suffixed.path),
                      "new suffixed file must exist at A001/clip_001.mov")
        XCTAssertEqual(try String(data: Data(contentsOf: suffixed), encoding: .utf8), "source content")
    }

    // MARK: Task 8: distinct roots do not share manifest entries

    func test_distinctRoots_doNotShareManifestEntries() async throws {
        let src = tempDir(); let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        for name in ["A001", "B001"] {
            let card = src.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
            try Data(repeating: 0x01, count: 16).write(to: card.appendingPathComponent("\(name).mov"))
        }
        _ = try await DataIntegrityHarness.run(
            sources: [src.appendingPathComponent("A001").path,
                      src.appendingPathComponent("B001").path],
            dest: dst.path)
        for name in ["A001", "B001"] {
            let ascDir = dst.appendingPathComponent("\(name)/ascmhl")
            guard let latest = ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir) else {
                XCTFail("\(name): no manifest"); continue
            }
            let entries = try ASCMHLReader.read(url: ascDir.appendingPathComponent(latest))
            XCTAssertTrue(entries.allSatisfy { $0.relPath.contains(name) },
                "\(name) manifest leaked foreign entries")
        }
    }
}
