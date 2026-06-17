import Foundation

struct BackupConfiguration: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String = "New Backup"
    var sourcePaths: [String] = []
    var destinationPaths: [String] = []
    var rsyncOptions: RsyncOptions = RsyncOptions()
    var lastRsyncOptions: RsyncOptions? = nil
    var logEnabled: Bool = true
    var logLocation: LogLocation = .sameAsDestination
    var customLogPath: String = ""
    var logFileNameTemplate: String = "transfer_{datetime}"
    var selectedOrganizationPresetId: UUID?
    var organizationReuseByDestination: [String: OrganizationReuseInfo] = [:]
    var copyFolderContents: Bool = false
    /// Ignore prior hash lists and re-copy every file (disables resume skip).
    var forceRecopy: Bool = false
    // Netflix shoot metadata (used by the Netflix Ingest preset's folder tokens).
    var episode: String = ""
    var day: String = ""
    var unit: String = ""
    var cameraFormat: String = ""
    /// Hash-list format written by the engine (ASC MHL vs simple hidden).
    var hashListStyle: HashListStyle = .ascMHL
    var runInParallel: Bool = false
    /// How the FilmCan fan-out engine writes to multiple destinations.
    var destinationCopyMode: DestinationCopyMode = .automatic
    var sourceAutoDetectEnabled: Bool = false
    var sourceAutoDetectPatterns: [String] = []
    /// Camera/Sound tag per source path (absent ⇒ camera). Netflix routing.
    var sourceMediaKinds: [String: SourceMediaKind] = [:]
    /// Auto-tag a source as Sound when its path/volume matches one of these patterns.
    var soundAutoDetectEnabled: Bool = false
    var soundAutoDetectPatterns: [String] = []
    /// Editable Sound folder template for the Netflix preset (Sound_Media routing).
    var soundFolderTemplate: String = "{date}_{episode}_{day}_{unit}/Sound_Media"
    var destinationAutoDetectEnabled: Bool = false
    var destinationAutoDetectPatterns: [String] = []
    var duplicatePolicy: OrganizationPreset.DuplicatePolicy = .ask
    var duplicateCounterTemplate: String = "_001"
    var organizationFolderTemplate: String = ""
    var organizationRenameTemplate: String = ""
    var organizationUseFolderTemplate: Bool = false
    var organizationUseRenameTemplate: Bool = false
    var organizationRenameOnlyPatterns: [String] = []
    var organizationIncludePatterns: [String] = []
    var organizationExcludePatterns: [String] = []
    var organizationCopyOnlyPatterns: [String] = []
    var organizationUseCustomDate: Bool = false
    var organizationCustomDate: Date = Date()
    var offOrganizationFolderTemplate: String = ""
    var offOrganizationRenameTemplate: String = ""
    var offOrganizationUseFolderTemplate: Bool = false
    var offOrganizationUseRenameTemplate: Bool = false
    var offOrganizationRenameOnlyPatterns: [String] = []
    var offOrganizationIncludePatterns: [String] = []
    var offOrganizationExcludePatterns: [String] = []
    var offOrganizationCopyOnlyPatterns: [String] = []
    var offOrganizationUseCustomDate: Bool = false
    var offOrganizationCustomDate: Date = Date()
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var webhookTemplateFormatVersion: Int = 1

    enum LogLocation: String, Codable, CaseIterable {
        case sameAsDestination = "same"
        case custom = "custom"
    }
    
    // Custom decoder: migrate old single-source configs saved as "sourcePath"
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decodeIfPresent(UUID.self,   forKey: .id)           ?? UUID()
        name         = try c.decodeIfPresent(String.self, forKey: .name)         ?? "New Backup"
        destinationPaths = try c.decodeIfPresent([String].self, forKey: .destinationPaths) ?? []
        rsyncOptions = try c.decodeIfPresent(RsyncOptions.self, forKey: .rsyncOptions) ?? RsyncOptions()
        lastRsyncOptions = try c.decodeIfPresent(RsyncOptions.self, forKey: .lastRsyncOptions)
        logEnabled = try c.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? true
        logLocation  = try c.decodeIfPresent(LogLocation.self, forKey: .logLocation) ?? .sameAsDestination
        customLogPath = try c.decodeIfPresent(String.self, forKey: .customLogPath) ?? ""
        logFileNameTemplate = try c.decodeIfPresent(String.self, forKey: .logFileNameTemplate) ?? "transfer_{datetime}"
        selectedOrganizationPresetId = try c.decodeIfPresent(UUID.self, forKey: .selectedOrganizationPresetId)
        organizationReuseByDestination = try c.decodeIfPresent([String: OrganizationReuseInfo].self, forKey: .organizationReuseByDestination) ?? [:]
        copyFolderContents = try c.decodeIfPresent(Bool.self, forKey: .copyFolderContents) ?? false
        forceRecopy = try c.decodeIfPresent(Bool.self, forKey: .forceRecopy) ?? false
        episode = try c.decodeIfPresent(String.self, forKey: .episode) ?? ""
        day = try c.decodeIfPresent(String.self, forKey: .day) ?? ""
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        cameraFormat = try c.decodeIfPresent(String.self, forKey: .cameraFormat) ?? ""
        hashListStyle = try c.decodeIfPresent(HashListStyle.self, forKey: .hashListStyle) ?? .ascMHL
        runInParallel = try c.decodeIfPresent(Bool.self,   forKey: .runInParallel) ?? false
        destinationCopyMode = try c.decodeIfPresent(DestinationCopyMode.self, forKey: .destinationCopyMode) ?? .automatic
        sourceAutoDetectEnabled = try c.decodeIfPresent(Bool.self, forKey: .sourceAutoDetectEnabled) ?? false
        sourceAutoDetectPatterns = try c.decodeIfPresent([String].self, forKey: .sourceAutoDetectPatterns) ?? []
        sourceMediaKinds = try c.decodeIfPresent([String: SourceMediaKind].self, forKey: .sourceMediaKinds) ?? [:]
        soundAutoDetectEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundAutoDetectEnabled) ?? false
        soundAutoDetectPatterns = try c.decodeIfPresent([String].self, forKey: .soundAutoDetectPatterns) ?? []
        soundFolderTemplate = try c.decodeIfPresent(String.self, forKey: .soundFolderTemplate) ?? "{date}_{episode}_{day}_{unit}/Sound_Media"
        destinationAutoDetectEnabled = try c.decodeIfPresent(Bool.self, forKey: .destinationAutoDetectEnabled) ?? false
        destinationAutoDetectPatterns = try c.decodeIfPresent([String].self, forKey: .destinationAutoDetectPatterns) ?? []
        duplicatePolicy = try c.decodeIfPresent(OrganizationPreset.DuplicatePolicy.self, forKey: .duplicatePolicy) ?? .ask
        duplicateCounterTemplate = try c.decodeIfPresent(String.self, forKey: .duplicateCounterTemplate) ?? "_001"
        organizationFolderTemplate = try c.decodeIfPresent(String.self, forKey: .organizationFolderTemplate) ?? ""
        organizationRenameTemplate = try c.decodeIfPresent(String.self, forKey: .organizationRenameTemplate) ?? ""
        organizationUseFolderTemplate = try c.decodeIfPresent(Bool.self, forKey: .organizationUseFolderTemplate)
            ?? !organizationFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        organizationUseRenameTemplate = try c.decodeIfPresent(Bool.self, forKey: .organizationUseRenameTemplate)
            ?? !organizationRenameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        organizationRenameOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .organizationRenameOnlyPatterns) ?? []
        organizationIncludePatterns = try c.decodeIfPresent([String].self, forKey: .organizationIncludePatterns) ?? []
        organizationExcludePatterns = try c.decodeIfPresent([String].self, forKey: .organizationExcludePatterns) ?? []
        organizationCopyOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .organizationCopyOnlyPatterns) ?? []
        organizationUseCustomDate = try c.decodeIfPresent(Bool.self, forKey: .organizationUseCustomDate) ?? false
        organizationCustomDate = try c.decodeIfPresent(Date.self, forKey: .organizationCustomDate) ?? Date()
        offOrganizationFolderTemplate = try c.decodeIfPresent(String.self, forKey: .offOrganizationFolderTemplate) ?? organizationFolderTemplate
        offOrganizationRenameTemplate = try c.decodeIfPresent(String.self, forKey: .offOrganizationRenameTemplate) ?? organizationRenameTemplate
        offOrganizationUseFolderTemplate = try c.decodeIfPresent(Bool.self, forKey: .offOrganizationUseFolderTemplate) ?? organizationUseFolderTemplate
        offOrganizationUseRenameTemplate = try c.decodeIfPresent(Bool.self, forKey: .offOrganizationUseRenameTemplate) ?? organizationUseRenameTemplate
        offOrganizationRenameOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .offOrganizationRenameOnlyPatterns) ?? organizationRenameOnlyPatterns
        offOrganizationIncludePatterns = try c.decodeIfPresent([String].self, forKey: .offOrganizationIncludePatterns) ?? organizationIncludePatterns
        offOrganizationExcludePatterns = try c.decodeIfPresent([String].self, forKey: .offOrganizationExcludePatterns) ?? organizationExcludePatterns
        offOrganizationCopyOnlyPatterns = try c.decodeIfPresent([String].self, forKey: .offOrganizationCopyOnlyPatterns) ?? organizationCopyOnlyPatterns
        offOrganizationUseCustomDate = try c.decodeIfPresent(Bool.self, forKey: .offOrganizationUseCustomDate) ?? organizationUseCustomDate
        offOrganizationCustomDate = try c.decodeIfPresent(Date.self, forKey: .offOrganizationCustomDate) ?? organizationCustomDate
        createdAt    = try c.decodeIfPresent(Date.self,   forKey: .createdAt)    ?? Date()
        lastUsedAt   = try c.decodeIfPresent(Date.self,   forKey: .lastUsedAt)
        webhookTemplateFormatVersion = try c.decodeIfPresent(Int.self, forKey: .webhookTemplateFormatVersion) ?? 1
        sourcePaths = try c.decodeIfPresent([String].self, forKey: .sourcePaths) ?? []
    }
    
    // Explicit memberwise init used internally
    init() {}
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,               forKey: .id)
        try c.encode(name,             forKey: .name)
        try c.encode(sourcePaths,      forKey: .sourcePaths)
        try c.encode(destinationPaths, forKey: .destinationPaths)
        try c.encode(rsyncOptions,     forKey: .rsyncOptions)
        try c.encodeIfPresent(lastRsyncOptions, forKey: .lastRsyncOptions)
        try c.encode(logEnabled,       forKey: .logEnabled)
        try c.encode(logLocation,      forKey: .logLocation)
        try c.encode(customLogPath,    forKey: .customLogPath)
        try c.encode(logFileNameTemplate, forKey: .logFileNameTemplate)
        try c.encodeIfPresent(selectedOrganizationPresetId, forKey: .selectedOrganizationPresetId)
        try c.encode(organizationReuseByDestination, forKey: .organizationReuseByDestination)
        try c.encode(copyFolderContents, forKey: .copyFolderContents)
        try c.encode(forceRecopy, forKey: .forceRecopy)
        try c.encode(episode, forKey: .episode)
        try c.encode(day, forKey: .day)
        try c.encode(unit, forKey: .unit)
        try c.encode(cameraFormat, forKey: .cameraFormat)
        try c.encode(hashListStyle, forKey: .hashListStyle)
        try c.encode(runInParallel,    forKey: .runInParallel)
        try c.encode(destinationCopyMode, forKey: .destinationCopyMode)
        try c.encode(sourceAutoDetectEnabled, forKey: .sourceAutoDetectEnabled)
        try c.encode(sourceAutoDetectPatterns, forKey: .sourceAutoDetectPatterns)
        try c.encode(sourceMediaKinds, forKey: .sourceMediaKinds)
        try c.encode(soundAutoDetectEnabled, forKey: .soundAutoDetectEnabled)
        try c.encode(soundAutoDetectPatterns, forKey: .soundAutoDetectPatterns)
        try c.encode(soundFolderTemplate, forKey: .soundFolderTemplate)
        try c.encode(destinationAutoDetectEnabled, forKey: .destinationAutoDetectEnabled)
        try c.encode(destinationAutoDetectPatterns, forKey: .destinationAutoDetectPatterns)
        try c.encode(duplicatePolicy, forKey: .duplicatePolicy)
        try c.encode(duplicateCounterTemplate, forKey: .duplicateCounterTemplate)
        try c.encode(organizationFolderTemplate, forKey: .organizationFolderTemplate)
        try c.encode(organizationRenameTemplate, forKey: .organizationRenameTemplate)
        try c.encode(organizationUseFolderTemplate, forKey: .organizationUseFolderTemplate)
        try c.encode(organizationUseRenameTemplate, forKey: .organizationUseRenameTemplate)
        try c.encode(organizationRenameOnlyPatterns, forKey: .organizationRenameOnlyPatterns)
        try c.encode(organizationIncludePatterns, forKey: .organizationIncludePatterns)
        try c.encode(organizationExcludePatterns, forKey: .organizationExcludePatterns)
        try c.encode(organizationCopyOnlyPatterns, forKey: .organizationCopyOnlyPatterns)
        try c.encode(organizationUseCustomDate, forKey: .organizationUseCustomDate)
        try c.encode(organizationCustomDate, forKey: .organizationCustomDate)
        try c.encode(offOrganizationFolderTemplate, forKey: .offOrganizationFolderTemplate)
        try c.encode(offOrganizationRenameTemplate, forKey: .offOrganizationRenameTemplate)
        try c.encode(offOrganizationUseFolderTemplate, forKey: .offOrganizationUseFolderTemplate)
        try c.encode(offOrganizationUseRenameTemplate, forKey: .offOrganizationUseRenameTemplate)
        try c.encode(offOrganizationRenameOnlyPatterns, forKey: .offOrganizationRenameOnlyPatterns)
        try c.encode(offOrganizationIncludePatterns, forKey: .offOrganizationIncludePatterns)
        try c.encode(offOrganizationExcludePatterns, forKey: .offOrganizationExcludePatterns)
        try c.encode(offOrganizationCopyOnlyPatterns, forKey: .offOrganizationCopyOnlyPatterns)
        try c.encode(offOrganizationUseCustomDate, forKey: .offOrganizationUseCustomDate)
        try c.encode(offOrganizationCustomDate, forKey: .offOrganizationCustomDate)
        try c.encode(createdAt,        forKey: .createdAt)
        try c.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try c.encode(webhookTemplateFormatVersion, forKey: .webhookTemplateFormatVersion)
    }

    private enum CodingKeys: String, CodingKey {
        case episode, day, unit, cameraFormat, hashListStyle
        case id, name, sourcePaths, destinationPaths, rsyncOptions, lastRsyncOptions
        case logEnabled, logLocation, customLogPath, runInParallel, destinationCopyMode, createdAt, lastUsedAt, webhookTemplateFormatVersion
        case sourceAutoDetectEnabled, sourceAutoDetectPatterns
        case sourceMediaKinds, soundAutoDetectEnabled, soundAutoDetectPatterns, soundFolderTemplate
        case destinationAutoDetectEnabled, destinationAutoDetectPatterns
        case logFileNameTemplate
        case selectedOrganizationPresetId, organizationReuseByDestination, copyFolderContents, forceRecopy
        case duplicatePolicy, duplicateCounterTemplate
        case organizationFolderTemplate, organizationRenameTemplate
        case organizationUseFolderTemplate, organizationUseRenameTemplate
        case organizationRenameOnlyPatterns
        case organizationIncludePatterns, organizationExcludePatterns, organizationCopyOnlyPatterns
        case organizationUseCustomDate, organizationCustomDate
        case offOrganizationFolderTemplate, offOrganizationRenameTemplate
        case offOrganizationUseFolderTemplate, offOrganizationUseRenameTemplate
        case offOrganizationRenameOnlyPatterns
        case offOrganizationIncludePatterns, offOrganizationExcludePatterns, offOrganizationCopyOnlyPatterns
        case offOrganizationUseCustomDate, offOrganizationCustomDate
    }
    
    var isValid: Bool {
        !sourcePaths.isEmpty &&
        !destinationPaths.isEmpty &&
        sourcePaths.allSatisfy { FileManager.default.fileExists(atPath: $0) } &&
        !name.isEmpty &&
        rsyncOptions.isValid
    }
    
    static var empty: BackupConfiguration {
        BackupConfiguration()
    }
    
    static var sample: BackupConfiguration {
        var config = BackupConfiguration()
        config.name = "Sample Backup"
        config.sourcePaths = ["/Users/sample/Documents"]
        config.destinationPaths = ["/Users/sample/Backups/Documents"]
        return config
    }
}

struct OrganizationReuseInfo: Codable, Equatable {
    var presetId: UUID?
    var sourceRoots: [String: String] = [:]
}

/// How the FilmCan fan-out engine writes to multiple destinations.
enum DestinationCopyMode: String, Codable, CaseIterable, Identifiable {
    /// Decide per run from drive type: parallel fan-out when every destination
    /// is an SSD, sequential (one at a time) when any destination is a spinning
    /// disk / network volume.
    case automatic
    /// Always read the source once and write to all destinations at the same time.
    case parallel
    /// Copy to one destination fully before starting the next (gentler on a
    /// shared bus or HDDs; re-reads the source per destination).
    case sequential

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .automatic:  return "Automatic (by drive type)"
        case .parallel:   return "All destinations at once"
        case .sequential: return "One destination at a time"
        }
    }

    var description: String {
        switch self {
        case .automatic:  return "Parallel for SSDs, sequential for hard drives"
        case .parallel:   return "Fastest with multiple SSDs — reads the source once"
        case .sequential: return "Gentler on shared buses and hard drives"
        }
    }
}
