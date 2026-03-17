import Foundation
import Combine
import SwiftUI

@MainActor
class BackupEditorViewModel: ObservableObject {
    @Published var config: BackupConfiguration
    @Published var showValidationError: Bool = false
    @Published var validationMessage: String = ""
    
    private let storage = AppState.shared.storage
    private var isSyncingFromPreset = false
    
    init(config: BackupConfiguration) {
        self.config = config
    }

    func syncFromStorage(_ updated: BackupConfiguration) {
        guard updated.id == config.id else { return }
        if config != updated {
            config = updated
        }
    }
    
    // Source paths
    var sourcePaths: [String] {
        get { config.sourcePaths }
        set {
            config.sourcePaths = newValue
            storage.lastSourcePath = newValue.last
            save()
        }
    }
    
    func addSource(_ path: String) {
        guard !path.isEmpty && !config.sourcePaths.contains(path) else { return }
        config.sourcePaths.append(path)
        storage.lastSourcePath = path
        save()
    }
    
    func removeSource(at index: Int) {
        guard index < config.sourcePaths.count else { return }
        config.sourcePaths.remove(at: index)
        save()
    }
    
    // Destinations
    var destinations: [String] {
        get { config.destinationPaths }
        set {
            config.destinationPaths = newValue
            if let first = newValue.first {
                storage.lastDestinationPath = first
            }
            save()
        }
    }
    
    func addDestination(_ path: String) {
        if !path.isEmpty && !config.destinationPaths.contains(path) {
            config.destinationPaths.append(path)
            storage.lastDestinationPath = path
            save()
        }
    }
    
    func removeDestination(at index: Int) {
        guard index < config.destinationPaths.count else { return }
        config.destinationPaths.remove(at: index)
        save()
    }
    
    func moveDestinations(from source: IndexSet, to destination: Int) {
        config.destinationPaths.move(fromOffsets: source, toOffset: destination)
        save()
    }
    
    // Rsync options
    var rsyncOptions: RsyncOptions {
        get { config.rsyncOptions }
        set {
            config.rsyncOptions = newValue
            save()
        }
    }

    func setCopyEngine(_ engine: CopyEngine) {
        var options = config.rsyncOptions
        if engine == .custom {
            if options.copyEngine == .rsync {
                var snapshot = options
                snapshot.copyEngine = .rsync
                config.lastRsyncOptions = snapshot
            }
            options.copyEngine = .custom
            options.useChecksum = false
            options.onlyCopyChanged = false
            options.allowResume = false
            options.delete = false
            options.inplace = false
            options.reuseOrganizedFiles = false
            options.customArgs = ""
            options.postVerify = true
        } else {
            if let last = config.lastRsyncOptions {
                options = last
            } else {
                options = RsyncOptions()
                options.onlyCopyChanged = true
            }
            options.copyEngine = .rsync
        }
        config.rsyncOptions = options
        save()
    }

    func enforceCustomEngineDefaultsIfNeeded() {
        guard config.rsyncOptions.copyEngine == .custom else { return }
        var options = config.rsyncOptions
        var changed = false
        if options.useChecksum { options.useChecksum = false; changed = true }
        if options.onlyCopyChanged { options.onlyCopyChanged = false; changed = true }
        if options.allowResume { options.allowResume = false; changed = true }
        if options.delete { options.delete = false; changed = true }
        if options.inplace { options.inplace = false; changed = true }
        if options.reuseOrganizedFiles { options.reuseOrganizedFiles = false; changed = true }
        if !options.customArgs.isEmpty { options.customArgs = ""; changed = true }
        if !options.postVerify { options.postVerify = true; changed = true }
        if changed {
            config.rsyncOptions = options
            save()
        }
    }
    
    // Name
    var name: String {
        get { config.name }
        set {
            config.name = newValue
            save()
        }
    }
    
    // Log location
    var logEnabled: Bool {
        get { config.logEnabled }
        set {
            config.logEnabled = newValue
            save()
        }
    }

    var logLocation: BackupConfiguration.LogLocation {
        get { config.logLocation }
        set {
            config.logLocation = newValue
            save()
        }
    }
    
    var customLogPath: String {
        get { config.customLogPath }
        set {
            config.customLogPath = newValue
            save()
        }
    }

