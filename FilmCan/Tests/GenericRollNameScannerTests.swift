import XCTest
@testable import FilmCan

final class GenericRollNameScannerTests: XCTestCase {
    private let fm = FileManager.default
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("gen-scan-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? fm.removeItem(at: tmp)
    }

    private func mkdir(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func test_noPreset_listsDestinationRootEntries() throws {
        let dest = tmp.appendingPathComponent("dest")
        try mkdir(dest.appendingPathComponent("Untitled_01"))
        try mkdir(dest.appendingPathComponent("Other"))
        let names = GenericRollNameScanner.existingNames(
            source: "/Volumes/Untitled", destinations: [dest.path], preset: nil,
            date: Date(), metadata: .empty, mediaKind: .camera)
        XCTAssertEqual(Set(names), ["Untitled_01", "Other"])
    }

    func test_netflixPreset_listsTheCameraMediaParent() throws {
        let dest = tmp.appendingPathComponent("dest")
        var preset = OrganizationPreset.netflixIngest()
        preset.useFolderTemplate = true
        let metadata = ShootMetadata(episode: "Docu", day: "D01", unit: "A", cameraFormat: "ARRI")
        let date = Date()
        let roll = FanOutCopier.resolveRollFolder(
            destRoot: dest.path, rootName: "Untitled", rootPath: "/Volumes/Untitled",
            isDirectoryRoot: true, preset: preset, copyFolderContents: false,
            date: date, metadata: metadata, mediaKind: .camera, rollNameIsAssigned: true)
        let parent = URL(fileURLWithPath: roll).deletingLastPathComponent()
        try mkdir(parent.appendingPathComponent("Untitled_01"))
        try mkdir(dest.appendingPathComponent("Unrelated"))
        let names = GenericRollNameScanner.existingNames(
            source: "/Volumes/Untitled", destinations: [dest.path], preset: preset,
            date: date, metadata: metadata, mediaKind: .camera)
        XCTAssertEqual(names, ["Untitled_01"])
    }

    func test_missingDirectory_isEmpty() {
        let names = GenericRollNameScanner.existingNames(
            source: "/Volumes/Untitled", destinations: [tmp.appendingPathComponent("nope").path],
            preset: nil, date: Date(), metadata: .empty, mediaKind: .camera)
        XCTAssertEqual(names, [])
    }

    func test_unionsAcrossDestinations() throws {
        let a = tmp.appendingPathComponent("a")
        let b = tmp.appendingPathComponent("b")
        try mkdir(a.appendingPathComponent("Untitled_01"))
        try mkdir(b.appendingPathComponent("Untitled_02"))
        let names = GenericRollNameScanner.existingNames(
            source: "/Volumes/Untitled", destinations: [a.path, b.path], preset: nil,
            date: Date(), metadata: .empty, mediaKind: .camera)
        XCTAssertEqual(Set(names), ["Untitled_01", "Untitled_02"])
    }
}
