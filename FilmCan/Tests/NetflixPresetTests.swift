import XCTest
@testable import FilmCan

final class NetflixPresetTests: XCTestCase {
    func testNetflixPresetTemplate() {
        let p = OrganizationPreset.netflixIngest()
        XCTAssertEqual(p.name, "Netflix Ingest")
        XCTAssertTrue(p.useFolderTemplate)
        XCTAssertEqual(p.folderTemplate, "{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}")
    }

    func testScaffoldCreatesReportsAndSoundMedia() throws {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("nf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let rollFolder = dest.appendingPathComponent("20260615_EP103_Day05_MU/Camera_Media/ARRI/A001").path
        FanOutCopier.scaffoldNetflixSiblings(destRoot: dest.path, rollFolder: rollFolder)
        let dayRoot = dest.appendingPathComponent("20260615_EP103_Day05_MU")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dayRoot.appendingPathComponent("Reports").path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dayRoot.appendingPathComponent("Sound_Media").path, isDirectory: &isDir) && isDir.boolValue)
    }
}
