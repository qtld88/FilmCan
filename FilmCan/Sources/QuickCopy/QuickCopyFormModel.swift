import Foundation

/// Pure logic behind the Quick Copy window: form state → temporary
/// `BackupConfiguration` + run-time `OrganizationPreset`, validation, folder
/// preview. No UI; the only I/O is the injectable `pathExists`.
struct QuickCopyFormModel {

    enum OrganizationMode: String, CaseIterable, Identifiable {
        case none, dateOnly, projectAndDay
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .none: return "None"
            case .dateOnly: return "Date only"
            case .projectAndDay: return "Project + day"
            }
        }
    }

    struct Item: Identifiable, Equatable {
        let path: String
        let isDirectory: Bool
        var kind: SourceMediaKind
        var id: String { path }
        var name: String { (path as NSString).lastPathComponent }
    }

    // MARK: Templates (existing tokens only)
    static let projectCameraTemplate = "{date}_{episode}_{day}/Camera_Media"
    static let projectSoundTemplate = "{date}_{episode}_{day}/Sound_Media"
    static let dateCameraTemplate = "{date}/Camera_Media"
    static let dateSoundTemplate = "{date}/Sound_Media"

    // MARK: Inputs
    var items: [Item]
    var destinations: [String] = []
    var savedPresets: [OrganizationPreset] = []
    /// nil ⇒ "None": the basic options below drive the run.
    var selectedPresetId: UUID?
    var verification: VerifyMode = .fast
    var duplicatePolicy: OrganizationPreset.DuplicatePolicy = .skip
    var copyFolderContents = false
    var organization: OrganizationMode = .none
    /// nil ⇒ today.
    var pickedDate: Date?
    var project = ""
    var day = ""
    var savePresetName = ""
    var today = Date()
    var pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }

    // MARK: Building items
    static func items(for paths: [String], fileManager: FileManager = .default) -> [Item] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted else { return nil }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
            return Item(path: path, isDirectory: isDir.boolValue,
                        kind: MediaKindGuesser.guess(path: path, fileManager: fileManager))
        }
    }

    // MARK: Sanitizing
    /// Whitespace → "_", then Netflix-prohibited characters → "_".
    static func sanitizeName(_ raw: String) -> String {
        let joined = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: "_")
        return NetflixNameValidator.sanitize(joined)
    }

    var sanitizedProject: String {
        // A hidden field's leftover text must not override the preset's project name.
        if selectedPreset == nil || showsProjectField {
            let typed = Self.sanitizeName(project)
            if !typed.isEmpty { return typed }
        }
        return Self.sanitizeName(selectedPreset?.projectName ?? "")
    }

    var sanitizedDay: String { Self.sanitizeName(day) }

    // MARK: Preset / organization state
    var selectedPreset: OrganizationPreset? {
        guard let id = selectedPresetId else { return nil }
        return savedPresets.first { $0.id == id }
    }

    private static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var organizationActive: Bool {
        if let p = selectedPreset { return p.useFolderTemplate && !Self.isBlank(p.folderTemplate) }
        return organization != .none
    }

    /// Camera/Sound dropdown only matters when folders are organized.
    var showsMediaKind: Bool { organizationActive }

    var showsProjectField: Bool {
        if let p = selectedPreset {
            return organizationActive && templatesContain("{episode}", in: p) && Self.isBlank(p.projectName)
        }
        return organization == .projectAndDay
    }

    var showsDayField: Bool {
        if let p = selectedPreset { return organizationActive && templatesContain("{day}", in: p) }
        return organization == .projectAndDay
    }

    private func templatesContain(_ token: String, in p: OrganizationPreset) -> Bool {
        p.folderTemplate.contains(token) || p.soundFolderTemplate.contains(token)
    }

    // MARK: Effective run values (preset wins over the basic options)
    var effectiveVerification: VerifyMode {
        selectedPreset?.engineOptions.verificationMode ?? verification
    }

    var effectiveDuplicatePolicy: OrganizationPreset.DuplicatePolicy {
        let policy = selectedPreset?.duplicatePolicy ?? duplicatePolicy
        return policy == .ask ? .skip : policy
    }

    /// True when the chosen preset says "Ask each time" and Quick Copy runs Skip.
    var duplicatePolicyWasMapped: Bool { selectedPreset?.duplicatePolicy == .ask }

    var effectiveCopyFolderContents: Bool { selectedPreset?.copyFolderContents ?? copyFolderContents }
    var effectiveHashListStyle: HashListStyle { selectedPreset?.hashListStyle ?? .ascMHL }

    // MARK: Run preset
    /// The preset the engine runs with (nil ⇒ no organization). A picked date lands
    /// on this copy only — never on a stored preset.
    func runPreset() -> OrganizationPreset? {
        var preset: OrganizationPreset
        if let saved = selectedPreset {
            preset = saved
        } else {
            switch organization {
            case .none:
                return nil
            case .dateOnly:
                preset = OrganizationPreset()
                preset.folderTemplate = Self.dateCameraTemplate
                preset.soundFolderTemplate = Self.dateSoundTemplate
            case .projectAndDay:
                preset = OrganizationPreset()
                preset.folderTemplate = Self.projectCameraTemplate
                preset.soundFolderTemplate = Self.projectSoundTemplate
            }
            preset.name = "Quick Copy"
            preset.useFolderTemplate = true
        }
        if organizationActive {
            // No picked date means "Today", whatever the stored preset says.
            preset.useCustomDate = pickedDate != nil
            if let picked = pickedDate { preset.customDate = picked }
        }
        return preset
    }
}

