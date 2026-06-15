import XCTest
@testable import FilmCan

final class C4HashTests: XCTestCase {
    func testReferenceVectors() {
        XCTAssertEqual(C4Hash.id(of: Data()),
            "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT")
        XCTAssertEqual(C4Hash.id(of: Data("foo".utf8)),
            "c45xZeXwMSpqXjpDumcHMA6mhoAmGHkUo7r9WmN2UgSEQzj9KjgseaQdkEJ11fGb5S1WEENcV3q8RFWwEeVpC7Fjk2")
        XCTAssertEqual(C4Hash.id(of: Data("hello world".utf8)),
            "c41yP4cqy7jmaRDzC2bmcGNZkuQb3VdftMk6YH7ynQ2Qw4zktKsyA9fk52xghNQNAdkpF9iFmFkKh2bNVG4kDWhsok")
        XCTAssertEqual(C4Hash.id(of: Data([1,2,3,4,5])),
            "c42c9enzsLCXc9UvruGATr2n7yJmqK8FpZ1TreU37q9YZhgPkfi8Gnvcc9zP9JVmN99mY2qqYtpdxf7ghFDAxtZYDT")
    }

    func testIDLengthIs90() {
        XCTAssertEqual(C4Hash.id(of: Data("anything".utf8)).count, 90)
    }
}