    var logFileNameTemplate: String {
        get { config.logFileNameTemplate }
        set {
            config.logFileNameTemplate = newValue
            save()
        }
    }
    
    var runInParallel: Bool {
        get { config.runInParallel }
        set {
            config.runInParallel = newValue
            save()
        }
    }

    var copyFolderContents: Bool {
        get { config.copyFolderContents }
        set {
            config.copyFolderContents = newValue
            save()
        }
    }

    var sourceAutoDetectEnabled: Bool {
        get { config.sourceAutoDetectEnabled }
        set {
            config.sourceAutoDetectEnabled = newValue
            save()
        }
    }

    var sourceAutoDetectPatterns: [String] {
        get { config.sourceAutoDetectPatterns }
        set {
            config.sourceAutoDetectPatterns = newValue
            save()
        }
    }

    var destinationAutoDetectEnabled: Bool {
        get { config.destinationAutoDetectEnabled }
        set {
            config.destinationAutoDetectEnabled = newValue
            save()
        }
    }

    var destinationAutoDetectPatterns: [String] {
        get { config.destinationAutoDetectPatterns }
        set {
            config.destinationAutoDetectPatterns = newValue
            save()
        }
    }

    func refreshAutoDetectedSources() {
        guard config.sourceAutoDetectEnabled else { return }
        let rules = config.sourceAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rules.isEmpty else { return }

        var updated = config.sourcePaths
        let volumeURLs = mountedExternalVolumes()
        for volumeURL in volumeURLs {
            let volumeName = volumeURL.lastPathComponent
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                if matches(volumeName, pattern: pattern) {
                    let resolvedMatches = resolveSubpathMatches(rootURL: volumeURL, subpath: subpath)
                    for resolved in resolvedMatches where !updated.contains(resolved) {
                        updated.append(resolved)
                    }
                }
            }
        }

