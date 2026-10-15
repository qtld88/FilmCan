import XCTest
@testable import FilmCan

@MainActor
final class QuickCopyIntegrationTests: XCTestCase {
    var tmp: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("qc-int-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    // MARK: helpers
    @discardableResult
    private func write(_ rel: String, bytes: Int = 4096) throws -> URL {
        let url = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        return url
    }

    private func makeDir(_ rel: String) throws -> URL {
        let url = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    /// Same engine call `TransferViewModel.runFanOut` makes, minus UI plumbing.
    private func runEngine(config: BackupConfiguration,
                           preset: OrganizationPreset?) async throws -> TransferResult {
        let service = CustomCopierService()
        let mode = config.engineOptions.verificationMode
        let dests = config.destinationPaths.map {
            DestWriter.Config(destPath: $0, displayName: ($0 as NSString).lastPathComponent,
                              verifyMode: mode, requiresFullFsync: false, chunkSize: 65536)
        }
        return try await service.runCopyFanOut(
            sources: config.sourcePaths, fanOutDestinations: dests, configName: config.name,
            organizationPreset: preset, copyFolderContents: config.copyFolderContents,
            useHashListPrecheck: config.engineOptions.customVerifyEnabled, hashListPath: nil,
            fileOrdering: config.engineOptions.fileOrdering, duplicatePolicy: config.duplicatePolicy,
            duplicateCounterTemplate: config.duplicateCounterTemplate, duplicateResolver: nil,
            verifyMode: mode, dryRun: false,
            shootMetadata: ShootMetadata(episode: config.episode, day: config.day,
                                         unit: config.unit, cameraFormat: config.cameraFormat),
            sourceMediaKinds: config.sourceMediaKinds, hashListStyle: config.hashListStyle,
            reVerifyExistingOnResume: config.reVerifyExistingOnResume,
            unreadableHandler: nil, rollIdentityHandler: nil, progressHandler: nil)
    }

    private func tree(of root: URL) -> [String] {
        guard let e = fm.enumerator(atPath: root.path) else { return [] }
        var out: [String] = []
        while let p = e.nextObject() as? String { out.append(p) }
        return out.sorted()
    }

    // MARK: tests
    func test_projectAndDay_routesCameraAndSound_toTwoDestinations() async throws {
        let cam = try makeDir("src/A001")
        try write("src/A001/clip1.mov")
        let snd = try makeDir("src/ZOOM_F8")
        try write("src/ZOOM_F8/take1.wav")
        let d1 = try makeDir("d1"), d2 = try makeDir("d2")

        var form = QuickCopyFormModel(items: [
            .init(path: cam.path, isDirectory: true, kind: .camera),
            .init(path: snd.path, isDirectory: true, kind: .sound)])
        form.destinations = [d1.path, d2.path]
        form.organization = .projectAndDay
        form.project = "Docu Truc"
        form.day = "itw Machin"
        form.pickedDate = date(2026, 10, 14)

        let result = try await runEngine(config: form.makeConfiguration(), preset: form.runPreset())

        XCTAssertEqual(result.destinationResults.count, 2)
        XCTAssertTrue(result.destinationResults.allSatisfy { $0.success })
        for dest in [d1, d2] {
            let day = dest.appendingPathComponent("20261014_Docu_Truc_itw_Machin")
            XCTAssertTrue(fm.fileExists(atPath: day.appendingPathComponent("Camera_Media/A001/clip1.mov").path))
            XCTAssertTrue(fm.fileExists(atPath: day.appendingPathComponent("Sound_Media/ZOOM_F8/take1.wav").path))
            XCTAssertTrue(fm.fileExists(atPath: day.appendingPathComponent("Camera_Media/A001/ascmhl").path))
            XCTAssertTrue(fm.fileExists(atPath: day.appendingPathComponent("Sound_Media/ZOOM_F8/ascmhl").path))
        }
    }

    func test_noOrganization_copiesFolderAsIs() async throws {
        let src = try makeDir("src/A001")
        try write("src/A001/clip1.mov")
        let dest = try makeDir("dest")
        var form = QuickCopyFormModel(items: [.init(path: src.path, isDirectory: true, kind: .camera)])
        form.destinations = [dest.path]
        let result = try await runEngine(config: form.makeConfiguration(), preset: form.runPreset())
        XCTAssertTrue(result.destinationResults.allSatisfy { $0.success })
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A001/clip1.mov").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("A001/ascmhl").path))
    }

    func test_singleLooseFile_copiesAndWritesOneManifest() async throws {
        let file = try write("src/take1.wav")
        let dest = try makeDir("dest")
        var form = QuickCopyFormModel(items: [.init(path: file.path, isDirectory: false, kind: .sound)])
        form.destinations = [dest.path]
        let result = try await runEngine(config: form.makeConfiguration(), preset: form.runPreset())
        XCTAssertTrue(result.destinationResults.allSatisfy { $0.success })
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("take1.wav").path))
        let asc = dest.appendingPathComponent("ascmhl")
        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: asc).count, 1)
    }

    /// Documents WHY `QuickCopyFormModel.Blocker.multipleFiles` exists (plan D3):
    /// two loose files in one folder share `<parent>/ascmhl/`, both take sequence 1,
    /// and the chain index keeps only one generation. If this test FAILS because the
    /// chain has 2 refs, the engine handles it — delete the blocker + its test.
    func test_twoLooseFiles_shareAscmhlFolder_chainKeepsOneGeneration() async throws {
        let a = try write("src/a.mov")
        let b = try write("src/b.mov")
        let dest = try makeDir("dest")
        var config = BackupConfiguration()
        config.sourcePaths = [a.path, b.path]
        config.destinationPaths = [dest.path]
        let result = try await runEngine(config: config, preset: nil)
        XCTAssertTrue(result.destinationResults.allSatisfy { $0.success })
        let asc = dest.appendingPathComponent("ascmhl")
        XCTAssertEqual(ASCMHLChain.manifestFilesOnDisk(ascmhlDir: asc).count, 2)
        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: asc).count, 1)
    }

    func test_rerun_isIdempotent_nothingRecopied() async throws {
        let src = try makeDir("src/A001")
        try write("src/A001/clip1.mov")
        let dest = try makeDir("dest")
        var form = QuickCopyFormModel(items: [.init(path: src.path, isDirectory: true, kind: .camera)])
        form.destinations = [dest.path]
        let config = form.makeConfiguration()
        _ = try await runEngine(config: config, preset: nil)
        let second = try await runEngine(config: config, preset: nil)
        XCTAssertTrue(second.destinationResults.allSatisfy { $0.success })
        XCTAssertEqual(second.destinationResults.map(\.filesTransferred), [0])
    }

    /// Observed engine behaviour for copyFolderContents = true + .dateOnly (a record, not a spec):
    /// the files land FLAT in the camera folder, but the roll folder `A001/` is still
    /// created next to them and holds the roll's bookkeeping only:
    ///
    ///     20261014/Camera_Media/clip1.mov
    ///     20261014/Camera_Media/A001/.filmcan/roll.json
    ///     20261014/Camera_Media/A001/ascmhl/0001_A001_<timestamp>.mhl
    ///     20261014/Camera_Media/A001/ascmhl/ascmhl_chain.xml
    func test_copyFolderContents_layout() async throws {
        let src = try makeDir("src/A001")
        try write("src/A001/clip1.mov")
        let dest = try makeDir("dest")
        var form = QuickCopyFormModel(items: [.init(path: src.path, isDirectory: true, kind: .camera)])
        form.destinations = [dest.path]
        form.organization = .dateOnly
        form.copyFolderContents = true
        form.pickedDate = date(2026, 10, 14)
        let result = try await runEngine(config: form.makeConfiguration(), preset: form.runPreset())
        XCTAssertTrue(result.destinationResults.allSatisfy { $0.success })

        let camera = dest.appendingPathComponent("20261014/Camera_Media")
        XCTAssertTrue(fm.fileExists(atPath: camera.appendingPathComponent("clip1.mov").path))
        XCTAssertFalse(fm.fileExists(atPath: camera.appendingPathComponent("A001/clip1.mov").path))

        let roll = camera.appendingPathComponent("A001")
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(atPath: roll.path, isDirectory: &isDir) && isDir.boolValue)
        XCTAssertTrue(fm.fileExists(atPath: roll.appendingPathComponent(".filmcan/roll.json").path))
        let asc = roll.appendingPathComponent("ascmhl")
        XCTAssertEqual(ASCMHLChain.manifestFilesOnDisk(ascmhlDir: asc).count, 1)
        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: asc).count, 1)

        let names = tree(of: dest).map {
            $0.replacingOccurrences(of: #"\d{4}_A001_[^/]+\.mhl"#, with: "0001_A001_<ts>.mhl",
                                    options: .regularExpression)
        }
        XCTAssertEqual(names, [
            "20261014",
            "20261014/Camera_Media",
            "20261014/Camera_Media/A001",
            "20261014/Camera_Media/A001/.filmcan",
            "20261014/Camera_Media/A001/.filmcan/roll.json",
            "20261014/Camera_Media/A001/ascmhl",
            "20261014/Camera_Media/A001/ascmhl/0001_A001_<ts>.mhl",
            "20261014/Camera_Media/A001/ascmhl/ascmhl_chain.xml",
            "20261014/Camera_Media/clip1.mov",
        ])
    }
}
