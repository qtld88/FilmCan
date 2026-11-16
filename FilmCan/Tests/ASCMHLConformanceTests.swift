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
        if (try? which.run()) != nil {
            which.waitUntilExit()
            let p = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if which.terminationStatus == 0 && !p.isEmpty { return p }
        }
        // The test host does not inherit the shell PATH: look where pipx (CI) and
        // Homebrew put it.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/ascmhl", "/opt/homebrew/bin/ascmhl", "/usr/local/bin/ascmhl"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func testReferenceToolReadsAndVerifiesOurManifest() async throws {
        guard let tool = toolPath() else { throw XCTSkip("ascmhl CLI not installed (pip install ascmhl)") }
        let roll = FileManager.default.temporaryDirectory.appendingPathComponent("A001-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: roll, withIntermediateDirectories: true)
        let clip = roll.appendingPathComponent("clip.bin")
        try Data([1, 2, 3, 4, 5]).write(to: clip)
        guard let hex = Hashing.hash(for: clip, algorithm: .xxh128) else { throw XCTSkip("no libxxhash") }

        let w = try ASCMHLWriter(ascmhlDir: roll.appendingPathComponent("ascmhl"), rollName: "A001")
        try await w.append(relPath: "clip.bin", size: 5, hash: hex, mtime: nil)
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

    /// Three runs on one roll: a sealed generation, a cancelled (partial) one, then a
    /// complete one carrying the earlier entries. Every entry has a modification date.
    func testReferenceToolAcceptsPartialThenCompleteGenerationsWithDates() async throws {
        guard let tool = toolPath() else { throw XCTSkip("ascmhl CLI not installed (pip install ascmhl)") }
        let fm = FileManager.default
        let roll = fm.temporaryDirectory.appendingPathComponent("A002-\(UUID().uuidString)")
        try fm.createDirectory(at: roll, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: roll) }
        func clip(_ name: String, _ bytes: [UInt8]) throws -> MHLEntry {
            let url = roll.appendingPathComponent(name)
            try Data(bytes).write(to: url)
            guard let hex = Hashing.hash(for: url, algorithm: .xxh128) else { throw XCTSkip("no libxxhash") }
            let mtime = try fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            return MHLEntry(relPath: name, size: Int64(bytes.count), hash: hex,
                            mtime: mtime.map { Int64($0.timeIntervalSince1970) })
        }
        let ascDir = roll.appendingPathComponent("ascmhl")
        let c1 = try clip("clip1.bin", [1, 2, 3]), c2 = try clip("clip2.bin", [4, 5, 6]), c3 = try clip("clip3.bin", [7, 8])

        let g1 = try ASCMHLWriter(ascmhlDir: ascDir, rollName: "A002")
        try await g1.append(relPath: c1.relPath, size: c1.size, hash: c1.hash, mtime: c1.mtime)
        try await g1.seal()

        let g2 = try ASCMHLWriter(ascmhlDir: ascDir, rollName: "A002")
        await g2.seed([c1])
        try await g2.append(relPath: c2.relPath, size: c2.size, hash: c2.hash, mtime: c2.mtime)
        try await g2.finalizeAsPartial(reason: "cancelled")

        let g3 = try ASCMHLWriter(ascmhlDir: ascDir, rollName: "A002")
        let carried = try ASCMHLReader.read(url: URL(fileURLWithPath: g2.manifestPath))
        await g3.seed(carried.map { MHLEntry(relPath: $0.relPath, size: $0.size ?? 0, hash: $0.hash, mtime: $0.mtime) })
        try await g3.append(relPath: c3.relPath, size: c3.size, hash: c3.hash, mtime: c3.mtime)
        try await g3.seal()

        let diff = Process()
        diff.executableURL = URL(fileURLWithPath: tool)
        diff.arguments = ["diff", roll.path]
        let out = Pipe(); diff.standardOutput = out; diff.standardError = out
        try diff.run(); diff.waitUntilExit()
        let log = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(diff.terminationStatus, 0, "ascmhl diff rejected our generations:\n\(log)")
        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: ascDir).map(\.seq), [1, 2])
    }
}
