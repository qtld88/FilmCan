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
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 2000), 540)
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 1200), 504)
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 840), MovieSettingsPanel.minimumWidth)
        // Too narrow for both: the panel takes the whole editor.
        XCTAssertFalse(MovieSettingsPanel.isSideBySide(editorWidth: 839))
        XCTAssertEqual(MovieSettingsPanel.width(editorWidth: 600), 600)
    }

    func test_sections_toggleOneAtATime_keepStackOrder() {
        var stored = MovieSettingsSections.defaultStored
        XCTAssertTrue(MovieSettingsSections.isOpen("basic", stored: stored))
        XCTAssertFalse(MovieSettingsSections.isOpen("logs", stored: stored))
        stored = MovieSettingsSections.toggling("logs", in: stored)
        stored = MovieSettingsSections.toggling("source", in: stored)
        XCTAssertEqual(stored, "basic,source,logs")
        stored = MovieSettingsSections.toggling("basic", in: stored)
        XCTAssertEqual(stored, "source,logs")
        // Everything closed is a valid state.
        stored = MovieSettingsSections.toggling("source", in: stored)
        stored = MovieSettingsSections.toggling("logs", in: stored)
        XCTAssertEqual(stored, "")
        XCTAssertTrue(MovieSettingsSections.openKeys(from: stored).isEmpty)
    }

    func test_sections_ignoreUnknownKeys_andOpeningIsIdempotent() {
        XCTAssertEqual(MovieSettingsSections.openKeys(from: "gone,logs,,"), ["logs"])
        XCTAssertEqual(MovieSettingsSections.toggling("gone", in: "logs"), "logs")
        XCTAssertEqual(MovieSettingsSections.opening("destinations", in: "basic"), "basic,destinations")
        XCTAssertEqual(MovieSettingsSections.opening("basic", in: "basic"), "basic")
    }

    func test_sectionContent_fitsInsideThePanel() {
        // Rows are sized from the width inside the panel, not the panel itself:
        // sizing them from the outer width is what pushed them past the edge.
        for panel in [MovieSettingsPanel.minimumWidth, 504, 540] as [CGFloat] {
            let inner = MovieSettingsSections.contentWidth(panelWidth: panel)
            XCTAssertEqual(inner, panel - 2 * MovieSettingsSections.contentInset)
            for extra in [0, 60, 100] as [CGFloat] {
                let text = optionsResolvedTextWidth(OptionsLayout.basicTextWidth, availableWidth: inner)
                let menu = optionsResolvedMenuWidth(OptionsLayout.menuWidth + extra, textWidth: text, availableWidth: inner)
                let menuRow = OptionsLayout.iconWidth + OptionsLayout.spacing * 2 + text + menu
                XCTAssertLessThanOrEqual(menuRow, inner, "menu row, panel \(panel), menu +\(extra)")
            }
            let text = optionsResolvedTextWidth(OptionsLayout.textWidth, availableWidth: inner)
            let switchRow = OptionsLayout.iconWidth + OptionsLayout.spacing * 2 + text + OptionsLayout.toggleWidth
            XCTAssertLessThanOrEqual(switchRow, inner, "switch row, panel \(panel)")
        }
        XCTAssertEqual(MovieSettingsSections.contentWidth(panelWidth: 10), 0)
    }
}
