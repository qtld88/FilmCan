import XCTest
@testable import FilmCan

final class PresetDivergenceTests: XCTestCase {
    private func applied(_ preset: OrganizationPreset) -> BackupConfiguration {
        var c = BackupConfiguration()
        c.copyFolderContents = preset.copyFolderContents
        c.runInParallel = preset.runInParallel
        c.engineOptions = preset.engineOptions
        c.logEnabled = preset.logEnabled
        c.logLocation = preset.logLocation
        c.customLogPath = preset.customLogPath
        c.logFileNameTemplate = preset.logFileNameTemplate
        c.duplicatePolicy = preset.duplicatePolicy
        c.duplicateCounterTemplate = preset.duplicateCounterTemplate
        c.organizationFolderTemplate = preset.folderTemplate
        c.organizationRenameTemplate = preset.renameTemplate
        c.organizationUseFolderTemplate = preset.useFolderTemplate
        c.organizationUseRenameTemplate = preset.useRenameTemplate
        c.organizationRenameOnlyPatterns = preset.renameOnlyPatterns
        c.organizationIncludePatterns = preset.includePatterns
        c.organizationExcludePatterns = preset.excludePatterns
        c.organizationCopyOnlyPatterns = preset.copyOnlyPatterns
        c.organizationUseCustomDate = preset.useCustomDate
        c.organizationCustomDate = preset.customDate
        return c
    }

    func test_identicalConfig_doesNotDiffer() {
        let p = OrganizationPreset()
        XCTAssertFalse(applied(p).differs(from: p))
    }

    func test_verificationDivergence_isReported() {
        var p = OrganizationPreset()
        p.engineOptions.verificationMode = .paranoid
        var c = applied(p)
        c.engineOptions.verificationMode = .fast
        let d = c.differences(from: p)
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.field, "Verification")
        XCTAssertEqual(d.first?.current, VerifyMode.fast.displayName)
        XCTAssertEqual(d.first?.preset, VerifyMode.paranoid.displayName)
    }

    func test_multipleFields_allListed() {
        let p = OrganizationPreset()
        var c = applied(p)
        c.duplicatePolicy = .skip
        c.copyFolderContents = true
        c.organizationExcludePatterns = ["*.tmp"]
        XCTAssertEqual(Set(c.differences(from: p).map(\.field)),
                       ["Duplicates", "Copy folder contents", "Exclude patterns"])
    }

    func test_unrelatedConfigFields_areIgnored() {
        let p = OrganizationPreset()
        var c = applied(p)
        c.name = "Other"
        c.sourcePaths = ["/a"]
        c.destinationPaths = ["/b"]
        XCTAssertFalse(c.differs(from: p))
    }

    func test_netflixReportsDefault_isNotModified() {
        let p = OrganizationPreset.netflixIngest()
        var c = applied(p)
        c.logLocation = .custom
        c.customLogPath = "Reports"
        XCTAssertEqual(c.differences(from: p), [])
    }

    func test_customDateOnAnotherDay_isReported() {
        var p = OrganizationPreset()
        p.useCustomDate = true
        var c = applied(p)
        c.organizationCustomDate = p.customDate.addingTimeInterval(3 * 86_400)
        XCTAssertEqual(c.differences(from: p).map(\.field), ["Date"])
    }
}
