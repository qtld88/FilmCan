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
}
