import XCTest
@testable import FilmCan

final class MediaKindGuesserTests: XCTestCase {
    var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func touch(_ rel: String) throws {
        let url = tmp.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([0]).write(to: url)
    }

    func test_audioMajorityFolder_isSound() throws {
        for n in ["a.wav", "b.WAV", "c.bwf", "d.mov"] { try touch("ZOOM/\(n)") }
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("ZOOM").path), .sound)
    }

    func test_mixedFolder_halfAudio_isCamera() throws {
        for n in ["a.wav", "b.wav", "c.mov", "d.mov"] { try touch("MIX/\(n)") }
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("MIX").path), .camera)
    }

    func test_videoFolder_isCamera() throws {
        for n in ["a.mov", "b.braw", "c.r3d"] { try touch("A001/\(n)") }
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("A001").path), .camera)
    }

    func test_singleFiles_classifiedByOwnExtension() throws {
        try touch("take.flac")
        try touch("clip.mov")
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("take.flac").path), .sound)
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("clip.mov").path), .camera)
    }

    func test_hiddenFilesIgnored() throws {
        try touch("S/real.wav")
        for n in ["._a.mov", ".b.mov", ".c.mov"] { try touch("S/\(n)") }
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("S").path), .sound)
    }

    func test_symlinkedFolder_isFollowed() throws {
        for n in ["a.wav", "b.wav", "c.bwf"] { try touch("REAL/\(n)") }
        let link = tmp.appendingPathComponent("LINK")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: tmp.appendingPathComponent("REAL"))
        XCTAssertEqual(MediaKindGuesser.guess(path: link.path), .sound)
    }

    func test_emptyAndMissing_areCamera() throws {
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("EMPTY"), withIntermediateDirectories: true)
        XCTAssertEqual(MediaKindGuesser.guess(path: tmp.appendingPathComponent("EMPTY").path), .camera)
        XCTAssertEqual(MediaKindGuesser.guess(path: "/nonexistent/\(UUID().uuidString)"), .camera)
    }
}
