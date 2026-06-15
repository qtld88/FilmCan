import XCTest
@testable import FilmCan

final class ASCMHLConformanceTests: XCTestCase {
    func testReferenceToolVerifiesOurManifest() async throws {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "ascmhl"]
        let pipe = Pipe(); which.standardOutput = pipe
        try? which.run(); which.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard which.terminationStatus == 0, !path.isEmpty else {
            throw XCTSkip("ascmhl CLI not installed (pip install ascmhl)")
        }
        let roll = FileManager.default.temporaryDirectory.appendingPathComponent("A001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        let clip = roll.appendingPathComponent("clip.bin")
        try Data([1,2,3,4,5]).write(to: clip)
        guard let hex = Hashing.hash(for: clip, algorithm: .xxh128) else { throw XCTSkip("no libxxhash") }
        let w = try ASCMHLWriter(url: roll.appendingPathComponent("ascmhl/0001_A001.mhl"), rollName: "A001")
        try await w.append(relPath: "clip.bin", size: 5, hash: hex)
        try await w.seal()
        let verify = Process()
        verify.executableURL = URL(fileURLWithPath: path)
        verify.arguments = ["verify", roll.path]
        try verify.run(); verify.waitUntilExit()
        XCTAssertEqual(verify.terminationStatus, 0, "ascmhl verify rejected our manifest")
    }
}
