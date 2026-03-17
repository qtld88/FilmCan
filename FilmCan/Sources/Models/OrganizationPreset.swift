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
    var rsyncOptions: RsyncOptions = RsyncOptions()
    var logEnabled: Bool = true
    var logLocation: BackupConfiguration.LogLocation = .sameAsDestination
    var customLogPath: String = ""
    var logFileNameTemplate: String = "transfer_{datetime}"
    var useCustomDate: Bool = false
    var customDate: Date = Date()
    
    private enum CodingKeys: String, CodingKey {
        case id, name, folderTemplate, renameTemplate
        case useFolderTemplate, useRenameTemplate, renameOnlyPatterns
        case includePatterns, excludePatterns, copyOnlyPatterns
        case duplicatePolicy, duplicateCounterTemplate
        case copyFolderContents, runInParallel, rsyncOptions
        case logEnabled, logLocation, customLogPath, logFileNameTemplate
        case useCustomDate, customDate
    }
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Preset 1"
        folderTemplate = try c.decodeIfPresent(String.self, forKey: .folderTemplate) ?? ""
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
        rsyncOptions = try c.decodeIfPresent(RsyncOptions.self, forKey: .rsyncOptions) ?? RsyncOptions()
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
        try c.encode(rsyncOptions, forKey: .rsyncOptions)
        try c.encode(logEnabled, forKey: .logEnabled)
        try c.encode(logLocation, forKey: .logLocation)
        try c.encode(customLogPath, forKey: .customLogPath)
        try c.encode(logFileNameTemplate, forKey: .logFileNameTemplate)
        try c.encode(useCustomDate, forKey: .useCustomDate)
        try c.encode(customDate, forKey: .customDate)
    }
}
