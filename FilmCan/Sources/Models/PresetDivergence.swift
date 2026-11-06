import Foundation

struct PresetDifference: Equatable {
    let field: String
    let current: String
    let preset: String

    var summary: String { "\(field): \(current) (preset: \(preset))" }
}

extension BackupConfiguration {
    func differences(from preset: OrganizationPreset) -> [PresetDifference] {
        var out: [PresetDifference] = []
        func check<T: Equatable>(_ field: String, _ cur: T, _ pre: T, _ label: (T) -> String) {
            if cur != pre { out.append(PresetDifference(field: field, current: label(cur), preset: label(pre))) }
        }
        func onOff(_ b: Bool) -> String { b ? "On" : "Off" }
        func orNone(_ s: String) -> String { s.isEmpty ? "none" : s }
        func list(_ l: [String]) -> String { l.isEmpty ? "none" : l.joined(separator: ", ") }
        let a = engineOptions, b = preset.engineOptions

        check("Verification", a.verificationMode, b.verificationMode) { $0.displayName }
        check("Post-verify", a.postVerify, b.postVerify, onOff)
        check("Only copy changed", a.onlyCopyChanged, b.onlyCopyChanged, onOff)
        check("Hash list precheck", a.useHashListPrecheck, b.useHashListPrecheck, onOff)
        check("Reuse organized files", a.reuseOrganizedFiles, b.reuseOrganizedFiles, onOff)
        check("Allow resume", a.allowResume, b.allowResume, onOff)
        check("File ordering", a.fileOrdering, b.fileOrdering) { "\($0)" }
        check("Parallel copy", a.parallelCopyEnabled, b.parallelCopyEnabled, onOff)
        check("Duplicates", duplicatePolicy, preset.duplicatePolicy) { $0.displayName }
        check("Duplicate counter", duplicateCounterTemplate, preset.duplicateCounterTemplate, orNone)
        check("Copy folder contents", copyFolderContents, preset.copyFolderContents, onOff)
        check("Run in parallel", runInParallel, preset.runInParallel, onOff)
        check("Logs", logEnabled, preset.logEnabled, onOff)
        // applyPreset pre-fills Netflix reports into Reports/ when the preset leaves the path empty.
        let netflixReports = preset.name == OrganizationPreset.netflixIngestName && preset.customLogPath.isEmpty
        check("Log location", logLocation, netflixReports ? .custom : preset.logLocation) { "\($0)" }
        check("Log path", customLogPath, netflixReports ? "Reports" : preset.customLogPath, orNone)
        check("Log file name", logFileNameTemplate, preset.logFileNameTemplate, orNone)
        check("Folder template", organizationFolderTemplate, preset.folderTemplate, orNone)
        check("Rename template", organizationRenameTemplate, preset.renameTemplate, orNone)
        check("Use folder template", organizationUseFolderTemplate, preset.useFolderTemplate, onOff)
        check("Use rename template", organizationUseRenameTemplate, preset.useRenameTemplate, onOff)
        check("Rename-only patterns", organizationRenameOnlyPatterns, preset.renameOnlyPatterns, list)
        check("Include patterns", organizationIncludePatterns, preset.includePatterns, list)
        check("Exclude patterns", organizationExcludePatterns, preset.excludePatterns, list)
        check("Copy-only patterns", organizationCopyOnlyPatterns, preset.copyOnlyPatterns, list)
        check("Custom date", organizationUseCustomDate, preset.useCustomDate, onOff)
        if organizationUseCustomDate, preset.useCustomDate,
           !Calendar.current.isDate(organizationCustomDate, inSameDayAs: preset.customDate) {
            let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none
            out.append(PresetDifference(field: "Date", current: f.string(from: organizationCustomDate),
                                        preset: f.string(from: preset.customDate)))
        }
        return out
    }

    func differs(from preset: OrganizationPreset) -> Bool {
        !differences(from: preset).isEmpty
    }
}
