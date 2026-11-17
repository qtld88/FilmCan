import XCTest
@testable import FilmCan

/// The Run click and the window timers must not do disk or IOKit work on the main
/// thread, and must give the same answers as before. Real temp folders, no mocks.
@MainActor
final class RunFluidityTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default

    override func setUp() async throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("run-fluidity-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: tmp)
    }

    private func makeCard(_ name: String) throws -> URL {
        let card = tmp.appendingPathComponent(name)
        try fm.createDirectory(at: card.appendingPathComponent("CLIPS"), withIntermediateDirectories: true)
        try Data(count: Int(CardFingerprint.minimumClipBytes) + 10)
            .write(to: card.appendingPathComponent("CLIPS/C0001.MP4"))
        try Data([1, 2, 3]).write(to: card.appendingPathComponent("CLIPS/C0001M01.XML"))
        return card
    }

    // MARK: - "Already copied" check

    func test_clipKeysForSeveralSources_matchTheSynchronousReading() async throws {
        XCTAssertTrue(Thread.isMainThread)
        let a = try makeCard("A001")
        let b = try makeCard("B001")
        let keys = await CardFingerprint.keys(forSources: [a.path, b.path])
        XCTAssertEqual(keys[a.path], CardFingerprint.keys(forSource: a.path))
        XCTAssertEqual(keys[b.path], CardFingerprint.keys(forSource: b.path))
        XCTAssertEqual(keys[a.path]?.count, 1, "only the clip of at least 1 MiB counts")
    }

    // MARK: - Drive facts read once, off the main thread

    func test_runProbe_givesTheSameFactsAsTheDirectCalls() async throws {
        let card = try makeCard("A001")
        let loose = tmp.appendingPathComponent("loose.wav")
        try Data([0]).write(to: loose)
        let dest = tmp.appendingPathComponent("SSD")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)

        let probe = await TransferViewModel.probeRun(
            sources: [card.path, loose.path], destinations: [dest.path], detectCameras: true)

        XCTAssertEqual(probe.isDirectory[card.path], true)
        XCTAssertEqual(probe.isDirectory[loose.path], false)
        XCTAssertEqual(probe.cardKeys[card.path], RollNumberer.cardKey(forPath: card.path))
        XCTAssertEqual(probe.signatures[card.path], CameraCardDetector.detect(rootPath: card.path))
        XCTAssertEqual(probe.driveInfo[dest.path], DriveSpeedClassifier.info(for: dest.path))
        let driveId = DriveUtilities.summary(for: dest.path).id
        XCTAssertNotNil(probe.capacity[driveId]?.totalBytes, "capacity of the drive is captured")
        XCTAssertNil(probe.driveInfo[card.path], "IOKit facts are for destinations only")
    }

    func test_runProbe_skipsCameraDetectionWhenNotAsked() async throws {
        let card = try makeCard("A001")
        let probe = await TransferViewModel.probeRun(
            sources: [card.path], destinations: [], detectCameras: false)
        XCTAssertTrue(probe.signatures.isEmpty)
        XCTAssertEqual(probe.isDirectory[card.path], true)
    }

    // MARK: - Logs written off the main thread

    func test_writeFanOutLogsOffMain_fillsTheLogPathAndWritesTheFile() async throws {
        let dest = tmp.appendingPathComponent("SSD")
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        var config = BackupConfiguration()
        config.name = "Movie"
        config.logEnabled = true
        let result = TransferResult(configurationName: "Movie", destination: dest.path,
                                    startTime: Date(), endTime: Date())

        let written = await BackupLogWriter.writeFanOutLogsOffMain(
            config: config, sources: [tmp.appendingPathComponent("A001").path],
            results: [result], preset: nil)

        let path = try XCTUnwrap(written.first?.logFilePath)
        XCTAssertTrue(fm.fileExists(atPath: path), "the log file is on disk")
        XCTAssertTrue(path.hasPrefix(dest.path), "same place as before: the destination")
    }

    // MARK: - One drive-list tick for the whole app

    func test_driveListTicker_runsOnceWhateverTheNumberOfWindows() {
        let ticker = DriveListTicker(interval: 3600, center: NotificationCenter())
        XCTAssertFalse(ticker.isRunning)

        ticker.attach()   // window 1
        ticker.attach()   // window 2
        XCTAssertTrue(ticker.isRunning)
        XCTAssertEqual(ticker.workspaceObserverCount, 3, "mount, unmount, rename — once")

        ticker.detach()   // window 2 closes
        XCTAssertTrue(ticker.isRunning, "still one window open")

        ticker.detach()   // last window closes
        XCTAssertFalse(ticker.isRunning)
        XCTAssertEqual(ticker.workspaceObserverCount, 0)

        ticker.detach()   // unbalanced detach is harmless
        XCTAssertEqual(ticker.attachedCount, 0)
    }

    // MARK: - ntfy header and log hygiene

    func test_ntfyTitle_nonASCIIIsSentAsRFC2047() {
        XCTAssertEqual(WebhookService.ntfyHeaderValue("Backup done"), "Backup done")
        let encoded = WebhookService.ntfyHeaderValue("✅ Tournage été")
        XCTAssertTrue(encoded.hasPrefix("=?UTF-8?B?") && encoded.hasSuffix("?="))
        XCTAssertTrue(encoded.allSatisfy(\.isASCII))
        let base64 = String(encoded.dropFirst("=?UTF-8?B?".count).dropLast(2))
        XCTAssertEqual(Data(base64Encoded: base64).flatMap { String(data: $0, encoding: .utf8) },
                       "✅ Tournage été")
        XCTAssertEqual(WebhookService.ntfyHeaderValue("a\nb"), "a b", "no line break in a header")
    }

    func test_rejectedURL_isLoggedWithoutItsTopic() {
        let line = WebhookService.logSafe(url: "http://ntfy.sh/filmcan-secret-topic?x=1")
        XCTAssertEqual(line, "http://ntfy.sh")
        XCTAssertFalse(WebhookService.logSafe(url: "ftp://user:pw@host/topic").contains("pw"))
    }
}
