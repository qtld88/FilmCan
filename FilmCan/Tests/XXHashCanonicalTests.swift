import XCTest
@testable import FilmCan

final class XXHashCanonicalTests: XCTestCase {
    private func hashHex(of bytes: [UInt8]) throws -> String {
        guard let hasher = XXH128StreamingHasher() else {
            throw XCTSkip("libxxhash unavailable")
        }
        hasher.update(data: Data(bytes))
        return hasher.finalize().hexString
    }

    // Reference values from `xxh128sum` (canonical xxh128, seed 0).
    func testCanonicalVectors() throws {
        XCTAssertEqual(try hashHex(of: []),
                       "99aa06d3014798d86001c324468d497f")
        XCTAssertEqual(try hashHex(of: Array("foo".utf8)),
                       "79aef92e83454121ab6e5f64077e7d8a")
        XCTAssertEqual(try hashHex(of: Array("hello world".utf8)),
                       "df8d09e93f874900a99b8775cc15b6c7")
        XCTAssertEqual(try hashHex(of: [1, 2, 3, 4, 5]),
                       "13d8ee1d6dd32c9c244bd8eab1d14be3")
    }
}
