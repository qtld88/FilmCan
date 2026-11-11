import XCTest
@testable import FilmCan

final class FolderTreeBuilderTests: XCTestCase {

    private var date: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 14; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    private func options(copyContents: Bool = false) -> FolderTreeBuilder.Options {
        var preset = OrganizationPreset.netflixIngest()
        preset.useFolderTemplate = true
        var o = FolderTreeBuilder.Options()
        o.preset = preset
        o.mediaIndexPreset = preset
        o.organizationActive = true
        o.copyContents = copyContents
        o.date = date
        o.metadata = ShootMetadata(episode: "Docu", day: "D01", unit: "A", cameraFormat: "ARRI")
        o.pathExists = { _ in false }
        return o
    }

    func test_netflixConfig_cameraAndSoundSourcesShareDayFolder() {
        let sources = [
            FolderTreeBuilder.Source(path: "/Volumes/CARD/A001", isDirectory: true, kind: .camera),
            FolderTreeBuilder.Source(path: "/Volumes/CARD/S001", isDirectory: true, kind: .sound)
        ]
        let lines = FolderTreeBuilder.lines(for: "/Volumes/SSD", sources: sources, options: options())
        XCTAssertEqual(lines.first?.depth, 0)
        XCTAssertEqual(lines.first?.isRoot, true)
        XCTAssertEqual(lines.filter(\.isRoot).count, 1)
        XCTAssertTrue(lines.contains { $0.name == "Sound_Media" })
        XCTAssertEqual(lines.filter { $0.role == .copiedFolder }.count, 2)
    }

    func test_copyContents_addsContentsLineWithoutHashListLine() {
        let sources = [FolderTreeBuilder.Source(path: "/Volumes/CARD/A001", isDirectory: true)]
        let lines = FolderTreeBuilder.lines(for: "/Volumes/SSD", sources: sources,
                                            options: options(copyContents: true))
        XCTAssertEqual(lines.last?.name, "contents of A001")
        XCTAssertFalse(lines.contains { $0.name.contains("hash list") })
    }

    func test_noPreset_isJustTheSource() {
        var o = FolderTreeBuilder.Options()
        o.pathExists = { _ in false }
        let sources = [FolderTreeBuilder.Source(path: "/Volumes/CARD/A001", isDirectory: true)]
        let lines = FolderTreeBuilder.lines(for: "/Volumes/SSD", sources: sources, options: o)
        XCTAssertEqual(lines.map(\.name), ["A001"])
        XCTAssertEqual(lines.first?.role, .copiedFolder)
    }

    func test_rollName_replacesTheCardName() {
        var o = FolderTreeBuilder.Options()
        o.pathExists = { _ in false }
        let sources = [FolderTreeBuilder.Source(path: "/Volumes/Untitled", isDirectory: true, rollName: "Untitled_01")]
        let lines = FolderTreeBuilder.lines(for: "/Volumes/SSD", sources: sources, options: o)
        XCTAssertEqual(lines.map(\.name), ["Untitled_01"])
        XCTAssertEqual(lines.first?.role, .copiedFolder)
    }

    func test_rollName_inContentsMode_keepsTheRollFolder() {
        let sources = [FolderTreeBuilder.Source(path: "/Volumes/Untitled", isDirectory: true, rollName: "Untitled_01")]
        let lines = FolderTreeBuilder.lines(for: "/Volumes/SSD", sources: sources,
                                            options: options(copyContents: true))
        XCTAssertTrue(lines.contains { $0.name == "Untitled_01" && $0.role == .copiedFolder })
        XCTAssertFalse(lines.contains { $0.role == .contents })
    }
}
