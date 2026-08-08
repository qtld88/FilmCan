import XCTest
@testable import FilmCan

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

    // MARK: seal gate (decision C: all planned destinations verified)

    func test_shouldSeal_trueOnlyWhenEveryPlannedDestVerified() {
        let planned = ["/Volumes/A", "/Volumes/B"]

        let allVerified = [
            makeResult(dest: "/Volumes/A", success: true, verified: true),
            makeResult(dest: "/Volumes/B", success: true, verified: true)
        ]
        XCTAssertTrue(CardSealService.shouldSeal(plannedDestinations: planned, results: allVerified))

        let oneUnverified = [
            makeResult(dest: "/Volumes/A", success: true, verified: true),
            makeResult(dest: "/Volumes/B", success: true, verified: false)
        ]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: planned, results: oneUnverified))

        let oneFailed = [
            makeResult(dest: "/Volumes/A", success: true, verified: true),
            makeResult(dest: "/Volumes/B", success: false, verified: true)
        ]
        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: planned, results: oneFailed))

        XCTAssertFalse(CardSealService.shouldSeal(plannedDestinations: [], results: []))
    }

    private func makeResult(dest: String, success: Bool, verified: Bool) -> TransferResult {
        var r = TransferResult(configurationName: "cfg", destination: dest, startTime: Date())
        r.success = success
        r.wasVerified = verified
        return r
    }
}
