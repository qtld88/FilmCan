import XCTest
@testable import FilmCan

final class CatalogScopeTests: XCTestCase {
    private func roll(_ name: String, configId: UUID?, project: String) -> CatalogRoll {
        CatalogRoll(configId: configId, projectName: project, shootDay: "Day 1", rollName: name,
                    mediaKind: .camera, sourceVolumeUUID: "SRC", sourcePath: "/Volumes/CARD",
                    firstBackedUp: Date(timeIntervalSince1970: 1_000), files: [], copies: [])
    }

    func testShowsOnlyTheSelectedMovie() {
        let tlf = UUID(), other = UUID()
        let rolls = [roll("A001", configId: tlf, project: "TLF"),
                     roll("B001", configId: other, project: "Other")]
        let scoped = CatalogScope(configId: tlf, movieName: "TLF").rolls(in: rolls)
        XCTAssertEqual(scoped.map(\.rollName), ["A001"])
    }

    func testRenamedMovieKeepsItsRollsById() {
        let tlf = UUID()
        let rolls = [roll("A001", configId: tlf, project: "Old name")]
        XCTAssertEqual(CatalogScope(configId: tlf, movieName: "New name").rolls(in: rolls).count, 1)
    }

    func testLegacyRollWithoutIdMatchesByName() {
        let rolls = [roll("A001", configId: nil, project: "TLF"),
                     roll("B001", configId: nil, project: "Other")]
        let scoped = CatalogScope(configId: UUID(), movieName: "TLF").rolls(in: rolls)
        XCTAssertEqual(scoped.map(\.rollName), ["A001"])
    }

    func testSameNameButOtherMovieIdIsExcluded() {
        let rolls = [roll("A001", configId: UUID(), project: "TLF")]
        XCTAssertTrue(CatalogScope(configId: UUID(), movieName: "TLF").rolls(in: rolls).isEmpty)
    }
}
