import XCTest
@testable import FilmCan

/// Two source roots that share a basename (e.g. two cards both named "DJI") must map
/// to DISTINCT roll-folder names, or they merge into one `<dest>/DJI/` sharing one
/// `ascmhl/` — conflating two cards into one roll. `disambiguatedRootNames` assigns a
/// deterministic, resume-stable unique name per distinct source root.
final class RootDisambiguationTests: XCTestCase {

    func test_uniqueBasenames_unchanged() {
        let map = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/CARD1", "/b/CARD2"])
        XCTAssertEqual(map["/a/CARD1"], "CARD1")
        XCTAssertEqual(map["/b/CARD2"], "CARD2")
    }

    func test_collidingBasenames_secondGetsSuffix() {
        let map = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/DJI", "/b/DJI"])
        // Sorted by path: /a/DJI keeps the clean name, /b/DJI is suffixed.
        XCTAssertEqual(map["/a/DJI"], "DJI")
        XCTAssertEqual(map["/b/DJI"], "DJI-2")
    }

    func test_tripleCollision_incrementsSuffix() {
        let map = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/DJI", "/b/DJI", "/c/DJI"])
        XCTAssertEqual(Set([map["/a/DJI"], map["/b/DJI"], map["/c/DJI"]]),
                       Set(["DJI", "DJI-2", "DJI-3"]))
    }

    func test_literalSuffixAlreadyPresent_stillAllUnique() {
        let map = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/DJI", "/b/DJI", "/c/DJI-2"])
        let names = ["/a/DJI", "/b/DJI", "/c/DJI-2"].compactMap { map[$0] }
        XCTAssertEqual(Set(names).count, 3, "every distinct root must get a unique name")
    }

    func test_deterministic_orderIndependent() {
        let a = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/DJI", "/b/DJI"])
        let b = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/b/DJI", "/a/DJI"])
        XCTAssertEqual(a, b, "same roots in any input order yield the same mapping")
    }

    func test_duplicatePaths_collapse() {
        let map = FanOutCopier.disambiguatedRootNames(sourceRoots: ["/a/DJI", "/a/DJI"])
        XCTAssertEqual(map.count, 1)
        XCTAssertEqual(map["/a/DJI"], "DJI")
    }
}
