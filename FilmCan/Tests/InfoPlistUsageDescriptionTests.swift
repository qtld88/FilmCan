import XCTest
@testable import FilmCan

/// macOS shows these sentences in the "FilmCan would like to access files…" dialogs.
/// Without them the dialog gives no reason at all, on the very first launch.
final class InfoPlistUsageDescriptionTests: XCTestCase {
    private let keys = [
        "NSRemovableVolumesUsageDescription",
        "NSNetworkVolumesUsageDescription",
        "NSDocumentsFolderUsageDescription",
        "NSDesktopFolderUsageDescription",
        "NSDownloadsFolderUsageDescription",
    ]

    func testAppBundleExplainsEveryFileAccessDialog() throws {
        // Tests are hosted by FilmCan.app, so Bundle.main is the app bundle.
        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        try XCTSkipUnless(Bundle.main.bundleIdentifier == "com.filmcan.app", "not hosted by FilmCan.app")
        for key in keys {
            let text = try XCTUnwrap(info[key] as? String, "\(key) is missing from Info.plist")
            XCTAssertGreaterThan(text.count, 20, "\(key) should be a full sentence")
            XCTAssertTrue(text.contains("FilmCan"), "\(key) should name the app")
        }
    }
}
