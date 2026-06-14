import XCTest
import SwiftUI
@testable import FilmCan

final class SettingsDrawerLayoutTests: XCTestCase {
    func testFolderTabShapeChamfersTopCorners() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let shape = FolderTabShape(chamfer: 10)
        let path = shape.path(in: rect)
        XCTAssertEqual(path.boundingRect.maxY, 40, accuracy: 0.01)
        XCTAssertEqual(path.boundingRect.width, 100, accuracy: 0.01)
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 1)))
    }

    func testFolderTabShapeZeroChamferIsRectangle() {
        let rect = CGRect(x: 0, y: 0, width: 80, height: 30)
        let path = FolderTabShape(chamfer: 0).path(in: rect)
        XCTAssertTrue(path.contains(CGPoint(x: 1, y: 1)))
    }

    func testOpenCapWideUses45Percent() {
        XCTAssertEqual(SettingsDrawerLayout.openCap(windowHeight: 1000, isWide: true),
                       450, accuracy: 0.01)
    }

    func testOpenCapNarrowUses55Percent() {
        XCTAssertEqual(SettingsDrawerLayout.openCap(windowHeight: 1000, isWide: false),
                       550, accuracy: 0.01)
    }

    func testOpenCapFloorsToReasonableMinimum() {
        XCTAssertEqual(SettingsDrawerLayout.openCap(windowHeight: 100, isWide: true),
                       160, accuracy: 0.01)
    }
}