// MARK: - Temporary configuration, validation, saved preset

extension QuickCopyFormModel {

    /// Never written to `configs.json`. Engine options are read from the CONFIG by
    /// `TransferViewModel.runFanOut`, so preset values are copied in here; the
    /// organization preset itself travels separately (`runPreset()`).
    func makeConfiguration() -> BackupConfiguration {
        var c = BackupConfiguration()
        c.name = "Quick Copy — \(items.first?.name ?? "")"
        c.sourcePaths = items.map(\.path)
        c.destinationPaths = destinations
        c.sourceMediaKinds = Dictionary(items.map { ($0.path, $0.kind) }, uniquingKeysWith: { first, _ in first })
        c.episode = sanitizedProject
        c.day = sanitizedDay

        var options = selectedPreset?.engineOptions ?? EngineOptions()
        options.verificationMode = effectiveVerification
        c.engineOptions = options

        c.hashListStyle = effectiveHashListStyle
        c.duplicatePolicy = effectiveDuplicatePolicy
        c.copyFolderContents = effectiveCopyFolderContents
        c.logEnabled = selectedPreset?.logEnabled ?? true
        if let p = selectedPreset {
            c.logLocation = p.logLocation
            c.customLogPath = p.customLogPath
            c.logFileNameTemplate = p.logFileNameTemplate
            c.duplicateCounterTemplate = p.duplicateCounterTemplate
        }
        c.selectedOrganizationPresetId = selectedPresetId
        return c
    }

    // MARK: Run blockers
    enum Blocker: Equatable {
        case noSources
        case noDestination
        case missingDestination(String)
        case missingProject
        case multipleFiles

        var message: String {
            switch self {
            case .noSources: return "Nothing to copy."
            case .noDestination: return "Add a destination to continue."
            case .missingDestination(let p):
                return "Destination not found: \((p as NSString).lastPathComponent)."
            case .missingProject: return "Enter a project name."
            case .multipleFiles:
                return "Several loose files can't be copied together yet — select a folder, or copy the files one at a time."
            }
        }
    }

    var blocker: Blocker? {
        if items.isEmpty { return .noSources }
        if destinations.isEmpty { return .noDestination }
        if let gone = destinations.first(where: { !pathExists($0) }) { return .missingDestination(gone) }
        if selectedPreset == nil, organization == .projectAndDay, sanitizedProject.isEmpty {
            return .missingProject
        }
        if items.filter({ !$0.isDirectory }).count > 1 { return .multipleFiles }
        return nil
    }

    var canRun: Bool { blocker == nil }

