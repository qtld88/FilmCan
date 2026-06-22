import XCTest
@testable import FilmCan

final class LogItemizeParserTests: XCTestCase {

    // MARK: isItemizeCode

    func test_isItemizeCode_acceptsTransferAndChangeCodes() {
        XCTAssertTrue(LogItemizeParser.isItemizeCode(">f+++++++++"))
        XCTAssertTrue(LogItemizeParser.isItemizeCode("cd+++++++++"))
        XCTAssertTrue(LogItemizeParser.isItemizeCode(".f"))
    }

    func test_isItemizeCode_rejectsNonCodes() {
        XCTAssertFalse(LogItemizeParser.isItemizeCode("x"))         // too short
        XCTAssertFalse(LogItemizeParser.isItemizeCode("zz"))        // bad prefix
        XCTAssertFalse(LogItemizeParser.isItemizeCode(">z"))        // bad type
    }

    // MARK: shouldRecordItemizedFile — only newly transferred/changed FILES

    func test_shouldRecordItemizedFile_recordsSentAndChangedFiles() {
        XCTAssertTrue(LogItemizeParser.shouldRecordItemizedFile(">f+++++++++"))
        XCTAssertTrue(LogItemizeParser.shouldRecordItemizedFile("cf"))
    }

    func test_shouldRecordItemizedFile_skipsDirsAndReceivedAndDots() {
        XCTAssertFalse(LogItemizeParser.shouldRecordItemizedFile("cd+++++++++")) // directory
        XCTAssertFalse(LogItemizeParser.shouldRecordItemizedFile(".f")) // unchanged
        XCTAssertFalse(LogItemizeParser.shouldRecordItemizedFile("<f")) // received (not our copy dir)
    }

    // MARK: cleanItemizedPath

    func test_cleanItemizedPath_stripsLeadingDotSlashAndArrowTarget() {
        XCTAssertEqual(LogItemizeParser.cleanItemizedPath("./A001/clip.mov"), "A001/clip.mov")
        XCTAssertEqual(LogItemizeParser.cleanItemizedPath("link -> /target"), "link")
        XCTAssertEqual(LogItemizeParser.cleanItemizedPath("  spaced.mov  "), "spaced.mov")
    }

    // MARK: resolveLoggedPath

    func test_resolveLoggedPath_absolutePassesThrough() {
        XCTAssertEqual(
            LogItemizeParser.resolveLoggedPath("/abs/file.mov", roots: ["/r"], fallbackRoot: "/fb"),
            "/abs/file.mov")
    }

    func test_resolveLoggedPath_singleRootIsPrefixed() {
        XCTAssertEqual(
            LogItemizeParser.resolveLoggedPath("A001/clip.mov", roots: ["/Volumes/DEST"], fallbackRoot: "/fb"),
            "/Volumes/DEST/A001/clip.mov")
    }

    func test_resolveLoggedPath_multiRootMatchesByLabel() {
        let roots = ["/Volumes/DEST/CardA", "/Volumes/DEST/CardB"]
        XCTAssertEqual(
            LogItemizeParser.resolveLoggedPath("CardB/clip.mov", roots: roots, fallbackRoot: "/fb"),
            "/Volumes/DEST/CardB/clip.mov")
    }

    func test_resolveLoggedPath_multiRootNoMatchUsesFallback() {
        let roots = ["/Volumes/DEST/CardA", "/Volumes/DEST/CardB"]
        XCTAssertEqual(
            LogItemizeParser.resolveLoggedPath("Unknown/clip.mov", roots: roots, fallbackRoot: "/fb"),
            "/fb/Unknown/clip.mov")
    }

    // MARK: extractItemizedPath

    func test_extractItemizedPath_parsesCodeAndPath() {
        let line = ">f+++++++++ A001/clip.mov"
        let parsed = LogItemizeParser.extractItemizedPath(from: line)
        XCTAssertEqual(parsed?.code, ">f+++++++++")
        XCTAssertEqual(parsed?.path, "A001/clip.mov")
    }

    func test_extractItemizedPath_returnsNilWithoutCode() {
        XCTAssertNil(LogItemizeParser.extractItemizedPath(from: "just some text"))
    }

    // MARK: parseTransferredPaths — end to end over a real log file

    func test_parseTransferredPaths_extractsOnlyTransferredFiles() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".log")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let log = """
        sending incremental file list
        cd+++++++++ A001/
        >f+++++++++ A001/clip1.mov
        >f+++++++++ A001/clip2.mov
        .f          A001/unchanged.mov
        """
        try log.write(to: tmp, atomically: true, encoding: .utf8)

        let result = LogItemizeParser.parseTransferredPaths(
            logFile: tmp.path, roots: ["/Volumes/DEST"], fallbackRoot: "/Volumes/DEST")

        XCTAssertTrue(result.sawItemize)
        XCTAssertEqual(Set(result.paths), Set([
            "/Volumes/DEST/A001/clip1.mov",
            "/Volumes/DEST/A001/clip2.mov",
        ]))
    }

    func test_parseTransferredPaths_missingFileReturnsEmpty() {
        let result = LogItemizeParser.parseTransferredPaths(
            logFile: "/nonexistent/\(UUID().uuidString).log", roots: ["/r"], fallbackRoot: "/r")
        XCTAssertTrue(result.paths.isEmpty)
        XCTAssertFalse(result.sawItemize)
    }
}
