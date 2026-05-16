import XCTest
@testable import FilmCan

final class FanOutCopierTests: XCTestCase {

    // MARK: - Atomic finalize

    func test_atomicFinalize_tempFileCreatedThenRenamed() async throws {
        let fm = FileManager.default
        let tmpDir = fm.temporaryDirectory.appendingPathComponent("test-atomic-\(UUID().uuidString)")
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        let sourceURL = tmpDir.appendingPathComponent("source.bin")
        let destDir = tmpDir.appendingPathComponent("dest")
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Create source data
        let testData = Data("hello world".utf8)
        try testData.write(to: sourceURL)

        // Configure fan-out
        let config = FanOutCopier.Configuration(
            sources: [sourceURL.path],
            destinations: [
                DestWriter.Config(
                    destPath: destDir.path,
                    displayName: "TestDest",
                    verifyMode: .paranoid,
                    requiresFullFsync: false,
                    tempSuffix: ".filmcan-test",
                    chunkSize: 4096
                )
            ],
            verifyMode: .paranoid,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )

        let copier = FanOutCopier(config: config)
        let results = try await copier.run()

        // Verify result
        XCTAssertEqual(results.count, 1)
        let result = results[0]
        XCTAssertTrue(result.success, "Copy should succeed")
        XCTAssertEqual(result.bytesTransferred, Int64(testData.count))

        // Verify file exists at destination
        let destFile = destDir.appendingPathComponent("source.bin")
        XCTAssertTrue(fm.fileExists(atPath: destFile.path), "Destination file should exist")
        let destData = try Data(contentsOf: destFile)
        XCTAssertEqual(destData, testData, "File content should match")

        // Verify no temp files left
        let contents = try fm.contentsOfDirectory(atPath: destDir.path)
        let temps = contents.filter { $0.hasPrefix(".filmcan-") }
        XCTAssertTrue(temps.isEmpty, "No temp files should remain, but found: \(temps)")
    }

    // MARK: - Duplicate detection
}