        if updated != config.sourcePaths {
            config.sourcePaths = updated
            save()
        }
    }

    func refreshAutoDetectedDestinations() {
        guard config.destinationAutoDetectEnabled else { return }
        let rules = config.destinationAutoDetectPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rules.isEmpty else { return }

        var updated = config.destinationPaths
        let volumeURLs = mountedExternalVolumes()
        for volumeURL in volumeURLs {
            let volumeName = volumeURL.lastPathComponent
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                if matches(volumeName, pattern: pattern) {
                    let resolvedMatches = resolveSubpathMatches(rootURL: volumeURL, subpath: subpath)
                    for resolved in resolvedMatches where !updated.contains(resolved) {
                        updated.append(resolved)
                    }
                }
            }
        }

        if updated != config.destinationPaths {
            config.destinationPaths = updated
            if let first = updated.first {
                storage.lastDestinationPath = first
            }
            save()
        }
    }

    var duplicatePolicy: OrganizationPreset.DuplicatePolicy {
        get { config.duplicatePolicy }
        set {
            config.duplicatePolicy = newValue
            save()
        }
    }

    var duplicateCounterTemplate: String {
        get { config.duplicateCounterTemplate }
        set {
            config.duplicateCounterTemplate = newValue
            save()
        }
    }

    private func mountedExternalVolumes() -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.volumeIsInternalKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey])
            return values?.volumeIsInternal != true
        }
    }

    private func splitRule(_ rule: String) -> (String, String) {
        guard let separatorIndex = rule.firstIndex(of: "/") else {
            return (rule, "")
        }
        let drive = String(rule[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = String(rule[rule.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (drive, folder)
    }

    private func matches(_ name: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            let regex = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
            return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return name.compare(trimmed, options: [.caseInsensitive]) == .orderedSame
    }

    private func resolveSubpathMatches(rootURL: URL, subpath: String) -> [String] {
        let trimmed = subpath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [rootURL.path] }

        if !trimmed.contains("*") {
            let resolvedURL = rootURL.appendingPathComponent(trimmed)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return [resolvedURL.path]
            }
            return []
        }

        let components = trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return [rootURL.path] }

        var currentURLs: [URL] = [rootURL]
        let fm = FileManager.default

        for (index, componentPattern) in components.enumerated() {
            let isLast = index == components.count - 1
            var nextURLs: [URL] = []

            for baseURL in currentURLs {
                guard let children = try? fm.contentsOfDirectory(
                    at: baseURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for child in children where matches(child.lastPathComponent, pattern: componentPattern) {
                    let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    if isLast {
                        if isDirectory {
                            nextURLs.append(child)
                        }
                    } else if isDirectory {
                        nextURLs.append(child)
                    }
                }
            }

            currentURLs = nextURLs
            if currentURLs.isEmpty { break }
        }

        return currentURLs.map { $0.path }
    }

    var organizationPresets: [OrganizationPreset] {
        get { storage.organizationPresets }
        set {
            objectWillChange.send()
            storage.organizationPresets = newValue
            storage.save()
        }
    }

    var selectedOrganizationPresetId: UUID? {
        get { config.selectedOrganizationPresetId }
        set {
            config.selectedOrganizationPresetId = newValue
            save()
        }
    }

    var localOrganizationPreset: OrganizationPreset {
        get {
            var preset = OrganizationPreset()
            preset.name = "Custom"
            preset.folderTemplate = config.offOrganizationFolderTemplate
            preset.renameTemplate = config.offOrganizationRenameTemplate
            preset.useFolderTemplate = config.offOrganizationUseFolderTemplate
            preset.useRenameTemplate = config.offOrganizationUseRenameTemplate
            preset.renameOnlyPatterns = config.offOrganizationRenameOnlyPatterns
            preset.includePatterns = config.offOrganizationIncludePatterns
            preset.excludePatterns = config.offOrganizationExcludePatterns
            preset.copyOnlyPatterns = config.offOrganizationCopyOnlyPatterns
            preset.useCustomDate = config.offOrganizationUseCustomDate
            preset.customDate = config.offOrganizationCustomDate
            return preset
        }
        set {
            config.offOrganizationFolderTemplate = newValue.folderTemplate
            config.offOrganizationRenameTemplate = newValue.renameTemplate
            config.offOrganizationUseFolderTemplate = newValue.useFolderTemplate
            config.offOrganizationUseRenameTemplate = newValue.useRenameTemplate
            config.offOrganizationRenameOnlyPatterns = newValue.renameOnlyPatterns
            config.offOrganizationIncludePatterns = newValue.includePatterns
            config.offOrganizationExcludePatterns = newValue.excludePatterns
            config.offOrganizationCopyOnlyPatterns = newValue.copyOnlyPatterns
            config.offOrganizationUseCustomDate = newValue.useCustomDate
            config.offOrganizationCustomDate = newValue.customDate
            if config.selectedOrganizationPresetId == nil {
                config.organizationFolderTemplate = newValue.folderTemplate
                config.organizationRenameTemplate = newValue.renameTemplate
                config.organizationUseFolderTemplate = newValue.useFolderTemplate
                config.organizationUseRenameTemplate = newValue.useRenameTemplate
                config.organizationRenameOnlyPatterns = newValue.renameOnlyPatterns
                config.organizationIncludePatterns = newValue.includePatterns
                config.organizationExcludePatterns = newValue.excludePatterns
                config.organizationCopyOnlyPatterns = newValue.copyOnlyPatterns
                config.organizationUseCustomDate = newValue.useCustomDate
                config.organizationCustomDate = newValue.customDate
            }
            save()
        }
    }

    func applyOffOrganizationSettings() {
        config.selectedOrganizationPresetId = nil
        config.organizationFolderTemplate = config.offOrganizationFolderTemplate
        config.organizationRenameTemplate = config.offOrganizationRenameTemplate
        config.organizationUseFolderTemplate = config.offOrganizationUseFolderTemplate
        config.organizationUseRenameTemplate = config.offOrganizationUseRenameTemplate
        config.organizationRenameOnlyPatterns = config.offOrganizationRenameOnlyPatterns
        config.organizationIncludePatterns = config.offOrganizationIncludePatterns
        config.organizationExcludePatterns = config.offOrganizationExcludePatterns
        config.organizationCopyOnlyPatterns = config.offOrganizationCopyOnlyPatterns
        config.organizationUseCustomDate = config.offOrganizationUseCustomDate
        config.organizationCustomDate = config.offOrganizationCustomDate
        save()
    }

    func applyPreset(_ preset: OrganizationPreset) {
        config.copyFolderContents = preset.copyFolderContents
        config.runInParallel = preset.runInParallel
        config.rsyncOptions = preset.rsyncOptions
        config.logEnabled = preset.logEnabled
        config.logLocation = preset.logLocation
        config.customLogPath = preset.customLogPath
        config.logFileNameTemplate = preset.logFileNameTemplate
        config.duplicatePolicy = preset.duplicatePolicy
        config.duplicateCounterTemplate = preset.duplicateCounterTemplate
        applyPresetOrganizationSettings(preset)
        config.selectedOrganizationPresetId = preset.id
        save()
    }

    func syncFromSelectedPresetIfNeeded() {
        guard let selectedId = config.selectedOrganizationPresetId,
              let preset = storage.organizationPresets.first(where: { $0.id == selectedId }) else { return }
        isSyncingFromPreset = true
        applyPresetOrganizationSettings(preset)
        save()
        isSyncingFromPreset = false
    }

    private func applyPresetOrganizationSettings(_ preset: OrganizationPreset) {
        config.organizationFolderTemplate = preset.folderTemplate
        config.organizationRenameTemplate = preset.renameTemplate
        config.organizationUseFolderTemplate = preset.useFolderTemplate
        config.organizationUseRenameTemplate = preset.useRenameTemplate
        config.organizationRenameOnlyPatterns = preset.renameOnlyPatterns
        config.organizationIncludePatterns = preset.includePatterns
        config.organizationExcludePatterns = preset.excludePatterns
        config.organizationCopyOnlyPatterns = preset.copyOnlyPatterns
        config.organizationUseCustomDate = preset.useCustomDate
        config.organizationCustomDate = preset.customDate
    }

    func updateSelectedPresetFromCurrent() {
        guard let selectedId = config.selectedOrganizationPresetId,
              let index = storage.organizationPresets.firstIndex(where: { $0.id == selectedId }) else { return }
        var preset = storage.organizationPresets[index]
        preset.copyFolderContents = config.copyFolderContents
        preset.runInParallel = config.runInParallel
        preset.rsyncOptions = config.rsyncOptions
        preset.logEnabled = config.logEnabled
        preset.logLocation = config.logLocation
        preset.customLogPath = config.customLogPath
        preset.logFileNameTemplate = config.logFileNameTemplate
        preset.duplicatePolicy = config.duplicatePolicy
        preset.duplicateCounterTemplate = config.duplicateCounterTemplate
        preset.folderTemplate = config.organizationFolderTemplate
        preset.renameTemplate = config.organizationRenameTemplate
        preset.useFolderTemplate = config.organizationUseFolderTemplate
        preset.useRenameTemplate = config.organizationUseRenameTemplate
        preset.renameOnlyPatterns = config.organizationRenameOnlyPatterns
        preset.includePatterns = config.organizationIncludePatterns
        preset.excludePatterns = config.organizationExcludePatterns
        preset.copyOnlyPatterns = config.organizationCopyOnlyPatterns
        preset.useCustomDate = config.organizationUseCustomDate
        preset.customDate = config.organizationCustomDate
        storage.organizationPresets[index] = preset
        storage.save()
    }

    func saveCurrentSettingsAsPreset() {
        objectWillChange.send()
        var preset = OrganizationPreset()
        preset.name = "Preset \(storage.organizationPresets.count + 1)"

        preset.folderTemplate = config.organizationFolderTemplate
        preset.renameTemplate = config.organizationRenameTemplate
        preset.useFolderTemplate = config.organizationUseFolderTemplate
        preset.useRenameTemplate = config.organizationUseRenameTemplate
        preset.renameOnlyPatterns = config.organizationRenameOnlyPatterns
        preset.includePatterns = config.organizationIncludePatterns
        preset.excludePatterns = config.organizationExcludePatterns
        preset.copyOnlyPatterns = config.organizationCopyOnlyPatterns
        preset.useCustomDate = config.organizationUseCustomDate
        preset.customDate = config.organizationCustomDate

        preset.copyFolderContents = config.copyFolderContents
        preset.runInParallel = config.runInParallel
        preset.rsyncOptions = config.rsyncOptions
        preset.logEnabled = config.logEnabled
        preset.logLocation = config.logLocation
        preset.customLogPath = config.customLogPath
        preset.logFileNameTemplate = config.logFileNameTemplate
        preset.duplicatePolicy = config.duplicatePolicy
        preset.duplicateCounterTemplate = config.duplicateCounterTemplate

        storage.organizationPresets.append(preset)
        config.selectedOrganizationPresetId = preset.id
        storage.save()
        save()
    }

    func addOrganizationPreset() {
        objectWillChange.send()
        var preset = OrganizationPreset()
        preset.name = "Preset \(storage.organizationPresets.count + 1)"
        preset.folderTemplate = ""
        preset.renameTemplate = ""
        preset.useFolderTemplate = false
        preset.useRenameTemplate = false
        preset.renameOnlyPatterns = []
        storage.organizationPresets.append(preset)
        config.selectedOrganizationPresetId = preset.id
        storage.save()
        save()
    }
    
    func deleteOrganizationPreset(id: UUID) {
        objectWillChange.send()
        storage.organizationPresets.removeAll { $0.id == id }
        if config.selectedOrganizationPresetId == id {
            config.selectedOrganizationPresetId = storage.organizationPresets.first?.id
        }
        storage.save()
        save()
    }
    
    // Validation
    func validate() -> Bool {
        if config.sourceAutoDetectEnabled {
            refreshAutoDetectedSources()
        }
        if config.sourcePaths.isEmpty {
            validationMessage = "Please add at least one source file or folder"
            showValidationError = true
            return false
        }
        
        if config.destinationPaths.isEmpty {
            validationMessage = "Please add at least one destination folder"
            showValidationError = true
            return false
        }
        
        let fm = FileManager.default
        
        // Validate sources exist and are accessible
        for src in config.sourcePaths {
            if !fm.fileExists(atPath: src) {
                validationMessage = "Source does not exist: \(src)"
                showValidationError = true
                return false
            }
            
            // Check if source is readable
            if !fm.isReadableFile(atPath: src) {
                validationMessage = "Permission denied: Cannot read source \((src as NSString).lastPathComponent)"
                showValidationError = true
                return false
            }
        }

        func normalizedPath(_ path: String) -> String {
            URL(fileURLWithPath: path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
        }

        // Prevent destinations inside sources (and exact matches).
        let normalizedSources = config.sourcePaths.map(normalizedPath)
        let normalizedDestinations = config.destinationPaths.map(normalizedPath)
        for sourcePath in normalizedSources {
            var isDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory)
            let sourceName = (sourcePath as NSString).lastPathComponent
            let sourcePrefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
            for destPath in normalizedDestinations {
                if destPath == sourcePath {
                    validationMessage = "Source and destination are the same: \(sourceName)"
                    showValidationError = true
                    return false
                }
                if isDirectory.boolValue, destPath.hasPrefix(sourcePrefix) {
                    let destName = (destPath as NSString).lastPathComponent
                    validationMessage = "Destination “\(destName)” is inside source “\(sourceName)”. Choose a destination outside the source folder."
                    showValidationError = true
                    return false
                }
            }
        }
        
        // Validate destinations
        for dest in config.destinationPaths {
            let summary = DriveUtilities.summary(for: dest)
            if summary.isReadOnly == true {
                let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                validationMessage = "Destination is read-only\(formatLabel): \(dest)"
                showValidationError = true
                return false
            }
            if !fm.fileExists(atPath: dest) {
                // Try to create it
                do {
                    try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
                } catch {
                    validationMessage = "Cannot create destination folder: \(dest)\n\(error.localizedDescription)"
                    showValidationError = true
                    return false
                }
            }
            
            // Check if destination is writable
            if !fm.isWritableFile(atPath: dest) {
                validationMessage = "Permission denied: Cannot write to \((dest as NSString).lastPathComponent)"
                showValidationError = true
                return false
            }
        }
        
        if !config.rsyncOptions.isValid {
            validationMessage = "Invalid custom rsync arguments"
            showValidationError = true
            return false
        }
        
        showValidationError = false
        return true
    }
    
    // Persistence
    func save() {
        storage.update(config)
        if config.selectedOrganizationPresetId != nil && !isSyncingFromPreset {
            updateSelectedPresetFromCurrent()
        }
    }
}
