import XCTest
@testable import FilmCan

/// Validates that FilmCan's ASC MHL output is accepted by the reference `ascmhl`
/// tool. Self-skips unless `ascmhl` is on PATH. To run: install it in a venv and put
/// its bin on PATH, e.g. `PATH="/tmp/ascv/bin:$PATH" xcodebuild test ...`
/// (`python3 -m venv /tmp/ascv && /tmp/ascv/bin/pip install ascmhl`).
final class ASCMHLConformanceTests: XCTestCase {
    private func toolPath() -> String? {
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        which.arguments = ["which", "ascmhl"]
        let pipe = Pipe(); which.standardOutput = pipe
        try? which.run(); which.waitUntilExit()
        let p = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (which.terminationStatus == 0 && !p.isEmpty) ? p : nil
    }

    func testReferenceToolReadsAndVerifiesOurManifest() async throws {
        guard let tool = toolPath() else { throw XCTSkip("ascmhl CLI not installed (pip install ascmhl)") }
        let roll = FileManager.default.temporaryDirectory.appendingPathComponent("A001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        let clip = roll.appendingPathComponent("clip.bin")
        try Data([1, 2, 3, 4, 5]).write(to: clip)
        guard let hex = Hashing.hash(for: clip, algorithm: .xxh128) else { throw XCTSkip("no libxxhash") }

        let w = try ASCMHLWriter(ascmhlDir: roll.appendingPathComponent("ascmhl"), rollName: "A001")
        try await w.append(relPath: "clip.bin", size: 5, hash: hex)
        try await w.seal()

        // `ascmhl diff` re-reads the folder against our chain+manifest and reports a
        // non-zero exit if anything fails to parse or a hash mismatches.
        let diff = Process()
        diff.executableURL = URL(fileURLWithPath: tool)
        diff.arguments = ["diff", roll.path]
        let out = Pipe(); diff.standardOutput = out; diff.standardError = out
        try diff.run(); diff.waitUntilExit()
        let log = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(diff.terminationStatus, 0, "ascmhl diff rejected our output:\n\(log)")
    }
}
