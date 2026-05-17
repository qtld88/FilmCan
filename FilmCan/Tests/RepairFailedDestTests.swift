import XCTest
@testable import FilmCan

@MainActor
final class RepairFailedDestTests: XCTestCase {

    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("repair-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tmpDir = tmpDir {
            try? FileManager.default.removeItem(at: tmpDir)
        }
    }

    /// Sibling branch: a successful sibling dest with a sealed MHL repairs the failed dest
    /// by copying every MHL-listed file from sibling → failed, hash-verified.
    func test_repairFailedDest_fromSibling_copiesAllFilesAndUpdatesResult() async throws {
        let fm = FileManager.default

        // Build a "sibling" dest that already holds two files + an MHL.
        let siblingRoot = tmpDir.appendingPathComponent("sibling")
        try fm.createDirectory(at: siblingRoot, withIntermediateDirectories: true)
        let f1Data = Data((0..<64 * 1024).map { _ in UInt8.random(in: 0...255) })
        let f2Data = Data((0..<32 * 1024).map { _ in UInt8.random(in: 0...255) })
        try f1Data.write(to: siblingRoot.appendingPathComponent("a.bin"))
        try f2Data.write(to: siblingRoot.appendingPathComponent("b.bin"))

        let mhlDir = siblingRoot.appendingPathComponent(".filmcan/hashlists")
        try fm.createDirectory(at: mhlDir, withIntermediateDirectories: true)
        let mhlURL = mhlDir.appendingPathComponent("CARD.mhl")
        // Compute real xxh128 hashes so SiblingDestSource will accept them.
        let h1 = try await xxh128Hex(of: siblingRoot.appendingPathComponent("a.bin"))
        let h2 = try await xxh128Hex(of: siblingRoot.appendingPathComponent("b.bin"))
        // MHL schema per MHLReader: <file name="…"><hash>HEX</hash></file>
        let mhlBody = """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="2.0" xmlns:filmcan="https://filmcan.app/ns">
          <hashes>
            <file name="a.bin"><hash>\(h1)</hash></file>
            <file name="b.bin"><hash>\(h2)</hash></file>
          </hashes>
          <sealed/>
        </hashlist>
        """
        try mhlBody.write(to: mhlURL, atomically: true, encoding: .utf8)

        // "failed" dest: empty directory.
        let failedRoot = tmpDir.appendingPathComponent("failed")
        try fm.createDirectory(at: failedRoot, withIntermediateDirectories: true)

        let sibling = DestResult(
            destinationPath: siblingRoot.path,
            displayName: "sibling",
            success: true,
            filesTransferred: 2,
            filesSkipped: 0,
            filesFailedAfterCopy: 0,
            bytesTransferred: Int64(f1Data.count + f2Data.count),
            failureReason: nil,
            mhlPath: mhlURL.path,
            durationSec: 1,
            verifyMode: .paranoid
        )
        let failed = DestResult(
            destinationPath: failedRoot.path,
            displayName: "failed",
            success: false,
            filesTransferred: 0,
            filesSkipped: 0,
            filesFailedAfterCopy: 2,
            bytesTransferred: 0,
            failureReason: .ioError("simulated"),
            mhlPath: nil,
            durationSec: 0,
            verifyMode: .paranoid
        )

        // Seed the view-model's results so the repair entry-point can find the parent TransferResult.
        let vm = TransferViewModel(isBackgroundWorker: true)
        var parent = TransferResult(
            configurationName: "test",
            destination: failedRoot.path,
            startTime: Date(),
            endTime: Date(),
            success: false,
            errorMessage: "1 destination(s) failed",
            warningMessage: nil,
            filesTransferred: 2,
            bytesTransferred: Int64(f1Data.count + f2Data.count),
            totalBytes: Int64(f1Data.count + f2Data.count),
            filesSkipped: 0,
            errors: [],
            hashListPath: nil,
            wasVerified: true
        )
        parent.destinationResults = [sibling, failed]
        vm.results = [parent]

        // Act
        let ok = await vm.repairFailedDest(failed: failed, sibling: sibling, choice: .fromSibling)

        // Assert
        XCTAssertTrue(ok, "Sibling repair should report success when all MHL files copy + hash-verify")
        XCTAssertTrue(fm.fileExists(atPath: failedRoot.appendingPathComponent("a.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: failedRoot.appendingPathComponent("b.bin").path))
        XCTAssertEqual(try Data(contentsOf: failedRoot.appendingPathComponent("a.bin")), f1Data)
        XCTAssertEqual(try Data(contentsOf: failedRoot.appendingPathComponent("b.bin")), f2Data)

        // Parent TransferResult.destinationResults[1] should now be marked success.
        let updated = vm.results.first?.destinationResults.first(where: { $0.destinationPath == failedRoot.path })
        XCTAssertEqual(updated?.success, true, "Failed dest entry should flip to success after repair")
    }

    /// Source branch: when the original source is still mounted, repair should
    /// re-copy the source into the failed dest using the fan-out engine.
    func test_repairFailedDest_fromSource_recopiesSourceFile() async throws {
        let fm = FileManager.default

        // Source file that "still exists" on disk.
        let sourceURL = tmpDir.appendingPathComponent("clip.bin")
        let sourceData = Data((0..<128 * 1024).map { _ in UInt8.random(in: 0...255) })
        try sourceData.write(to: sourceURL)

        let sibling = DestResult(
            destinationPath: tmpDir.appendingPathComponent("ignored-sibling").path,
            displayName: "ignored",
            success: true,
            filesTransferred: 1,
            filesSkipped: 0,
            filesFailedAfterCopy: 0,
            bytesTransferred: Int64(sourceData.count),
            failureReason: nil,
            mhlPath: nil,
            durationSec: 1,
            verifyMode: .paranoid
        )
        let failedRoot = tmpDir.appendingPathComponent("failed-src")
        try fm.createDirectory(at: failedRoot, withIntermediateDirectories: true)
        let failed = DestResult(
            destinationPath: failedRoot.path,
            displayName: "failed",
            success: false,
            filesTransferred: 0,
            filesSkipped: 0,
            filesFailedAfterCopy: 1,
            bytesTransferred: 0,
            failureReason: .ioError("simulated"),
            mhlPath: nil,
            durationSec: 0,
            verifyMode: .paranoid
        )

        let vm = TransferViewModel(isBackgroundWorker: true)
        vm.currentSources = [sourceURL.path]
        var parent = TransferResult(
            configurationName: "test",
            destination: failedRoot.path,
            startTime: Date(),
            endTime: Date(),
            success: false,
            errorMessage: "1 destination(s) failed",
            warningMessage: nil,
            filesTransferred: 1,
            bytesTransferred: Int64(sourceData.count),
            totalBytes: Int64(sourceData.count),
            filesSkipped: 0,
            errors: [],
            hashListPath: nil,
            wasVerified: true
        )
        parent.destinationResults = [sibling, failed]
        vm.results = [parent]

        let ok = await vm.repairFailedDest(failed: failed, sibling: sibling, choice: .fromSource)

        XCTAssertTrue(ok, "Source repair should succeed when source is reachable")
        XCTAssertTrue(fm.fileExists(atPath: failedRoot.appendingPathComponent("clip.bin").path))
        XCTAssertEqual(try Data(contentsOf: failedRoot.appendingPathComponent("clip.bin")), sourceData)
    }

    // Helper: compute xxh128 hex of a file by feeding it through XXH128StreamingHasher in 64KB chunks.
    private func xxh128Hex(of url: URL) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let hasher = XXH128StreamingHasher() else {
            XCTFail("Could not init hasher")
            return ""
        }
        while true {
            let chunk = try handle.read(upToCount: 65536) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}
