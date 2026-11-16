import XCTest
@testable import FilmCan

/// Two cards that both mount as "Untitled": the second one, plugged in at the same
/// path after the first was ejected, must get its own numbered roll folder.
final class GenericRollNamingTests: XCTestCase {
    private let path = "/Volumes/Untitled"

    private func suggest(takenOnDrive: [String]) -> (String, [String: String]) -> String {
        { path, names in
            GenericCardName.nextNumberedName(
                base: GenericCardName.baseName((path as NSString).lastPathComponent),
                taken: takenOnDrive + Array(names.values))
        }
    }

    func test_secondUntitledCard_atSamePath_getsNextNumber() {
        // First card was named and backed up as Untitled_01.
        let existing = ["uuid-A|": "Untitled_01"]
        // The second card mounts at the same path: same source list, new card key.
        let added = GenericRollNaming.namesToFill(
            sources: [path], isGeneric: { _ in true }, keyFor: { _ in "uuid-B|" },
            existing: existing, userEdited: [],
            suggest: suggest(takenOnDrive: ["Untitled_01"]))
        XCTAssertEqual(added, ["uuid-B|": "Untitled_02"])
    }

    func test_sameCardBack_keepsItsName() {
        let added = GenericRollNaming.namesToFill(
            sources: [path], isGeneric: { _ in true }, keyFor: { _ in "uuid-A|" },
            existing: ["uuid-A|": "Untitled_01"], userEdited: [],
            suggest: suggest(takenOnDrive: ["Untitled_01"]))
        XCTAssertTrue(added.isEmpty)
    }

    func test_cardNamedByHand_isNeverRefilled() {
        let added = GenericRollNaming.namesToFill(
            sources: [path], isGeneric: { _ in true }, keyFor: { _ in "uuid-B|" },
            existing: [:], userEdited: ["uuid-B|"],
            suggest: suggest(takenOnDrive: []))
        XCTAssertTrue(added.isEmpty)
    }

    func test_twoNewCardsInOnePass_getDistinctNumbers() {
        let sources = ["/Volumes/Untitled", "/Volumes/Untitled 1"]
        let keys = ["/Volumes/Untitled": "uuid-C|", "/Volumes/Untitled 1": "uuid-D|"]
        let added = GenericRollNaming.namesToFill(
            sources: sources, isGeneric: { _ in true }, keyFor: { keys[$0]! },
            existing: ["uuid-A|": "Untitled_01"], userEdited: [],
            suggest: suggest(takenOnDrive: ["Untitled_01"]))
        XCTAssertEqual(Set(added.values), ["Untitled_02", "Untitled_03"])
    }

    func test_nonGenericSource_isIgnored() {
        let added = GenericRollNaming.namesToFill(
            sources: ["/Volumes/A001"], isGeneric: { _ in false }, keyFor: { _ in "uuid-E|" },
            existing: [:], userEdited: [],
            suggest: suggest(takenOnDrive: []))
        XCTAssertTrue(added.isEmpty)
    }
}
