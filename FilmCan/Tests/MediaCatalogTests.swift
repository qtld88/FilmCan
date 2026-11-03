import XCTest
@testable import FilmCan

final class MediaCatalogTests: XCTestCase {

    private func copy(_ uuid: String?, name: String = "SSD", path: String? = nil,
                      verified: Bool = true, date: Date = Date()) -> CatalogCopy {
        CatalogCopy(destVolumeUUID: uuid, destVolumeName: name,
                    rollFolderPath: path ?? "/Volumes/\(uuid ?? name)/A001",
                    verified: verified, date: date)
    }

    private func roll(copies: [CatalogCopy], files: [CatalogFile] = [],
                      rollName: String = "A001", sourceUUID: String? = "SRC") -> CatalogRoll {
        CatalogRoll(configId: nil, projectName: "Proj", shootDay: "Day 1", rollName: rollName,
                    mediaKind: .camera, sourceVolumeUUID: sourceUUID, sourcePath: "/Volumes/CARD",
                    firstBackedUp: Date(timeIntervalSince1970: 1_000), files: files, copies: copies)
    }

    func test_coverage_twoDistinctUUIDs_isSafe() {
        let r = roll(copies: [copy("A"), copy("B")])
        XCTAssertEqual(r.coverage, .safe(drives: 2))
    }

    func test_coverage_sameUUIDTwice_isSingle() {
        let r = roll(copies: [copy("A", path: "/Volumes/X/A001"), copy("A", path: "/Volumes/X/B/A001")])
        XCTAssertEqual(r.coverage, .single)
    }

    func test_coverage_twoDrivesBothNamedUntitled_differentUUIDs_isSafe() {
        let r = roll(copies: [copy("A", name: "Untitled"), copy("B", name: "Untitled")])
        XCTAssertEqual(r.coverage, .safe(drives: 2))
    }

    func test_coverage_unverifiedCopyDoesNotCount() {
        let r = roll(copies: [copy("A"), copy("B", verified: false)])
        XCTAssertEqual(r.coverage, .single)
    }

    func test_merge_sameIdentity_upsertsCopyByDrive() {
        let first = roll(copies: [copy("A")])
        var merged = MediaCatalog.merge(first, into: [])
        merged = MediaCatalog.merge(roll(copies: [copy("B")]), into: merged)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].copies.count, 2)

        let later = Date(timeIntervalSince1970: 9_999)
        merged = MediaCatalog.merge(roll(copies: [copy("B", date: later)]), into: merged)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].copies.count, 2)
        XCTAssertEqual(merged[0].copies.first { $0.destVolumeUUID == "B" }?.date, later)
    }

    func test_merge_differentSourceUUID_sameRollName_keepsTwoRolls() {
        var merged = MediaCatalog.merge(roll(copies: [copy("A")], sourceUUID: "S1"), into: [])
        merged = MediaCatalog.merge(roll(copies: [copy("A")], sourceUUID: "S2"), into: merged)
        XCTAssertEqual(merged.count, 2)
    }

    func test_search_matchesBasenameCaseInsensitive() {
        let r = roll(copies: [copy("A")], files: [
            CatalogFile(relPath: "Clip/C0042.MP4", size: 1),
            CatalogFile(relPath: "Clip/C0043.MP4", size: 1),
        ])
        let hits = MediaCatalog.search("c0042", in: [r])
        XCTAssertEqual(hits.map(\.file.relPath), ["Clip/C0042.MP4"])
    }

    func test_search_emptyQuery_returnsNothing() {
        let r = roll(copies: [copy("A")], files: [CatalogFile(relPath: "C0042.MP4", size: 1)])
        XCTAssertTrue(MediaCatalog.search("  ", in: [r]).isEmpty)
        XCTAssertTrue(MediaCatalog.search("", in: [r]).isEmpty)
    }
}
