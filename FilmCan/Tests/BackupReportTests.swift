import XCTest
@testable import FilmCan

@MainActor
final class BackupReportTests: XCTestCase {
    var tmpDir: URL!

    override func setUp() async throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Real fan-out run of a CARD dir (A.mov, B.wav, meta.xml) to one temp dest.
    private func runBackup() async throws -> (TransferResult, BackupConfiguration, URL) {
        let fm = FileManager.default
        let card = tmpDir.appendingPathComponent("CARD")
        try fm.createDirectory(at: card, withIntermediateDirectories: true)
        for n in ["A.mov", "B.wav", "meta.xml"] {
            try Data((0..<32 * 1024).map { _ in UInt8.random(in: 0...255) })
                .write(to: card.appendingPathComponent(n))
        }
        let dest = tmpDir.appendingPathComponent("dest")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        let cfg = FanOutCopier.Configuration(
            sources: [card.path],
            destinations: [DestWriter.Config(destPath: dest.path, displayName: "D1",
                                             verifyMode: .paranoid, requiresFullFsync: false, chunkSize: 32768)],
            verifyMode: .paranoid, mhlBasePath: nil, dryRun: false, progressHandler: nil)
        let results = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(results.count, 1)

        var fan = TransferResult(configurationName: "Proj", destination: dest.path,
                                 startTime: Date(), endTime: Date(), success: true)
        fan.destinationResults = results
        let exploded = TransferViewModel().explodeFanOutResult(fan, configName: "Proj")
        var config = BackupConfiguration()
        config.name = "Proj"
        return (exploded[0], config, dest)
    }

    func test_build_listsAllFilesSortedAndSkipsAscmhl() async throws {
        let (result, config, _) = try await runBackup()
        let report = BackupReport.build(result: result, config: config, appVersion: "1.0")
        XCTAssertEqual(report.rolls.count, 1)
        let clips = report.rolls[0].clips
        XCTAssertEqual(clips.map(\.relPath), ["A.mov", "B.wav", "meta.xml"])
        XCTAssertFalse(clips.contains { $0.relPath.contains("ascmhl") })
        XCTAssertEqual(clips.map(\.isVideo), [true, false, false])
        XCTAssertEqual(clips.map(\.isAudio), [false, true, false])
        XCTAssertEqual(report.rolls[0].name, "CARD")
    }

    func test_build_fillsChecksumsFromLatestManifest() async throws {
        let (result, config, _) = try await runBackup()
        let report = BackupReport.build(result: result, config: config, appVersion: "1.0")
        let hex = try NSRegularExpression(pattern: "^[0-9a-f]{32}$")
        for clip in report.rolls[0].clips {
            let sum = try XCTUnwrap(clip.checksum, "no checksum for \(clip.relPath)")
            XCTAssertNotNil(hex.firstMatch(in: sum, range: NSRange(sum.startIndex..., in: sum)))
        }
    }
}
