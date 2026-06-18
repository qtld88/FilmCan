import XCTest
@testable import FilmCan

final class RobustnessTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: - Task 1: Enumeration surfaces unreadable dirs

    func test_enumeration_reportsUnreadableDirectory() async throws {
        if getuid() == 0 { throw XCTSkip("perms not enforced as root") }
        let root = tempDir()
        let locked = root.appendingPathComponent("locked")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("ok.mov"))
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data([4, 5, 6]).write(to: locked.appendingPathComponent("inside.mov"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let result = await FileEnumerator.enumerateFiles(sources: [root.path], preset: nil)
        XCTAssertTrue(result.entries.contains { $0.relativePath == "ok.mov" })
        XCTAssertFalse(result.unreadable.isEmpty, "unreadable directory must be reported")
    }

    // MARK: - Task 2: ConfigurationStorage surfaces save failure

    func test_save_reportsFailureOnUnwritableDir() throws {
        if getuid() == 0 { throw XCTSkip("perms not enforced as root") }
        let ro = tempDir()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ro.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path) }

        let storage = ConfigurationStorage(baseDirectory: ro)
        let ok = storage.save()
        XCTAssertFalse(ok, "save into a read-only dir must report failure")
        XCTAssertNotNil(storage.lastSaveError)
    }

    // MARK: - Task 3: DryRun honors exclude filter

    func test_dryRun_honorsExcludeFilter() async throws {
        let src = tempDir()
        let dst = tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }
        try Data([1]).write(to: src.appendingPathComponent("keep.mov"))
        try Data([1]).write(to: src.appendingPathComponent("skip.tmp"))
        var preset = OrganizationPreset()
        preset.excludePatterns = ["*.tmp"]

        let planner = DryRunPlanner()
        let report = try await planner.plan(
            sourcePaths: [src.path],
            destinations: [],
            preset: preset
        )
        XCTAssertFalse(report.plannedRelPaths.contains("skip.tmp"), "excluded file must not be planned")
        XCTAssertTrue(report.plannedRelPaths.contains("keep.mov"))
    }

    // MARK: - Task 4: RunContext round-trips through history

    func test_repairContext_roundTripsThroughHistory() throws {
        let snapshot = TransferOptionsSnapshot(config: BackupConfiguration(), presetName: nil)
        var entry = TransferHistoryEntry(
            configId: nil,
            configName: "test",
            startedAt: Date(),
            endedAt: Date(),
            success: true,
            sources: [],
            destinations: [],
            results: [],
            options: snapshot,
            hashListPath: nil
        )
        let presetId = UUID()
        entry.runContext = RunContext(
            organizationPresetId: presetId,
            cameraFolderTemplate: "{date}_{episode}/Camera_Media/{cameraFormat}",
            soundFolderTemplate: "{date}_{episode}/Sound_Media",
            copyFolderContents: true,
            sourceMediaKinds: ["/Volumes/SR001": .sound],
            duplicatePolicy: .skip,
            hashListStyle: .ascMHL
        )
        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(TransferHistoryEntry.self, from: data)
        XCTAssertEqual(decoded.runContext?.copyFolderContents, true)
        XCTAssertEqual(decoded.runContext?.sourceMediaKinds["/Volumes/SR001"], .sound)
        XCTAssertEqual(decoded.runContext?.duplicatePolicy, .skip)
        XCTAssertEqual(decoded.runContext?.organizationPresetId, presetId)
    }
}
