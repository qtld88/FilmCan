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
}
