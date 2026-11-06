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
    /// Folder-vs-contents picked in the preview for this copy only, over the preset's.
    var copyFolderContentsOverride: Bool?
    var organization: OrganizationMode = .none
    /// nil ⇒ today.
    var pickedDate: Date?
    /// Typed name for the top folder; nil ⇒ the name the templates resolve to.
    var rootFolderName: String?
    /// Camera/Sound folder typed by the user when the preset has none.
    var mediaFolderNames: [SourceMediaKind: String] = [:]
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

    var showsMediaKind: Bool { organizationActive }

    /// The preset has no separate Camera/Sound folder: the user must name one per
    /// kind in use, or both kinds would land in the same folder.
    var lacksMediaFolder: Bool {
        guard let p = organizedPreset() else { return false }
        return Self.isBlank(p.soundFolderTemplate) || p.soundFolderTemplate == p.folderTemplate
    }

    /// Sanitized typed media folder name for `kind`; nil when empty.
    func mediaFolder(for kind: SourceMediaKind) -> String? {
        let name = Self.sanitizeName(mediaFolderNames[kind] ?? "").filter { $0 != "{" && $0 != "}" }
        return name.isEmpty ? nil : name
    }

    var missingMediaFolderKind: SourceMediaKind? {
        guard lacksMediaFolder else { return nil }
        return SourceMediaKind.allCases.first { kind in
            items.contains { $0.kind == kind } && mediaFolder(for: kind) == nil
        }
    }

    /// Sanitized `rootFolderName`; nil when empty. Braces are dropped so typed text
    /// is never read as a template token.
    var rootFolderOverride: String? {
        guard let raw = rootFolderName else { return nil }
        let name = Self.sanitizeName(raw).filter { $0 != "{" && $0 != "}" }
        return name.isEmpty ? nil : name
    }

    /// The top folder name the templates produce, used to pre-fill the field.
    var defaultRootFolderName: String? {
        guard organizationActive else { return nil }
        var plain = self
        plain.rootFolderName = nil
        guard let rel = plain.relativePaths(for: "/").first else { return nil }
        let parts = rel.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }

    /// The Camera/Sound folder name the templates produce for `kind`.
    func defaultMediaFolderName(for kind: SourceMediaKind) -> String? {
        guard !lacksMediaFolder, let p = organizedPreset(),
              let index = Self.mediaComponentIndex(in: Self.template(for: kind, in: p), kind: kind),
              let item = items.first(where: { $0.kind == kind }) ?? items.first else { return nil }
        var plain = self
        plain.mediaFolderNames[kind] = nil
        var probe = item
        probe.kind = kind
        plain.items = [probe]
        guard let rel = plain.relativePaths(for: "/").first else { return nil }
        let parts = rel.split(separator: "/")
        return index < parts.count - 1 ? String(parts[index]) : nil
    }

    private static func template(for kind: SourceMediaKind, in p: OrganizationPreset) -> String {
        FolderTreeBuilder.template(for: kind, in: p)
    }

    static func mediaComponentIndex(in template: String, kind: SourceMediaKind) -> Int? {
        FolderTreeBuilder.mediaComponentIndex(in: template, kind: kind)
    }

    static func replacingComponent(_ index: Int, of template: String, with name: String) -> String {
        var parts = template.split(separator: "/").map(String.init)
        guard index < parts.count else { return template }
        parts[index] = name
        return parts.joined(separator: "/")
    }

    /// Stores a typed name; one equal to the suggestion stores nothing.
    mutating func setFolderName(_ raw: String, root: Bool, kind: SourceMediaKind?) {
        if root {
            rootFolderName = raw == defaultRootFolderName ? nil : raw
        } else if let kind {
            let suggestion = lacksMediaFolder ? nil : defaultMediaFolderName(for: kind)
            mediaFolderNames[kind] = raw == suggestion ? nil : raw
        }
    }

    func isFolderNameEdited(root: Bool, kind: SourceMediaKind?) -> Bool {
        if root { return rootFolderOverride != nil }
        guard let kind, !lacksMediaFolder else { return false }
        return mediaFolder(for: kind) != nil
    }

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

    var effectiveCopyFolderContents: Bool {
        copyFolderContentsOverride ?? selectedPreset?.copyFolderContents ?? copyFolderContents
    }

    /// Without a preset the basic option is edited; with one, an override for this copy.
    mutating func setCopyFolderContents(_ value: Bool) {
        if let preset = selectedPreset {
            copyFolderContentsOverride = value == preset.copyFolderContents ? nil : value
        } else {
            copyFolderContentsOverride = nil
            copyFolderContents = value
        }
    }
    var effectiveHashListStyle: HashListStyle { selectedPreset?.hashListStyle ?? .ascMHL }

    // MARK: Run preset
    /// The preset the engine runs with (nil ⇒ no organization). A picked date lands
    /// on this copy only — never on a stored preset.
    func runPreset() -> OrganizationPreset? {
        guard var preset = organizedPreset() else { return nil }
        if organizationActive {
            if lacksMediaFolder {
                let base = preset.folderTemplate
                preset.folderTemplate = Self.appending(mediaFolder(for: .camera), to: base)
                preset.soundFolderTemplate = Self.appending(mediaFolder(for: .sound), to: base)
            } else {
                if let name = mediaFolder(for: .camera),
                   let index = Self.mediaComponentIndex(in: preset.folderTemplate, kind: .camera) {
                    preset.folderTemplate = Self.replacingComponent(index, of: preset.folderTemplate, with: name)
                }
                if let name = mediaFolder(for: .sound), !Self.isBlank(preset.soundFolderTemplate),
                   let index = Self.mediaComponentIndex(in: preset.soundFolderTemplate, kind: .sound) {
                    preset.soundFolderTemplate = Self.replacingComponent(index, of: preset.soundFolderTemplate,
                                                                         with: name)
                }
            }
            if let root = rootFolderOverride {
                preset.folderTemplate = Self.replacingComponent(0, of: preset.folderTemplate, with: root)
                if !Self.isBlank(preset.soundFolderTemplate) {
                    preset.soundFolderTemplate = Self.replacingComponent(0, of: preset.soundFolderTemplate,
                                                                         with: root)
                }
            }
        }
        return preset
    }

    private static func appending(_ folder: String?, to template: String) -> String {
        guard let folder else { return template }
        return template.hasSuffix("/") ? template + folder : template + "/" + folder
    }

    /// Stored or basic-mode preset with the date and the derived sound template,
    /// before the user's typed folder names.
    private func organizedPreset() -> OrganizationPreset? {
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
            // A preset without a sound template would send Sound cards to Camera_Media.
            if Self.isBlank(preset.soundFolderTemplate), preset.folderTemplate.contains("Camera_Media") {
                preset.soundFolderTemplate = preset.folderTemplate
                    .replacingOccurrences(of: "Camera_Media", with: "Sound_Media")
            }
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
            c.runInParallel = p.runInParallel
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
        case invalidRollName(String)
        case multipleFiles
        case missingMediaFolder(SourceMediaKind)

        var message: String {
            switch self {
            case .noSources: return "Nothing to copy."
            case .noDestination: return "Add a destination to continue."
            case .missingDestination(let p):
                return "Destination not found: \((p as NSString).lastPathComponent)."
            case .missingProject: return "Enter a project name."
            case .invalidRollName(let name):
                let chars = String(Array(Set(name.filter { NetflixNameValidator.prohibited.contains($0) })))
                return "\u{201C}\(name)\u{201D} contains characters Netflix prohibits (\(chars)). Rename the folder first."
            case .missingMediaFolder(let kind):
                return "Name the \(kind.displayName) folder in the preview below."
            case .multipleFiles:
                return "Several loose files can't be copied together yet — select a folder, or copy the files one at a time."
            }
        }
    }

    var blocker: Blocker? {
        if items.isEmpty { return .noSources }
        if destinations.isEmpty { return .noDestination }
        if let gone = destinations.first(where: { !pathExists($0) }) { return .missingDestination(gone) }
        if showsProjectField, sanitizedProject.isEmpty, rootFolderOverride == nil { return .missingProject }
        if let kind = missingMediaFolderKind { return .missingMediaFolder(kind) }
        if selectedPreset?.name == OrganizationPreset.netflixIngestName {
            for issue in NetflixNameValidator.validate(rollNames: items.map(\.name)) {
                if case .prohibitedChars(let name, _) = issue { return .invalidRollName(name) }
            }
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
    /// Short chips describing the chosen preset's options (nil with Preset = None).
    var presetChips: [String]? {
        guard let p = selectedPreset else { return nil }
        let verify = effectiveVerification == .off
            ? "No verification" : "\(effectiveVerification.displayName) check"
        let policy = duplicatePolicyWasMapped ? OrganizationPreset.DuplicatePolicy.skip : p.duplicatePolicy
        let existing: String
        switch policy {
        case .skip, .ask: existing = "Skip existing files"
        case .overwrite: existing = "Overwrite existing files"
        case .increment: existing = "Add counter if exists"
        case .verify: existing = "Verify existing files"
        }
        return [verify, existing, effectiveCopyFolderContents ? "Contents only" : "Whole folder",
                effectiveHashListStyle.shortName]
    }

    /// Tooltip for the "Ask each time" to Skip mapping (nil when it does not apply).
    var presetChipsHelp: String? {
        guard selectedPreset != nil, duplicatePolicyWasMapped else { return nil }
        return "The preset says \"Ask each time\"; Quick Copy skips existing files instead."
    }
}

// MARK: - Folder tree preview

extension QuickCopyFormModel {

    typealias TreeLine = FolderTreeLine

    private var treeSources: [FolderTreeBuilder.Source] {
        items.map { FolderTreeBuilder.Source(path: $0.path, isDirectory: $0.isDirectory, kind: $0.kind) }
    }

    private var treeOptions: FolderTreeBuilder.Options {
        var o = FolderTreeBuilder.Options()
        o.preset = runPreset()
        o.organizationActive = organizationActive
        o.copyContents = effectiveCopyFolderContents
        o.date = today
        o.metadata = ShootMetadata(episode: sanitizedProject, day: sanitizedDay)
        o.lacksMediaFolder = lacksMediaFolder
        o.hasTypedMediaFolder = { mediaFolder(for: $0) != nil }
        o.mediaIndexPreset = organizedPreset()
        o.pathExists = pathExists
        return o
    }

    /// Path of each item under `destination`, relative to it, resolved with the
    /// SAME function the engine uses so the preview cannot drift from what is written.
    func relativePaths(for destination: String) -> [String] {
        FolderTreeBuilder.relativePaths(for: destination, sources: treeSources, options: treeOptions)
    }

    func treePreview(for destination: String) -> [TreeLine] {
        FolderTreeBuilder.lines(for: destination, sources: treeSources, options: treeOptions)
    }

    func copyFolders(for destination: String) -> [String] {
        var seen = Set<String>()
        var folders: [String] = []
        for rel in relativePaths(for: destination) {
            let parent = (rel as NSString).deletingLastPathComponent
            let full = parent.isEmpty ? destination : (destination as NSString).appendingPathComponent(parent)
            if seen.insert(full).inserted { folders.append(full) }
        }
        return folders.isEmpty ? [destination] : folders
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
