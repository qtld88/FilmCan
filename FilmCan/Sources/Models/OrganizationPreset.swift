import Foundation

struct OrganizationPreset: Codable, Identifiable, Equatable {
    enum DuplicatePolicy: String, Codable, CaseIterable, Identifiable {
        case skip
        case overwrite
        case increment
        case verify
        case ask

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .skip: return "Skip"
            case .overwrite: return "Overwrite"
            case .increment: return "Add counter"
            case .verify: return "Verify using hash list"
            case .ask: return "Ask each time"
            }
        }
    }

    
    var id: UUID = UUID()
    var name: String = "Preset 1"
    var folderTemplate: String = ""
    /// Optional separate folder template for sources tagged as Sound (Netflix
    /// Sound_Media routing). Empty → sound sources use `folderTemplate` like camera.
    var soundFolderTemplate: String = ""
    var renameTemplate: String = ""
    var useFolderTemplate: Bool = false
    var useRenameTemplate: Bool = false
    var renameOnlyPatterns: [String] = []
    var includePatterns: [String] = []
    var excludePatterns: [String] = []
    var copyOnlyPatterns: [String] = []
    var duplicatePolicy: DuplicatePolicy = .ask
    var duplicateCounterTemplate: String = "_001"
    var copyFolderContents: Bool = false
    var runInParallel: Bool = false
    var engineOptions: EngineOptions = EngineOptions()
    var logEnabled: Bool = true
    var logLocation: BackupConfiguration.LogLocation = .sameAsDestination
    var customLogPath: String = ""
    var logFileNameTemplate: String = "transfer_{datetime}"
    var useCustomDate: Bool = false
    var customDate: Date = Date()
    
    private enum CodingKeys: String, CodingKey {
        case id, name, folderTemplate, soundFolderTemplate, renameTemplate
        case useFolderTemplate, useRenameTemplate, renameOnlyPatterns
        case includePatterns, excludePatterns, copyOnlyPatterns
        case duplicatePolicy, duplicateCounterTemplate
        case copyFolderContents, runInParallel, engineOptions
        case logEnabled, logLocation, customLogPath, logFileNameTemplate
        case useCustomDate, customDate
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Preset 1"
        folderTemplate = try c.decodeIfPresent(String.self, forKey: .folderTemplate) ?? ""
        soundFolderTemplate = try c.decodeIfPresent(String.self, forKey: .soundFolderTemplate) ?? ""
        renameTemplate = try c.decodeIfPresent(String.self, forKey: .renameTemplate) ?? ""
        useFolderTemplate = try c.decodeIfPresent(Bool.self, forKey: .useFolderTemplate)
            ?? !folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        useRenameTemplate = try c.decodeIfPresent(Bool.self, forKey: .useRenameTemplate)
            ?? !renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        renameOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .renameOnlyPatterns) ?? []
        includePatterns = try c.decodeIfPresent([String].self, forKey: .includePatterns) ?? []
        excludePatterns = try c.decodeIfPresent([String].self, forKey: .excludePatterns) ?? []
        copyOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .copyOnlyPatterns) ?? []
        duplicatePolicy = try c.decodeIfPresent(DuplicatePolicy.self, forKey: .duplicatePolicy) ?? .ask
        copyFolderContents = try c.decodeIfPresent(Bool.self, forKey: .copyFolderContents) ?? false
        runInParallel = try c.decodeIfPresent(Bool.self, forKey: .runInParallel) ?? false
        engineOptions = try c.decodeIfPresent(EngineOptions.self, forKey: .engineOptions) ?? EngineOptions()
        logEnabled = try c.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? true
        logLocation = try c.decodeIfPresent(BackupConfiguration.LogLocation.self, forKey: .logLocation) ?? .sameAsDestination
        customLogPath = try c.decodeIfPresent(String.self, forKey: .customLogPath) ?? ""
        logFileNameTemplate = try c.decodeIfPresent(String.self, forKey: .logFileNameTemplate) ?? "transfer_{datetime}"
        useCustomDate = try c.decodeIfPresent(Bool.self, forKey: .useCustomDate) ?? false
        customDate = try c.decodeIfPresent(Date.self, forKey: .customDate) ?? Date()
        
        duplicateCounterTemplate = try c.decodeIfPresent(String.self, forKey: .duplicateCounterTemplate) ?? "_001"
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(folderTemplate, forKey: .folderTemplate)
        try c.encode(soundFolderTemplate, forKey: .soundFolderTemplate)
        try c.encode(renameTemplate, forKey: .renameTemplate)
        try c.encode(useFolderTemplate, forKey: .useFolderTemplate)
        try c.encode(useRenameTemplate, forKey: .useRenameTemplate)
        try c.encode(renameOnlyPatterns, forKey: .renameOnlyPatterns)
        try c.encode(includePatterns, forKey: .includePatterns)
        try c.encode(excludePatterns, forKey: .excludePatterns)
        try c.encode(copyOnlyPatterns, forKey: .copyOnlyPatterns)
        try c.encode(duplicatePolicy, forKey: .duplicatePolicy)
        try c.encode(duplicateCounterTemplate, forKey: .duplicateCounterTemplate)
        try c.encode(copyFolderContents, forKey: .copyFolderContents)
        try c.encode(runInParallel, forKey: .runInParallel)
        try c.encode(engineOptions, forKey: .engineOptions)
        try c.encode(logEnabled, forKey: .logEnabled)
        try c.encode(logLocation, forKey: .logLocation)
        try c.encode(customLogPath, forKey: .customLogPath)
        try c.encode(logFileNameTemplate, forKey: .logFileNameTemplate)
        try c.encode(useCustomDate, forKey: .useCustomDate)
        try c.encode(customDate, forKey: .customDate)
    }
}

extension OrganizationPreset {
    /// Built-in preset matching Netflix Footage Ingest folder requirements:
    /// `YYYYMMDD_EP###_Day##_Unit/Camera_Media/[Camera_Format]/<Roll>`. The roll
    /// folder (source root) is appended automatically, so the template ends at the
    /// camera-format segment (which collapses when {cameraFormat} is empty).
    static let netflixIngestName = "Netflix Ingest"

    static func netflixIngest() -> OrganizationPreset {
        var p = OrganizationPreset()
        p.name = netflixIngestName
        p.useFolderTemplate = true
        p.folderTemplate = "{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}"
        p.soundFolderTemplate = "{date}_{episode}_{day}_{unit}/Sound_Media"
        return p
    }
}
