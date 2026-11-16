import XCTest
@testable import FilmCan


extension CardSealService {
    /// Test helper: seal what a fresh walk of the card finds. Production seals the list
    /// the engine copied (`entries(of:source:)`), never a walk after the copy.
    static func seal(source: URL, preset: OrganizationPreset?,
                     destinationsVerified: [String], mhlRef: String?) async throws {
        let walked = await FileEnumerator.enumerateFiles(sources: [source.path], preset: preset)
        let entries = walked.entries.map {
            CardSeal.Entry(relPath: $0.relativePath, size: $0.logicalSize, modified: $0.modified)
        }
        try await seal(source: source, entries: entries, preset: preset,
                       destinationsVerified: destinationsVerified, mhlRef: mhlRef)
    }
}

final class CardSealServiceTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cardseal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ rel: String, bytes: Int) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    // MARK: seal → evaluate

    func test_evaluate_noMarker_returnsNone() async throws {
        try write("A001.MOV", bytes: 10)
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .none)
    }

    func test_sealThenEvaluateUnchanged_returnsSealed() async throws {
        try write("A001.MOV", bytes: 10)
        try write("sub/B002.MOV", bytes: 20)
        try await CardSealService.seal(source: root, preset: nil,
                                       destinationsVerified: ["/Volumes/DEST"], mhlRef: nil)
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .sealed)
    }

    func test_addedFile_breaksSeal() async throws {
        try write("A001.MOV", bytes: 10)
        try await CardSealService.seal(source: root, preset: nil,
                                       destinationsVerified: [], mhlRef: nil)
        try write("A002.MOV", bytes: 30)
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .broken(added: ["A002.MOV"], missing: [], modified: []))
    }

    func test_removedFile_breaksSeal() async throws {
        try write("A001.MOV", bytes: 10)
        try write("A002.MOV", bytes: 20)
        try await CardSealService.seal(source: root, preset: nil,
                                       destinationsVerified: [], mhlRef: nil)
        try FileManager.default.removeItem(at: root.appendingPathComponent("A002.MOV"))
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .broken(added: [], missing: ["A002.MOV"], modified: []))
    }

    func test_resizedFile_breaksSealAsModified() async throws {
        try write("A001.MOV", bytes: 10)
        try await CardSealService.seal(source: root, preset: nil,
                                       destinationsVerified: [], mhlRef: nil)
        try write("A001.MOV", bytes: 999)  // same name, different size
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .broken(added: [], missing: [], modified: ["A001.MOV"]))
    }

    func test_fileInsideHiddenNamespace_doesNotBreakSeal() async throws {
        try write("A001.MOV", bytes: 10)
        try await CardSealService.seal(source: root, preset: nil,
                                       destinationsVerified: [], mhlRef: nil)
        // Writing more inside .filmcan/ must be ignored (FileEnumerator excludes it).
        try write("\(FilmCanPaths.hidden)/scratch.txt", bytes: 5)
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .sealed)
    }

    func test_unknownSchemaVersion_returnsNone() async throws {
        try write("A001.MOV", bytes: 10)
        let markerDir = root.appendingPathComponent(FilmCanPaths.hidden)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":999,"volumeUUID":"x","sealDate":0,"appVersion":"1","entries":[],"includePatterns":[],"excludePatterns":[],"copyOnlyPatterns":[],"destinationsVerified":[],"mhlRef":null}"#
        try json.data(using: .utf8)!.write(to: markerDir.appendingPathComponent("seal.json"))
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .none)
    }

    func test_malformedMarker_returnsNone() async throws {
        let markerDir = root.appendingPathComponent(FilmCanPaths.hidden)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: markerDir.appendingPathComponent("seal.json"))
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .none)
    }

    // MARK: seal gate (every planned file hash-compared at every planned destination)

    private let srcA = PlannedSourceFile(sourcePath: "/card/A001.MOV", rootPath: "/card", relPath: "A001.MOV",
                                         size: 10, modified: 1, isDirectoryRoot: true)
    private let srcB = PlannedSourceFile(sourcePath: "/card/B002.MOV", rootPath: "/card", relPath: "B002.MOV",
                                         size: 20, modified: 1, isDirectoryRoot: true)

    private func plan(_ files: [PlannedSourceFile], ignored: [String] = []) -> RunPlan {
        RunPlan(files: files, ignoredUnreadable: ignored)
    }

    private func makeResult(dest: String, success: Bool = true, mode: VerifyMode = .fast,
                            proven: [PlannedSourceFile]) -> TransferResult {
        var dr = DestResult(destinationPath: dest, displayName: (dest as NSString).lastPathComponent)
        dr.success = success
        dr.verifyMode = mode
        dr.verifiedSourcePaths = Set(proven.map(\.sourcePath))
        var r = TransferResult(configurationName: "cfg", destination: dest, startTime: Date())
        r.success = success
        r.destinationResults = [dr]
        return r
    }

    func test_shouldSeal_trueOnlyWhenEveryDestProvedEveryFile() {
        let planned = ["/Volumes/A", "/Volumes/B"]
        let p = plan([srcA, srcB])

        let all = [makeResult(dest: "/Volumes/A", proven: [srcA, srcB]),
                   makeResult(dest: "/Volumes/B", mode: .paranoid, proven: [srcA, srcB])]
        XCTAssertTrue(CardSealService.shouldSeal(plannedDestinations: planned, results: all, plan: p))

        let oneFileShort = [makeResult(dest: "/Volumes/A", proven: [srcA, srcB]),
                            makeResult(dest: "/Volumes/B", proven: [srcA])]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: planned, results: oneFileShort, plan: p))

        let oneFailed = [makeResult(dest: "/Volumes/A", proven: [srcA, srcB]),
                         makeResult(dest: "/Volumes/B", success: false, proven: [srcA, srcB])]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: planned, results: oneFailed, plan: p))

        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: [], results: [], plan: p))
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: planned, results: all, plan: nil))
    }

    /// Verification Off proves nothing, whatever the destination reports.
    func test_shouldSeal_verificationOffNeverSeals() {
        let off = [makeResult(dest: "/Volumes/A", mode: .off, proven: [])]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: ["/Volumes/A"], results: off,
                                                  plan: plan([srcA])))
    }

    /// A mode other than Off is not proof: the per-file set is.
    func test_shouldSeal_fastModeWithoutPerFileProofDoesNotSeal() {
        let claimed = [makeResult(dest: "/Volumes/A", mode: .fast, proven: [])]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: ["/Volumes/A"], results: claimed,
                                                  plan: plan([srcA])))
    }

    func test_shouldSeal_ignoredUnreadableItemsNeverSeal() {
        let all = [makeResult(dest: "/Volumes/A", proven: [srcA])]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: ["/Volumes/A"], results: all,
                                                  plan: plan([srcA], ignored: ["/card/PRIVATE"])))
    }

    /// The real path: per-destination records from `explodeFanOutResult`.
    @MainActor
    func test_shouldSeal_explodedFastRunOnTwoDrives() {
        var a = DestResult(destinationPath: "/Volumes/A", displayName: "A")
        a.success = true; a.verifyMode = .fast; a.verifiedSourcePaths = [srcA.sourcePath]
        var b = DestResult(destinationPath: "/Volumes/B", displayName: "B")
        b.success = true; b.verifyMode = .fast; b.verifiedSourcePaths = [srcA.sourcePath]
        var fanOut = TransferResult(configurationName: "cfg", destination: "/Volumes/A",
                                    startTime: Date(), success: true)
        fanOut.destinationResults = [a, b]
        let exploded = TransferViewModel().explodeFanOutResult(fanOut, configName: "cfg")
        XCTAssertTrue(exploded.allSatisfy { !$0.wasVerified }, "wasVerified stays Paranoid-only")
        XCTAssertTrue(CardSealService.shouldSeal(plannedDestinations: ["/Volumes/A", "/Volumes/B"],
                                                 results: exploded, plan: plan([srcA])))
    }

    // MARK: seal content

    /// The seal lists the planned files, not whatever the card holds afterwards, so a
    /// file added during the run is not covered and breaks the seal at once.
    func test_fileAddedAfterPlanning_isNotSealed() async throws {
        try write("A001.MOV", bytes: 10)
        let walked = await FileEnumerator.enumerateFiles(sources: [root.path], preset: nil)
        let planned = RunPlan(files: walked.entries.map {
            PlannedSourceFile(sourcePath: $0.sourcePath, rootPath: root.path, relPath: $0.relativePath,
                              size: $0.logicalSize, modified: $0.modified, isDirectoryRoot: true)
        })
        // A clip lands on the card while the copy runs.
        try write("A002.MOV", bytes: 30)

        try await CardSealService.seal(
            source: root, entries: CardSealService.entries(of: planned, source: root.path),
            preset: nil, destinationsVerified: ["/Volumes/DEST"], mhlRef: nil)

        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .broken(added: ["A002.MOV"], missing: [], modified: []))
    }

    /// Same name, same size, different modification time: not the file that was copied.
    func test_sameSizeDifferentMtime_breaksSealAsModified() async throws {
        try write("A001.MOV", bytes: 10)
        try await CardSealService.seal(source: root, preset: nil, destinationsVerified: [], mhlRef: nil)
        let url = root.appendingPathComponent("A001.MOV")
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)], ofItemAtPath: url.path)
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .broken(added: [], missing: [], modified: ["A001.MOV"]))
    }

    /// A schema-1 marker (no modification time) reads as "not sealed".
    func test_schemaVersion1Marker_returnsNone() async throws {
        try write("A001.MOV", bytes: 10)
        let markerDir = root.appendingPathComponent(FilmCanPaths.hidden)
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        let json = #"{"schemaVersion":1,"volumeUUID":"","sealDate":0,"appVersion":"1","entries":[{"relPath":"A001.MOV","size":10}],"includePatterns":[],"excludePatterns":[],"copyOnlyPatterns":[],"destinationsVerified":[],"mhlRef":null}"#
        try json.data(using: .utf8)!.write(to: markerDir.appendingPathComponent("seal.json"))
        let state = await CardSealService.evaluate(source: root)
        XCTAssertEqual(state, .none)
    }

    // MARK: demo movie

    func test_demoMovieIsNeverSealed() throws {
        let suite = "cardseal-demo-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let demoId = UUID()
        defaults.set(demoId.uuidString, forKey: DemoSession.defaultsKey)
        XCTAssertFalse(CardSealService.isSealable(configId: demoId, defaults: defaults))
        XCTAssertTrue(CardSealService.isSealable(configId: UUID(), defaults: defaults))
    }
}
