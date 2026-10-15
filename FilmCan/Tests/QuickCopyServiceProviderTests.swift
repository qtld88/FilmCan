import XCTest
import AppKit
@testable import FilmCan

@MainActor
final class QuickCopyServiceProviderTests: XCTestCase {

    func test_paths_readsFileURLsFromPasteboard() throws {
        let board = NSPasteboard(name: NSPasteboard.Name("filmcan.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        let a = URL(fileURLWithPath: "/tmp/a folder")
        let b = URL(fileURLWithPath: "/tmp/b.mov")
        XCTAssertTrue(board.writeObjects([a as NSURL, b as NSURL]))
        XCTAssertEqual(QuickCopyServiceProvider.paths(from: board), ["/tmp/a folder", "/tmp/b.mov"])
    }

    func test_paths_emptyPasteboard_isEmpty() {
        let board = NSPasteboard(name: NSPasteboard.Name("filmcan.test.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        XCTAssertEqual(QuickCopyServiceProvider.paths(from: board), [])
    }
}
