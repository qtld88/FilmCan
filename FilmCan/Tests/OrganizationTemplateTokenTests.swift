import XCTest
@testable import FilmCan

final class OrganizationTemplateTokenTests: XCTestCase {
    private func makeDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func preset(_ template: String) -> OrganizationPreset {
        var p = OrganizationPreset()
        p.useFolderTemplate = true
        p.folderTemplate = template
        return p
    }

    func testNetflixTokensResolveInFolderPath() {
        let r = OrganizationTemplate.resolve(
            preset: preset("{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"),
            sourcePath: "/cards/A001", destinationRoot: "/dest", counter: 0,
            date: makeDate(2026, 6, 15),
            metadata: ShootMetadata(episode: "EP103", day: "Day05", unit: "MU", cameraFormat: "ARRI"))
        XCTAssertEqual(r.folderPath, "20260615_EP103_Day05_MU/Camera_Media/ARRI")
        XCTAssertEqual(r.renamedItem, "A001")
    }

    func testEmptyCameraFormatCollapses() {
        let r = OrganizationTemplate.resolve(
            preset: preset("{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"),
            sourcePath: "/cards/A001", destinationRoot: "/dest", counter: 0,
            date: makeDate(2026, 6, 15),
            metadata: ShootMetadata(episode: "EP103", day: "Day05", unit: "MU", cameraFormat: ""))
        XCTAssertEqual(r.folderPath, "20260615_EP103_Day05_MU/Camera_Media")
    }

    func testEmptyEpisodeAndUnitDoNotLeaveStrayUnderscores() {
        let r = OrganizationTemplate.resolve(
            preset: preset("{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"),
            sourcePath: "/cards/A001", destinationRoot: "/dest", counter: 0,
            date: makeDate(2026, 6, 16),
            metadata: ShootMetadata(episode: "", day: "DAY01", unit: "", cameraFormat: "ARRI"))
        XCTAssertEqual(r.folderPath, "20260616_DAY01/Camera_Media/ARRI")
    }
}
