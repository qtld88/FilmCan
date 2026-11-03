import XCTest
import PDFKit
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

    private func sampleReport(clipCount: Int) -> BackupReport {
        let clips = (1...clipCount).map { i in
            BackupReport.Clip(relPath: "clip-\(String(format: "%03d", i)).mov",
                              absolutePath: "/nonexistent/clip-\(i).mov", size: Int64(i) * 1_000_000,
                              checksum: String(repeating: "ab", count: 16), checksumAlgorithm: "xxh128",
                              isVideo: true, isAudio: false)
        }
        return BackupReport(
            projectName: "Sample Project", episode: "EP1", day: "Day2", unit: "MU",
            destinationPath: "/Volumes/SSD", destinationVolumeName: "SSD",
            startedAt: Date(), endedAt: Date().addingTimeInterval(120), success: true, verified: true,
            warning: nil,
            rolls: [BackupReport.Roll(name: "A001", folderPath: "/Volumes/SSD/A001",
                                      mediaKind: .camera, clips: clips)],
            appVersion: "1.0")
    }

    func test_render_producesReadablePDFWithClipNames() throws {
        let url = tmpDir.appendingPathComponent("r.pdf")
        try BackupReportWriter.render(sampleReport(clipCount: 3), thumbnails: [:], durations: [:], to: url)
        let doc = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 1)
        let text = doc.string ?? ""
        for n in ["clip-001.mov", "clip-002.mov", "clip-003.mov", "Sample Project"] {
            XCTAssertTrue(text.contains(n), "missing \(n)")
        }
    }

    func test_render_paginates() throws {
        let url = tmpDir.appendingPathComponent("r.pdf")
        try BackupReportWriter.render(sampleReport(clipCount: 40), thumbnails: [:], durations: [:], to: url)
        let doc = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertGreaterThanOrEqual(doc.pageCount, 2)
        XCTAssertTrue(doc.page(at: 1)?.string?.contains("(cont.)") ?? false)
    }

    func test_thumbnail_nonVideo_returnsIconQuickly() async throws {
        let f = tmpDir.appendingPathComponent("x.xml")
        try Data("<a/>".utf8).write(to: f)
        let start = Date()
        let img = await BackupReportWriter.thumbnail(for: f.path, isVideo: false, isAudio: false)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertGreaterThan(img.size.width, 0)
    }

    func test_generate_withoutLog_returnsNil() async {
        let result = TransferResult(configurationName: "X", destination: tmpDir.path, startTime: Date())
        let path = await BackupReportWriter.generate(result: result, config: BackupConfiguration())
        XCTAssertNil(path)
    }
}
