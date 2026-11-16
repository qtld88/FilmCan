import XCTest
@testable import FilmCan

/// FilmCan never overwrites a destination file the user has not seen and accepted.
/// Real files in temp folders, no mocks.
final class OverwriteSafetyTests: XCTestCase {

    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // realpath: the enumerator reports /private/var paths, not the /var symlink.
        let raw = fm.temporaryDirectory.appendingPathComponent("overwrite-\(UUID().uuidString)")
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        tmp = realpath(raw.path, &buffer) != nil ? URL(fileURLWithPath: String(cString: buffer)) : raw
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func randomData(_ n: Int) -> Data {
        Data((0..<n).map { _ in UInt8.random(in: 0...255) })
    }

    private func dir(_ rel: String) throws -> URL {
        let url = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ data: Data, _ url: URL) throws -> Data {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return data
    }

    private func destConfig(_ url: URL, _ mode: VerifyMode = .fast) -> DestWriter.Config {
        DestWriter.Config(destPath: url.path, displayName: url.lastPathComponent,
                          verifyMode: mode, requiresFullFsync: false, chunkSize: 32768)
    }

    private func config(sources: [URL], dests: [URL], mode: VerifyMode = .fast) -> FanOutCopier.Configuration {
        FanOutCopier.Configuration(
            sources: sources.map(\.path), destinations: dests.map { destConfig($0, mode) },
            verifyMode: mode, mhlBasePath: nil, dryRun: false, progressHandler: nil)
    }

    /// Collects what the resolver was shown, across the @Sendable boundary.
    private actor Seen {
        var conflicts: [[ConflictScanner.Conflict]] = []
        var prompts: [DuplicatePrompt] = []
        func add(_ c: [ConflictScanner.Conflict]) { conflicts.append(c) }
        func add(_ p: DuplicatePrompt) { prompts.append(p) }
    }

    // MARK: 1. Reused card: a manifested file whose source changed is a conflict

    /// Card emptied without formatting and reused: C0001.MP4 comes back with other
    /// content and another size. The old clip is in the manifest; it must not be
    /// rewritten until the user has said so.
    private func reusedCard(style: HashListStyle = .ascMHL) async throws -> (card: URL, dest: URL, old: Data, new: Data) {
        let card = try dir("CARD")
        let dest = try dir("dest")
        let old = try write(randomData(4096), card.appendingPathComponent("C0001.MP4"))
        var cfg = config(sources: [card], dests: [dest])
        cfg.hashListStyle = style
        let first = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(first.first?.success, true)
        let new = try write(randomData(8192), card.appendingPathComponent("C0001.MP4"))
        return (card, dest, old, new)
    }

