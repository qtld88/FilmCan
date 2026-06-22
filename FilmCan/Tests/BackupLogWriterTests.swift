import XCTest
@testable import FilmCan

final class BackupLogWriterTests: XCTestCase {

    func test_mergeWarning_concatenatesNonEmpty() {
        XCTAssertEqual(BackupLogWriter.mergeWarning(nil, "b"), "b")
        XCTAssertEqual(BackupLogWriter.mergeWarning("a", "b"), "a\nb")
    }

    func test_ensureWritableLogPath_createsParentAndIsWritable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let path = dir.appendingPathComponent("logs/run.log").path
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(BackupLogWriter.ensureWritableLogPath(path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("logs").path))
    }
}
