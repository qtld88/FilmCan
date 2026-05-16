import XCTest
@testable import FilmCan

final class MHLWriterTests: XCTestCase {
    func test_writeAndFlush_createsValidXML() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mhl")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MHLWriter(url: url, sourceName: "FilmCan_v1.0.dmg")
        try await writer.append(hash: "aaa", fileName: "file1.bin")
        try await writer.append(hash: "bbb", fileName: "file2.bin")
        try await writer.flush()
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains("<?xml"))
        XCTAssertTrue(xml.contains("<hash>aaa</hash>"))
        XCTAssertTrue(xml.contains("<hash>bbb</hash>"))
        XCTAssertTrue(xml.contains("</hashlist>"))
    }

    func test_writeWithoutFlush_noFileOnDisk() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mhl")
        let writer = try MHLWriter(url: url, sourceName: "File.dmg")
        try await writer.append(hash: "ccc", fileName: "f.dat")
        try await writer.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_emptyWriter_onFlush_producesValidXML() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).mhl")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MHLWriter(url: url, sourceName: "Empty.dmg")
        try await writer.flush()
        let xml = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(xml.contains("<hashlist"))
        XCTAssertTrue(xml.contains("</hashlist>"))
    }
}