    func test_reusedCard_changedManifestedClip_isShownAndKeptUntilConfirmed() async throws {
        let (card, dest, old, _) = try await reusedCard()
        let seen = Seen()
        var cfg = config(sources: [card], dests: [dest])
        cfg.hashListStyle = .ascMHL
        cfg.duplicatePolicy = .ask
        cfg.duplicateResolver = { conflicts in
            await seen.add(conflicts)
            return [:]   // the user closed the prompt without accepting anything
        }
        let results = try await FanOutCopier(config: cfg).run()

        let shown = await seen.conflicts
        XCTAssertEqual(shown.count, 1, "the user is asked once")
        XCTAssertEqual(shown.first?.map(\.fileName), ["C0001.MP4"])
        XCTAssertEqual(shown.first?.first?.kind, .differsFromManifest)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD/C0001.MP4")), old,
                       "the backed-up clip survives")
        XCTAssertEqual(results.first?.success, false)
        XCTAssertEqual(results.first?.failureReason, .conflict)
    }

    func test_reusedCard_askWithoutResolver_neverOverwrites() async throws {
        let (card, dest, old, _) = try await reusedCard()
        var cfg = config(sources: [card], dests: [dest])
        cfg.duplicatePolicy = .ask
        _ = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD/C0001.MP4")), old)
    }

    func test_reusedCard_userAcceptsOverwrite_replacesTheClip() async throws {
        let (card, dest, _, new) = try await reusedCard()
        var cfg = config(sources: [card], dests: [dest])
        cfg.duplicatePolicy = .ask
        cfg.duplicateResolver = { conflicts in
            Dictionary(uniqueKeysWithValues: conflicts.map {
                ($0.resolvedPath, FanOutCopier.ConflictDecision(policy: .overwrite))
            })
        }
        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.first?.success, true)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD/C0001.MP4")), new)
    }

    /// The simple hash list records no size: the destination file is hashed. It
    /// matches the manifest, so it is the backed-up clip, not a damaged copy.
    func test_reusedCard_simpleHashList_changedClipIsAConflict() async throws {
        let (card, dest, old, _) = try await reusedCard(style: .simpleHidden)
        let seen = Seen()
        var cfg = config(sources: [card], dests: [dest])
        cfg.hashListStyle = .simpleHidden
        cfg.duplicatePolicy = .ask
        cfg.duplicateResolver = { conflicts in await seen.add(conflicts); return [:] }
        _ = try await FanOutCopier(config: cfg).run()
        let shown = await seen.conflicts
        XCTAssertEqual(shown.first?.first?.kind, .differsFromManifest)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD/C0001.MP4")), old)
    }

    /// A damaged copy (truncated at the destination, source unchanged) is still
    /// recopied silently: the source matches the manifest, nothing of value is lost.
    func test_truncatedCopy_sourceUnchanged_isRecopiedWithoutPrompt() async throws {
        let card = try dir("CARD")
        let dest = try dir("dest")
        let clip = try write(randomData(4096), card.appendingPathComponent("C0001.MP4"))
        _ = try await FanOutCopier(config: config(sources: [card], dests: [dest])).run()
        try Data().write(to: dest.appendingPathComponent("CARD/C0001.MP4"))

        let seen = Seen()
        var cfg = config(sources: [card], dests: [dest])
        cfg.duplicatePolicy = .ask
        cfg.duplicateResolver = { conflicts in await seen.add(conflicts); return [:] }
        let results = try await FanOutCopier(config: cfg).run()
        let shown = await seen.conflicts
        XCTAssertTrue(shown.isEmpty)
        XCTAssertEqual(results.first?.success, true)
        XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("CARD/C0001.MP4")), clip)
    }

    // MARK: 2. Two planned files, one target path

    private func assertDuplicateTargets(_ cfg: FanOutCopier.Configuration,
                                        file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await FanOutCopier(config: cfg).run()
            XCTFail("expected duplicateTargetPaths", file: file, line: line)
        } catch FanOutCopier.Error.duplicateTargetPaths(let names) {
            XCTAssertFalse(names.isEmpty, file: file, line: line)
        } catch {
            XCTFail("unexpected error \(error)", file: file, line: line)
        }
    }

    func test_twoSourcesInContentsMode_sharingARelativePath_areRefusedBeforeAnyWrite() async throws {
        let s1 = try dir("S1"), s2 = try dir("S2")
        let dest = try dir("dest")
        try write(randomData(4096), s1.appendingPathComponent("CLIP/A001.MOV"))
        try write(randomData(4096), s2.appendingPathComponent("CLIP/A001.MOV"))
        try write(randomData(4096), s2.appendingPathComponent("CLIP/A002.MOV"))
        var cfg = config(sources: [s1, s2], dests: [dest])
        cfg.copyFolderContents = true
        await assertDuplicateTargets(cfg)
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("CLIP/A001.MOV").path))
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("CLIP/A002.MOV").path),
                       "nothing is copied at all")
    }

    func test_twoLooseFilesWithTheSameName_areRefused() async throws {
        try write(randomData(4096), tmp.appendingPathComponent("x/C001.MOV"))
        try write(randomData(4096), tmp.appendingPathComponent("y/C001.MOV"))
        let dest = try dir("dest")
        let cfg = config(sources: [tmp.appendingPathComponent("x/C001.MOV"),
                                   tmp.appendingPathComponent("y/C001.MOV")], dests: [dest])
        await assertDuplicateTargets(cfg)
        XCTAssertFalse(fm.fileExists(atPath: dest.appendingPathComponent("C001.MOV").path))
    }

    /// Case only differs: one file on a case-insensitive volume (APFS, exFAT default).
    func test_targetsDifferingOnlyByCase_areRefused() async throws {
        let s1 = try dir("S1"), s2 = try dir("S2")
        let dest = try dir("dest")
        try write(randomData(4096), s1.appendingPathComponent("a001.mov"))
        try write(randomData(4096), s2.appendingPathComponent("A001.MOV"))
        var cfg = config(sources: [s1, s2], dests: [dest])
        cfg.copyFolderContents = true
        await assertDuplicateTargets(cfg)
    }

    func test_distinctTargets_inContentsMode_stillCopy() async throws {
        let s1 = try dir("S1"), s2 = try dir("S2")
        let dest = try dir("dest")
        try write(randomData(4096), s1.appendingPathComponent("CLIP/A001.MOV"))
        try write(randomData(4096), s2.appendingPathComponent("CLIP/B001.MOV"))
        var cfg = config(sources: [s1, s2], dests: [dest])
        cfg.copyFolderContents = true
        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.first?.success, true)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("CLIP/A001.MOV").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("CLIP/B001.MOV").path))
    }

    // MARK: 3. Duplicate prompt on three conflicts

    private func threeConflicts() throws -> (card: URL, dest: URL, old: [String: Data]) {
        let card = try dir("A001")
        let dest = try dir("dest")
        var old: [String: Data] = [:]
        for name in ["c1.mov", "c2.mov", "c3.mov"] {
            try write(randomData(2048), card.appendingPathComponent(name))
            old[name] = try write(randomData(1024), dest.appendingPathComponent("A001/\(name)"))
        }
        return (card, dest, old)
    }

    private func runService(card: URL, dest: URL,
                            resolver: @escaping @Sendable (DuplicatePrompt) async -> DuplicateResolution) async throws {
        _ = try await CustomCopierService().runCopyFanOut(
            sources: [card.path], fanOutDestinations: [destConfig(dest)], configName: "",
            organizationPreset: nil, copyFolderContents: false, useHashListPrecheck: false,
            hashListPath: nil, fileOrdering: .defaultOrder, duplicatePolicy: .ask,
            duplicateCounterTemplate: "_001", duplicateResolver: resolver,
            verifyMode: .fast, dryRun: false, hashListStyle: .ascMHL, progressHandler: nil)
    }

    func test_prompt_listsAllThreeConflicts_andAsksEachWhenNotAppliedToAll() async throws {
        let (card, dest, old) = try threeConflicts()
        let seen = Seen()
        try await runService(card: card, dest: dest) { prompt in
            await seen.add(prompt)
            let n = await seen.prompts.count
            // 1st: skip, 2nd: overwrite, 3rd: skip — none applied to all.
            return DuplicateResolution(action: n == 2 ? .overwrite : .skip,
                                       applyToAll: false, counterTemplate: nil)
        }
        let prompts = await seen.prompts
        XCTAssertEqual(prompts.count, 3, "one question per file")
        XCTAssertEqual(prompts.first?.conflictCount, 3)
        XCTAssertEqual(prompts.first?.conflictNames.count, 3)
        XCTAssertEqual(prompts.map(\.position), [0, 1, 2])

        let names = prompts.map { ($0.destinationPath as NSString).lastPathComponent }
        let overwritten = names[1]
        for name in ["c1.mov", "c2.mov", "c3.mov"] {
            let onDisk = try Data(contentsOf: dest.appendingPathComponent("A001/\(name)"))
            if name == overwritten {
                XCTAssertEqual(onDisk, try Data(contentsOf: card.appendingPathComponent(name)))
            } else {
                XCTAssertEqual(onDisk, old[name], "\(name) was skipped and must be intact")
            }
        }
    }

    func test_prompt_applyToAll_answersTheRemainingConflicts() async throws {
        let (card, dest, _) = try threeConflicts()
        let seen = Seen()
        try await runService(card: card, dest: dest) { prompt in
            await seen.add(prompt)
            return DuplicateResolution(action: .overwrite, applyToAll: true, counterTemplate: nil)
        }
        let prompts = await seen.prompts
        XCTAssertEqual(prompts.count, 1)
        XCTAssertEqual(prompts.first?.conflictCount, 3)
        for name in ["c1.mov", "c2.mov", "c3.mov"] {
            XCTAssertEqual(try Data(contentsOf: dest.appendingPathComponent("A001/\(name)")),
                           try Data(contentsOf: card.appendingPathComponent(name)))
        }
    }

    // MARK: 5. Roll name ".."

    func test_rollNameDotDot_neverWritesOutsideTheDestination() async throws {
        let card = try dir("CARD")
        let dest = try dir("outer/dest")
        try write(randomData(4096), card.appendingPathComponent("clip.bin"))
        var cfg = config(sources: [card], dests: [dest])
        cfg.rollNames = [card.path: ".."]
        _ = try await FanOutCopier(config: cfg).run()
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("outer/clip.bin").path),
                       "\"..\" must not climb out of the destination")
        let inside = (try? fm.subpathsOfDirectory(atPath: dest.path)) ?? []
        XCTAssertTrue(inside.contains { $0.hasSuffix("clip.bin") }, "the clip lands inside the destination")
    }

    func test_rollNameWithSlash_staysOneFolder() async throws {
        let card = try dir("CARD")
        // Deep enough that "../../evil" would still land inside the temp folder.
        let dest = try dir("a/b/dest")
        try write(randomData(4096), card.appendingPathComponent("clip.bin"))
        var cfg = config(sources: [card], dests: [dest])
        cfg.rollNames = [card.path: "../../evil"]
        _ = try await FanOutCopier(config: cfg).run()
        let top = try fm.contentsOfDirectory(atPath: dest.path)
            .filter { !$0.hasPrefix(".filmcan") && $0 != ".DS_Store" }
        XCTAssertEqual(top.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent(top[0]).appendingPathComponent("clip.bin").path))
    }
}

