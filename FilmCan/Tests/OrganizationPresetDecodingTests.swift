import XCTest
@testable import FilmCan

final class OrganizationPresetDecodingTests: XCTestCase {

    func test_oldJSONWithoutNewFields_decodesWithDefaults() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","folderTemplate":"{date}/{source}","useFolderTemplate":true}"#
        let p = try JSONDecoder().decode(OrganizationPreset.self, from: Data(json.utf8))
        XCTAssertEqual(p.projectName, "")
        XCTAssertEqual(p.hashListStyle, .ascMHL)
        XCTAssertEqual(p.folderTemplate, "{date}/{source}")
        XCTAssertTrue(p.useFolderTemplate)
    }

    func test_newFields_roundTrip() throws {
        var p = OrganizationPreset()
        p.projectName = "Docu_Truc"
        p.hashListStyle = .simpleHidden
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(OrganizationPreset.self, from: data)
        XCTAssertEqual(back.projectName, "Docu_Truc")
        XCTAssertEqual(back.hashListStyle, .simpleHidden)
    }
}