    // MARK: Save as preset
    /// Only with Preset = None and a non-empty name. A date is never stored.
    func makeSavedPreset() -> OrganizationPreset? {
        guard selectedPresetId == nil else { return nil }
        let name = savePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        var p = OrganizationPreset()
        p.name = name
        var options = EngineOptions()
        options.verificationMode = verification
        p.engineOptions = options
        p.duplicatePolicy = duplicatePolicy == .ask ? .skip : duplicatePolicy
        p.copyFolderContents = copyFolderContents
        p.logEnabled = true
        p.hashListStyle = .ascMHL
        p.useCustomDate = false
        switch organization {
        case .none:
            break
        case .dateOnly:
            p.useFolderTemplate = true
            p.folderTemplate = Self.dateCameraTemplate
            p.soundFolderTemplate = Self.dateSoundTemplate
        case .projectAndDay:
            p.useFolderTemplate = true
            p.folderTemplate = Self.projectCameraTemplate
            p.soundFolderTemplate = Self.projectSoundTemplate
            p.projectName = sanitizedProject
        }
        return p
    }

    // MARK: Summary
    /// One-line description of the chosen preset's options (nil with Preset = None).
    var presetSummary: String? {
        guard let p = selectedPreset else { return nil }
        let policy = duplicatePolicyWasMapped
            ? "Skip (preset says Ask each time)"
            : p.duplicatePolicy.displayName
        let copy = p.copyFolderContents ? "contents only" : "whole folder"
        return "\(effectiveVerification.displayName) verification · If exists: \(policy) · "
            + "\(copy) · \(effectiveHashListStyle.shortName)"
    }
}

// MARK: - Folder tree preview

extension QuickCopyFormModel {

    struct TreeLine: Equatable {
        let depth: Int
        let name: String
        let isNew: Bool
    }

    /// Path of each item under `destination`, relative to it, resolved with the
    /// SAME function the engine uses (`FanOutCopier.resolveDestFilePath`) so the
    /// preview cannot drift from what is written.
    func relativePaths(for destination: String) -> [String] {
        let preset = runPreset()
        let metadata = ShootMetadata(episode: sanitizedProject, day: sanitizedDay)
        let prefix = destination.hasSuffix("/") ? destination : destination + "/"
        return items.map { item in
            let full = FanOutCopier.resolveDestFilePath(
                destRoot: destination, rootName: item.name, rootPath: item.path, relPath: "",
                preset: preset, copyFolderContents: false,
                date: today, metadata: metadata, mediaKind: item.kind)
            return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : item.name
        }
    }

    /// What will be created under `destination`; `isNew` = does not exist yet.
    func treePreview(for destination: String) -> [TreeLine] {
        var lines: [TreeLine] = []
        var seen = Set<String>()
        for (item, rel) in zip(items, relativePaths(for: destination)) {
            var components = rel.split(separator: "/").map(String.init)
            var rollName: String?
            if effectiveCopyFolderContents && item.isDirectory {
                // Contents land flat in the parent; the roll folder is still created
                // beside them, holding only the hash list (`ascmhl/`, `.filmcan/`).
                rollName = components.popLast()
            }
            var cumulative = destination
            for (depth, component) in components.enumerated() {
                cumulative = (cumulative as NSString).appendingPathComponent(component)
                if seen.insert(cumulative).inserted {
                    lines.append(TreeLine(depth: depth, name: component, isNew: !pathExists(cumulative)))
                }
            }
            if let rollName {
                let rollPath = (cumulative as NSString).appendingPathComponent(rollName)
                lines.append(TreeLine(depth: components.count, name: "contents of \(item.name)", isNew: true))
                lines.append(TreeLine(depth: components.count, name: "\(rollName) (hash list only)",
                                      isNew: !pathExists(rollPath)))
            }
        }
        return lines
    }

    /// Folder to reveal in Finder after the copy: the top folder the run created
    /// under `destination` (or the destination itself when nothing nests below it).
    func revealPath(for destination: String) -> String {
        guard let rel = relativePaths(for: destination).first else { return destination }
        let parts = rel.split(separator: "/")
        if effectiveCopyFolderContents, items.first?.isDirectory == true, parts.count == 1 {
            return destination
        }
        guard let top = parts.first else { return destination }
        return (destination as NSString).appendingPathComponent(String(top))
    }
}
