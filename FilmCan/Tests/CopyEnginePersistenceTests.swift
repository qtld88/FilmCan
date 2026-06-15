import XCTest
@testable import FilmCan

final class CopyEnginePersistenceTests: XCTestCase {
    // A config saved by an older build may carry copyEngine = "rsync".
    // It must still decode (as the FilmCan engine) and never throw.
    func testLegacyRsyncOptionsDecodeAsCustom() throws {
        let json = #"{"copyEngine":"rsync","verificationMode":"fast"}"#.data(using: .utf8)!
        let options = try JSONDecoder().decode(RsyncOptions.self, from: json)
        XCTAssertEqual(options.copyEngine, .custom)
    }

    func testCopyEngineStillDecodesBothRawValues() throws {
        XCTAssertEqual(CopyEngine(rawValue: "rsync"), .rsync)
        XCTAssertEqual(CopyEngine(rawValue: "custom"), .custom)
    }
}
