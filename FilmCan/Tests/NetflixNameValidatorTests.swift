import XCTest
@testable import FilmCan

final class NetflixNameValidatorTests: XCTestCase {
    func testFlagsProhibitedChars() {
        let issues = NetflixNameValidator.validate(rollNames: ["A001", "B:02", "C#3"])
        XCTAssertTrue(issues.contains { if case .prohibitedChars(let n, _) = $0 { return n == "B:02" } else { return false } })
        XCTAssertTrue(issues.contains { if case .prohibitedChars(let n, _) = $0 { return n == "C#3" } else { return false } })
        XCTAssertFalse(issues.contains { if case .prohibitedChars(let n, _) = $0 { return n == "A001" } else { return false } })
    }

    func testFlagsDuplicateRolls() {
        let issues = NetflixNameValidator.validate(rollNames: ["A001", "A001", "A002"])
        XCTAssertEqual(issues.filter { if case .duplicateRoll = $0 { return true } else { return false } }.count, 1)
    }

    func testSanitizeReplacesProhibited() {
        XCTAssertEqual(NetflixNameValidator.sanitize("A:00#1"), "A_00_1")
        XCTAssertEqual(NetflixNameValidator.sanitize("A001"), "A001")
    }
}
