import XCTest
@testable import FilmCan

final class NotificationSummaryBuilderTests: XCTestCase {

    func test_formatQuotedList_variants() {
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList([]), "No items")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/One"]), "\"One\"")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/One", "/b/Two"]),
                       "\"One\" and \"Two\"")
        XCTAssertEqual(NotificationSummaryBuilder.formatQuotedList(["/a/A", "/b/B", "/c/C", "/d/D"]),
                       "\"A\", \"B\", \"C\", and 1 others")
    }

    func test_durationString_formats() {
        XCTAssertNil(NotificationSummaryBuilder.durationString(durations: []))
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [5]), "5s")
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [65]), "1m 5s")
        XCTAssertEqual(NotificationSummaryBuilder.durationString(durations: [3661]), "1h 1m 1s")
    }

    // MARK: - destinationSummary branching (the previously-uncovered logic)

    private func makeConfig() -> BackupConfiguration {
        var c = BackupConfiguration()
        c.name = "Ep01"
        c.destinationPaths = ["/Volumes/DEST"]
        return c
    }

    private func makeResult(success: Bool, error: String?) -> TransferResult {
        let start = Date(timeIntervalSince1970: 1_000_000)
        return TransferResult(
            configurationName: "Ep01",
            destination: "/Volumes/DEST",
            startTime: start,
            endTime: start.addingTimeInterval(5),
            success: success,
            errorMessage: error,
            filesTransferred: 3)
    }

    private var emptyTemplateSettings: NotificationSettings {
        NotificationSettings(
            notifyOnComplete: true, notifyOnError: true,
            ntfyEnabled: false, ntfyURL: "",
            ntfyTitleTemplate: "", ntfyMessageTemplate: "",
            webhookEnabled: false, webhookURL: "", webhookIncludeFullPaths: false)
    }

    func test_destinationSummary_successBranch() {
        let s = NotificationSummaryBuilder.destinationSummary(
            source: "/Volumes/CARD/A001", config: makeConfig(),
            result: makeResult(success: true, error: nil),
            totalFiles: 3, totalBytes: 1_000_000, settings: emptyTemplateSettings)
        XCTAssertTrue(s.allSuccess)
        XCTAssertFalse(s.wasPaused)
        XCTAssertEqual(s.title, "A001's backup for Ep01: Done.")
        XCTAssertTrue(s.body.contains("has been backed up to DEST"))
        // Empty templates → messageTitle/body fall back to title/body.
        XCTAssertEqual(s.messageTitle, s.title)
        XCTAssertEqual(s.messageBody, s.body)
    }

    func test_destinationSummary_cancelledBranch() {
        let s = NotificationSummaryBuilder.destinationSummary(
            source: "/Volumes/CARD/A001", config: makeConfig(),
            result: makeResult(success: false, error: "Run was cancelled by user"),
            totalFiles: 0, totalBytes: 0, settings: emptyTemplateSettings)
        XCTAssertFalse(s.allSuccess)
        XCTAssertEqual(s.title, "A001's backup for Ep01: Cancelled by user.")
        XCTAssertTrue(s.body.contains("failed to back up"))
    }

    func test_destinationSummary_failedBranch() {
        let s = NotificationSummaryBuilder.destinationSummary(
            source: "/Volumes/CARD/A001", config: makeConfig(),
            result: makeResult(success: false, error: "Disk full"),
            totalFiles: 0, totalBytes: 0, settings: emptyTemplateSettings)
        XCTAssertFalse(s.allSuccess)
        XCTAssertEqual(s.title, "A001's backup for Ep01: Failed.")
        XCTAssertEqual(s.fields["{backupDetails}"], "Disk full")
    }

    func test_destinationSummary_appliesCustomTemplates() {
        var settings = emptyTemplateSettings
        settings.ntfyTitleTemplate = "{movie} → {backupStatus}"
        settings.ntfyMessageTemplate = "{files} files / {source}"
        let s = NotificationSummaryBuilder.destinationSummary(
            source: "/Volumes/CARD/A001", config: makeConfig(),
            result: makeResult(success: true, error: nil),
            totalFiles: 3, totalBytes: 1_000_000, settings: settings)
        XCTAssertEqual(s.messageTitle, "Ep01 → Done.")
        XCTAssertEqual(s.messageBody, "3 files / A001")
    }
}
