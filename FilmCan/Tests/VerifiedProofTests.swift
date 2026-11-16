import XCTest
@testable import FilmCan

/// A destination is "verified", and a card sealed, only when every planned file was
/// compared by hash. Real files in temp folders, no mocks.
final class VerifiedProofTests: XCTestCase {

    private var tmp: URL!
    private var card: URL!
    private var dest: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // realpath: the enumerator reports /private/var paths, not the /var symlink
        // (resolvingSymlinksInPath would strip /private again).
        let raw = fm.temporaryDirectory.appendingPathComponent("proof-\(UUID().uuidString)")
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        tmp = realpath(raw.path, &buffer) != nil ? URL(fileURLWithPath: String(cString: buffer)) : raw
        card = tmp.appendingPathComponent("CARD")
        dest = tmp.appendingPathComponent("dest")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: card.appendingPathComponent("LOCKED").path)
        try? fm.removeItem(at: tmp)
    }

    private func randomData(_ n: Int = 4096) -> Data {
        Data((0..<n).map { _ in UInt8.random(in: 0...255) })
    }

    @discardableResult
    private func addClip(_ name: String, _ data: Data? = nil) throws -> Data {
        let bytes = data ?? randomData()
        try bytes.write(to: card.appendingPathComponent(name))
        return bytes
    }

    private var rollFolder: URL { dest.appendingPathComponent("CARD") }

    private func key(_ name: String) -> String {
        PlannedSourceFile.proofKey(card.appendingPathComponent(name).path)
    }

    private struct Outcome {
        let result: DestResult
        let plan: RunPlan
    }

    private func run(mode: VerifyMode, policy: OrganizationPreset.DuplicatePolicy = .overwrite,
                     style: HashListStyle = .ascMHL,
                     unreadableHandler: (@Sendable ([String]) async -> Bool)? = nil) async throws -> Outcome {
        var cfg = FanOutCopier.Configuration(
            sources: [card.path],
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "D",
                                             verifyMode: mode, requiresFullFsync: false, chunkSize: 32768)],
            verifyMode: mode, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        cfg.duplicatePolicy = policy
        cfg.hashListStyle = style
        cfg.unreadableHandler = unreadableHandler
        let copier = FanOutCopier(config: cfg)
        let results = try await copier.run()
        return Outcome(result: try XCTUnwrap(results.first), plan: await copier.runPlan)
    }

    private func transferResult(_ dr: DestResult) -> TransferResult {
        var r = TransferResult(configurationName: "cfg", destination: dr.destinationPath, startTime: Date())
        r.success = dr.success
        r.destinationResults = [dr]
        return r
    }

    private func sealable(_ o: Outcome) -> Bool {
        CardSealService.shouldSeal(plannedDestinations: [o.result.destinationPath],
                                   results: [transferResult(o.result)], plan: o.plan)
    }

    private func manifestNames() -> [String] {
        FanOutCopier.loadExistingMHLEntries(destPath: dest.path, rootName: "CARD",
                                            rollFolder: rollFolder.path).map(\.fileName)
    }

    // MARK: 1. Verification Off is not proof

    func test_offRun_provesNothing_andWritesTheLedger() async throws {
        try addClip("a.bin"); try addClip("b.bin")
        let off = try await run(mode: .off)
        XCTAssertTrue(off.result.success)
        XCTAssertTrue(off.result.verifiedSourcePaths.isEmpty)
        XCTAssertFalse(sealable(off))
        let ledger = UnverifiedLedger.load(rollFolder: rollFolder.path)
        XCTAssertTrue(ledger.contains("a.bin"))
        XCTAssertTrue(ledger.contains("b.bin"))
    }

    /// Off, then Fast: the manifest lists both files but no one compared them. The
    /// Fast run must look at them — a same-size corrupted copy is recopied, never
    /// skipped and sealed on the manifest's word.
    func test_offThenFast_corruptedSameSizeFileIsRecopied_andProofCoversEverything() async throws {
        let a = try addClip("a.bin"); try addClip("b.bin")
        _ = try await run(mode: .off)

        var rotten = a; rotten[0] ^= 0xFF
        try rotten.write(to: rollFolder.appendingPathComponent("a.bin"))

        let fast = try await run(mode: .fast)
        XCTAssertTrue(fast.result.success)
        XCTAssertEqual(fast.result.filesTransferred, 1, "only the corrupted file is recopied")
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("a.bin")), a)
        XCTAssertEqual(fast.result.verifiedSourcePaths, [key("a.bin"), key("b.bin")])
        XCTAssertTrue(sealable(fast))
        XCTAssertTrue(UnverifiedLedger.load(rollFolder: rollFolder.path).isEmpty,
                      "nothing is unverified any more")
    }

    /// Off, then Fast with nothing damaged: skipped files are re-hashed, not recopied.
    func test_offThenFast_untouchedFilesAreRehashedNotRecopied() async throws {
        try addClip("a.bin"); try addClip("b.bin")
        _ = try await run(mode: .off)
        let fast = try await run(mode: .fast)
        XCTAssertEqual(fast.result.filesTransferred, 0)
        XCTAssertEqual(fast.result.filesSkipped, 2)
        XCTAssertEqual(fast.result.verifiedSourcePaths, [key("a.bin"), key("b.bin")])
        XCTAssertTrue(sealable(fast))
    }

    /// A run that never checked stays unsealable even when it only skips.
    func test_offThenOff_neverSeals() async throws {
        try addClip("a.bin")
        _ = try await run(mode: .off)
        let again = try await run(mode: .off)
        XCTAssertFalse(sealable(again))
    }

    /// A checked run followed by another: skipped files stay proven without a re-hash.
    func test_fastThenFast_skipsAreProven_withoutLedger() async throws {
        try addClip("a.bin"); try addClip("b.bin")
        let first = try await run(mode: .fast)
        XCTAssertTrue(sealable(first))
        let second = try await run(mode: .fast)
        XCTAssertEqual(second.result.filesTransferred, 0)
        XCTAssertEqual(second.result.verifiedSourcePaths.count, 2)
        XCTAssertTrue(sealable(second))
        XCTAssertFalse(fm.fileExists(atPath: UnverifiedLedger.url(rollFolder: rollFolder.path).path))
    }

    // MARK: 2. Skip policy compares hashes

    func test_skip_homonymWithDifferentContent_isAConflict_notASuccess() async throws {
        try addClip("clip.mov")
        let existing = Data(repeating: 0x77, count: 99)
        try fm.createDirectory(at: rollFolder, withIntermediateDirectories: true)
        try existing.write(to: rollFolder.appendingPathComponent("clip.mov"))

        let o = try await run(mode: .fast, policy: .skip)

        XCTAssertFalse(o.result.success)
        XCTAssertEqual(o.result.failureReason, .conflict)
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("clip.mov")), existing,
                       "the existing file is left alone")
        XCTAssertFalse(manifestNames().contains("clip.mov"))
        XCTAssertFalse(o.result.verifiedSourcePaths.contains(key("clip.mov")))
        XCTAssertFalse(sealable(o))
    }

    func test_skip_identicalHomonym_isInscribedInTheManifest() async throws {
        let bytes = try addClip("clip.mov")
        try fm.createDirectory(at: rollFolder, withIntermediateDirectories: true)
        try bytes.write(to: rollFolder.appendingPathComponent("clip.mov"))

        let o = try await run(mode: .fast, policy: .skip)

        XCTAssertTrue(o.result.success)
        XCTAssertTrue(manifestNames().contains("clip.mov"))
        XCTAssertEqual(o.result.verifiedSourcePaths, [key("clip.mov")])
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("clip.mov")), bytes)
        XCTAssertTrue(sealable(o))
    }

    /// A conflict on one file does not stop the other files from being copied.
    func test_skip_conflictOnOneFile_stillCopiesTheOthers() async throws {
        try addClip("a.bin"); let b = try addClip("b.bin")
        try fm.createDirectory(at: rollFolder, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 10).write(to: rollFolder.appendingPathComponent("a.bin"))

        let o = try await run(mode: .fast, policy: .skip)
        XCTAssertFalse(o.result.success)
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("b.bin")), b)
        XCTAssertTrue(o.result.verifiedSourcePaths.contains(key("b.bin")))
        XCTAssertFalse(o.result.verifiedSourcePaths.contains(key("a.bin")))
    }

    // MARK: 3. Resume checks the destination file

    func test_resume_zeroByteDestinationFileIsRecopied() async throws {
        let a = try addClip("a.bin"); try addClip("b.bin")
        _ = try await run(mode: .fast)
        try Data().write(to: rollFolder.appendingPathComponent("a.bin"))

        let again = try await run(mode: .fast)

        XCTAssertTrue(again.result.success)
        XCTAssertEqual(again.result.filesTransferred, 1)
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("a.bin")), a)
        XCTAssertEqual(again.result.verifiedSourcePaths.count, 2)
    }

    /// The simple hash list records no size: only the destination file's own length
    /// can tell a truncated copy from a good one.
    func test_resume_simpleHashList_truncatedDestinationFileIsRecopied() async throws {
        let a = try addClip("a.bin")
        _ = try await run(mode: .fast, style: .simpleHidden)
        try a.prefix(10).write(to: rollFolder.appendingPathComponent("a.bin"))

        let again = try await run(mode: .fast, style: .simpleHidden)

        XCTAssertEqual(again.result.filesTransferred, 1)
        XCTAssertEqual(try Data(contentsOf: rollFolder.appendingPathComponent("a.bin")), a)
    }

    // MARK: 4. The plan is what was enumerated

    func test_plan_listsEveryEnumeratedFile() async throws {
        try addClip("a.bin", randomData(100)); try addClip("sub-b.bin", randomData(200))
        let o = try await run(mode: .fast)
        XCTAssertEqual(Set(o.plan.files.map(\.relPath)), ["a.bin", "sub-b.bin"])
        XCTAssertEqual(o.plan.files.first(where: { $0.relPath == "a.bin" })?.size, 100)
        XCTAssertTrue(o.plan.files.allSatisfy { $0.modified > 0 && $0.rootPath == card.path })
        XCTAssertTrue(o.plan.ignoredUnreadable.isEmpty)
    }

    func test_ignoredUnreadableFolder_isRecordedAndPreventsSeal() async throws {
        try addClip("a.bin")
        let locked = card.appendingPathComponent("LOCKED")
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        try addClip("LOCKED/secret.bin")
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        guard !fm.isReadableFile(atPath: locked.path) else {
            throw XCTSkip("permissions are not enforced for this user")
        }

        let o = try await run(mode: .fast, unreadableHandler: { _ in true })

        XCTAssertTrue(o.result.success)
        XCTAssertEqual(o.plan.ignoredUnreadable.map { ($0 as NSString).lastPathComponent }, ["LOCKED"])
        XCTAssertFalse(sealable(o), "a card with ignored folders is never sealed")
    }

    // MARK: 7. Catalog follows the same proof

    @MainActor
    func test_catalog_verifiedFollowsPerFileProof_andUsesEffectiveKinds() async throws {
        try addClip("a.bin"); try addClip("b.bin")
        let off = try await run(mode: .off)

        let now = Date()
        func record(_ o: Outcome, into store: MediaCatalogStore, kinds: [String: SourceMediaKind]?) async {
            var fanOut = TransferResult(configurationName: "Proj", destination: dest.path,
                                        startTime: now, endTime: now, success: true)
            fanOut.destinationResults = [o.result]
            let exploded = TransferViewModel().explodeFanOutResult(fanOut, configName: "Proj")
            var config = BackupConfiguration()
            config.name = "Proj"
            await store.record(config: config, sources: [card.path], results: exploded, runDate: now,
                               plan: o.plan, mediaKinds: kinds)
        }

        let offStore = MediaCatalogStore(fileURL: tmp.appendingPathComponent("off.json"))
        await record(off, into: offStore, kinds: nil)
        XCTAssertEqual(offStore.rolls.first?.copies.first?.verified, false)

        try fm.removeItem(at: rollFolder)
        let fast = try await run(mode: .fast)
        let fastStore = MediaCatalogStore(fileURL: tmp.appendingPathComponent("fast.json"))
        await record(fast, into: fastStore, kinds: [card.path: .sound])
        XCTAssertEqual(fastStore.rolls.first?.copies.first?.verified, true)
        XCTAssertEqual(fastStore.rolls.first?.mediaKind, .sound,
                       "the run's effective kind (auto-detected sound), not the config's default")
    }
}