/// Main window editor checks (no engine run).
@MainActor
final class OverwriteSafetyEditorTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("overwrite-editor-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? fm.removeItem(at: tmp) }

    private func editor(sources: [String], dest: String) -> BackupEditorViewModel {
        var config = BackupConfiguration()
        config.sourcePaths = sources
        config.destinationPaths = [dest]
        let storage = ConfigurationStorage(baseDirectory: tmp.appendingPathComponent("storage"))
        return BackupEditorViewModel(config: config, storage: storage)
    }

    // MARK: 4. Several loose files

    func test_validate_blocksSeveralLooseFiles_likeQuickCopy() throws {
        let a = tmp.appendingPathComponent("a.mov"), b = tmp.appendingPathComponent("b.mov")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        let dest = tmp.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let vm = editor(sources: [a.path, b.path], dest: dest.path)
        XCTAssertFalse(vm.validate())
        XCTAssertTrue(vm.validationMessage.contains("loose files"), vm.validationMessage)
    }

    func test_validate_acceptsOneLooseFileWithAFolder() throws {
        let a = tmp.appendingPathComponent("a.mov")
        try Data("a".utf8).write(to: a)
        let card = tmp.appendingPathComponent("CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        let dest = tmp.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let vm = editor(sources: [a.path, card.path], dest: dest.path)
        XCTAssertTrue(vm.validate(), vm.validationMessage)
    }

    // MARK: 5. Typed roll name

    func test_typedRollNameDotDot_isNeverStored() throws {
        let card = tmp.appendingPathComponent("CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        let vm = editor(sources: [card.path], dest: tmp.appendingPathComponent("dest").path)
        vm.setRollNameOverride("..", for: card.path)
        let key = RollNumberer.cardKey(forPath: card.path)
        XCTAssertNotEqual(vm.config.genericRollNames[key], "..")
        vm.setRollNameOverride("../../Day 1", for: card.path)
        let stored = vm.config.genericRollNames[key] ?? ""
        XCTAssertFalse(stored.contains("/"))
        XCTAssertEqual(stored, OrganizationTemplate.folderNameAsWritten("../../Day 1"))
    }
}
