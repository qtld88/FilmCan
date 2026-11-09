import XCTest
@testable import FilmCan

@MainActor
final class QuickCopySessionDropTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("qc-drop-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    private func dir(_ name: String) throws -> String {
        let url = tmp.appendingPathComponent(name)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    private func file(_ name: String) throws -> String {
        let url = tmp.appendingPathComponent(name)
        try Data(repeating: 1, count: 16).write(to: url)
        return url.path
    }

    private func makeSession(_ paths: [String]) -> QuickCopySession {
        let storage = ConfigurationStorage(baseDirectory: tmp.appendingPathComponent("store"))
        let defaults = UserDefaults(suiteName: "qc-drop-\(UUID().uuidString)")!
        return QuickCopySession(paths: paths, storage: storage, defaults: defaults)
    }

    func test_addSources_appendsNewSkipsKnownDuplicatesAndMissing() throws {
        let a = try dir("A001")
        let b = try dir("A002")
        let wav = try file("take.wav")
        let session = makeSession([a])

        session.addSources([a, b, b, wav, tmp.appendingPathComponent("gone").path])

        XCTAssertEqual(session.form.items.map(\.path), [a, b, wav])
    }

    func test_addDestinations_acceptsFoldersOnly_noDuplicates() throws {
        let src = try dir("A001")
        let d1 = try dir("SSD1")
        let loose = try file("notes.txt")
        let session = makeSession([src])

        session.addDestinations([d1, loose, d1])
        session.addDestinations([d1])

        XCTAssertEqual(session.form.destinations, [d1])
    }
}
