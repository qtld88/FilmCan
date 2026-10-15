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
        let typed = Self.sanitizeName(project)
        if !typed.isEmpty { return typed }
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
        if let picked = pickedDate, organizationActive {
            preset.useCustomDate = true
            preset.customDate = picked
        }
        return preset
    }
}
