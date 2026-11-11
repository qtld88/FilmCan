import XCTest
@testable import FilmCan

final class GenericCardNameTests: XCTestCase {

    func test_listMatch_isCaseInsensitive() {
        for name in ["Untitled", "UNTITLED", "untitled", "No Name", "dji", "EOS_DIGITAL", "dcim"] {
            XCTAssertTrue(GenericCardName.isGeneric(name), name)
        }
    }

    func test_macOSSuffix_isStripped() {
        XCTAssertTrue(GenericCardName.isGeneric("Untitled 1"))
        XCTAssertEqual(GenericCardName.baseName("Untitled 1"), "Untitled")
        XCTAssertEqual(GenericCardName.baseName("Untitled"), "Untitled")
    }

    func test_realReelNames_areNotGeneric() {
        for name in ["A001R2EC", "A001_C002", "S001", "MyCard", "Untitled_01"] {
            XCTAssertFalse(GenericCardName.isGeneric(name), name)
        }
    }

    func test_nextNumberedName_noneTaken() {
        XCTAssertEqual(GenericCardName.nextNumberedName(base: "Untitled", taken: []), "Untitled_01")
        XCTAssertEqual(GenericCardName.nextNumberedName(base: "Untitled", taken: ["Other", "Untitled"]), "Untitled_01")
    }

    func test_nextNumberedName_usesMaxPlusOne_notFirstGap() {
        XCTAssertEqual(GenericCardName.nextNumberedName(base: "Untitled", taken: ["Untitled_01", "Untitled_03"]),
                       "Untitled_04")
    }

    func test_nextNumberedName_mixedCase_andOtherSources() {
        XCTAssertEqual(GenericCardName.nextNumberedName(
            base: "Untitled", taken: ["Untitled_01", "untitled_03", "Other"]), "Untitled_04")
        XCTAssertEqual(GenericCardName.nextNumberedName(
            base: "DJI", taken: ["DJI_01", "DJI_02"]), "DJI_03")
    }

    func test_nextNumberedName_growsPastTwoDigits() {
        XCTAssertEqual(GenericCardName.nextNumberedName(base: "DJI", taken: ["DJI_99"]), "DJI_100")
    }
}
