import XCTest
@testable import FilmCan

@MainActor
final class CustomCopierServiceE2ETests: XCTestCase {
    private func makeTmpDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Skip policy

    func test_skipPolicy_doesNotOverwriteUnmanifestedFile() async throws {
        let tmp = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Named card folder: basename "A001" → files land at dst/A001/
        let card = tmp.appendingPathComponent("A001")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("source content".utf8).write(to: card.appendingPathComponent("clip.mov"))

        // Pre-existing file at exact destination path FanOutCopier would target
        let target = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("old content".utf8).write(to: target)

        let svc = CustomCopierService()
        _ = try await svc.runCopyFanOut(
            sources: [card.path],
            fanOutDestinations: [DestWriter.Config(destPath: dst.path, displayName: "dst",
                                                    verifyMode: .fast, requiresFullFsync: false)],
            configName: "",
            organizationPreset: nil,
            copyFolderContents: false,
            useHashListPrecheck: false,
            hashListPath: nil,
            fileOrdering: .defaultOrder,
            duplicatePolicy: .skip,
            duplicateCounterTemplate: "_001",
            duplicateResolver: nil,
            verifyMode: .fast,
            dryRun: false,
            hashListStyle: .ascMHL,
            progressHandler: nil
        )

        let content = try String(data: Data(contentsOf: target), encoding: .utf8)
        XCTAssertEqual(content, "old content", "skip policy must not overwrite pre-existing unmanifested file")
    }

    // MARK: - Overwrite policy

    func test_overwritePolicy_replacesUnmanifestedFile() async throws {
        let tmp = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let card = tmp.appendingPathComponent("A001")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("new content".utf8).write(to: card.appendingPathComponent("clip.mov"))

        let target = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("old content".utf8).write(to: target)

        let svc = CustomCopierService()
        _ = try await svc.runCopyFanOut(
            sources: [card.path],
            fanOutDestinations: [DestWriter.Config(destPath: dst.path, displayName: "dst",
                                                    verifyMode: .fast,
                                                    requiresFullFsync: false)],
            configName: "",
            organizationPreset: nil,
            copyFolderContents: false,
            useHashListPrecheck: false,
            hashListPath: nil,
            fileOrdering: .defaultOrder,
            duplicatePolicy: .overwrite,
            duplicateCounterTemplate: "_001",
            duplicateResolver: nil,
            verifyMode: .fast,
            dryRun: false,
            hashListStyle: .ascMHL,
            progressHandler: nil
        )

        let content = try String(data: Data(contentsOf: target), encoding: .utf8)
        XCTAssertEqual(content, "new content", "overwrite policy must replace the pre-existing file")
    }

    // MARK: - Increment policy

    func test_incrementPolicy_allInvariants() async throws {
        let tmp = try makeTmpDir()
        defer { try? FileManager.default.removeItem(at: tmp) }

        let card = tmp.appendingPathComponent("A001")
        let dst = tmp.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: card, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        try Data("source content".utf8).write(to: card.appendingPathComponent("clip.mov"))

        let original = dst.appendingPathComponent("A001/clip.mov")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("old content".utf8).write(to: original)

        let svc = CustomCopierService()
        _ = try await svc.runCopyFanOut(
            sources: [card.path],
            fanOutDestinations: [DestWriter.Config(destPath: dst.path, displayName: "dst",
                                                    verifyMode: .paranoid,
                                                    requiresFullFsync: false)],
            configName: "",
            organizationPreset: nil,
            copyFolderContents: false,
            useHashListPrecheck: false,
            hashListPath: nil,
            fileOrdering: .defaultOrder,
            duplicatePolicy: .increment,
            duplicateCounterTemplate: "_001",
            duplicateResolver: nil,
            verifyMode: .paranoid,
            dryRun: false,
            hashListStyle: .ascMHL,
            progressHandler: nil
        )

        let fm = FileManager.default
        // Suffix template "_001" inserts before extension: clip.mov → clip_001.mov
        let suffixed = dst.appendingPathComponent("A001/clip_001.mov")

        // Original must be untouched
        XCTAssertTrue(fm.fileExists(atPath: original.path), "original file must still exist")
        XCTAssertEqual(try String(data: Data(contentsOf: original), encoding: .utf8), "old content",
                       "original content must be unchanged")

        // Suffixed file must exist with source content
        XCTAssertTrue(fm.fileExists(atPath: suffixed.path), "suffixed file must exist at A001/clip_001.mov")
        XCTAssertEqual(try String(data: Data(contentsOf: suffixed), encoding: .utf8), "source content",
                       "suffixed file must contain source content")

        // MHL must reference the suffixed name (Task 2 fixed this)
        let ascmhlDir = dst.appendingPathComponent("A001/ascmhl")
        let mhlFiles = try fm.contentsOfDirectory(atPath: ascmhlDir.path)
            .filter { $0.hasSuffix(".mhl") }
        XCTAssertFalse(mhlFiles.isEmpty, "MHL must be written")
        if let mhlFile = mhlFiles.first {
            let mhlContent = try String(contentsOf: ascmhlDir.appendingPathComponent(mhlFile))
            XCTAssertTrue(mhlContent.contains("clip_001.mov"),
                          "MHL must reference the suffixed filename")
        }
    }
}
