import XCTest
@testable import FilmCan

final class SettingsWordingTests: XCTestCase {

    func test_firstLevelLabels_sayTheEffect_notTheMechanism() {
        for label in SettingsWording.firstLevelLabels {
            for term in SettingsWording.avoidedTerms {
                XCTAssertFalse(label.lowercased().contains(term), "\"\(label)\" contains \"\(term)\"")
            }
            XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    func test_everyVerificationMode_hasItsOwnLabel() {
        let labels = VerifyMode.allCases.map(SettingsWording.verification)
        XCTAssertEqual(Set(labels).count, VerifyMode.allCases.count)
    }

    func test_settingsPages_keepEveryFormerTab() {
        XCTAssertEqual(SettingsPage.allCases.map(\.rawValue),
                       ["appearance", "notifications", "push", "history", "drives", "hotkeys", "about"])
        XCTAssertEqual(Set(SettingsPage.allCases.map(\.title)).count, SettingsPage.allCases.count)
    }

    func test_unknownStoredPage_opensTheFirstPage() {
        XCTAssertEqual(SettingsPage.page(for: "gone"), .appearance)
        XCTAssertEqual(SettingsPage.page(for: "drives"), .drives)
    }

    func test_onePaneAtATime() {
        XCTAssertTrue(MovieSettingsPanel.isShown(wantsOpen: true, otherPaneOpen: false))
        XCTAssertFalse(MovieSettingsPanel.isShown(wantsOpen: true, otherPaneOpen: true))
        XCTAssertFalse(MovieSettingsPanel.isShown(wantsOpen: false, otherPaneOpen: false))
    }

    func test_panelWidth_staysBetweenItsBounds() {
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 1280), 460)
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 800), 400)
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 500), 340)
    }
}
