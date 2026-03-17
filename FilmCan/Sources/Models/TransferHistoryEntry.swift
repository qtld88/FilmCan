import Foundation

struct TransferHistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var configId: UUID?
    var configName: String
    var startedAt: Date
    var endedAt: Date
    var success: Bool
    var sources: [String]
    var destinations: [String]
    var results: [TransferResultRecord]
    var options: TransferOptionsSnapshot
    var hashListPath: String?
    var hashRoots: [String] = []
}

struct TransferResultRecord: Codable, Identifiable {
    var id: UUID = UUID()
    var destination: String
    var success: Bool
    var errorMessage: String?
    var warningMessage: String?
    var filesTransferred: Int
    var filesSkipped: Int
    var bytesTransferred: Int64
    var totalBytes: Int64 = 0
    var startTime: Date
    var endTime: Date?
    var logFilePath: String?
    var hashListPath: String?
    var hashRoots: [String] = []
    var visibleFilesTransferred: Int?
    var visibleFilesSkipped: Int?
    var wasPaused: Bool = false
    var wasVerified: Bool = false
    var organizationPresetName: String?
    var duplicatePolicy: String?
    var duplicateHits: Int = 0
}

struct TransferOptionsSnapshot: Codable, Equatable {
    var copyFolderContents: Bool
    var runInParallel: Bool
    var organizationPresetName: String?
    var logEnabled: Bool
    var copyEngine: String
    var duplicatePolicy: String
    var duplicateCounterTemplate: String
    var useChecksum: Bool
    var checksumChoice: String
    var postVerify: Bool
    var onlyCopyChanged: Bool
    var reuseOrganizedFiles: Bool
    var allowResume: Bool
    var deleteExtraFiles: Bool
    var updateInPlace: Bool
    var customArgs: String
}

extension TransferOptionsSnapshot {
    private enum CodingKeys: String, CodingKey {
        case copyFolderContents
        case runInParallel
        case organizationPresetName
        case logEnabled
        case copyEngine
        case duplicatePolicy
        case duplicateCounterTemplate
        case useChecksum
        case checksumChoice
        case postVerify
        case onlyCopyChanged
        case reuseOrganizedFiles
        case allowResume
        case deleteExtraFiles
        case updateInPlace
        case customArgs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        copyFolderContents = try c.decodeIfPresent(Bool.self, forKey: .copyFolderContents) ?? false
        runInParallel = try c.decodeIfPresent(Bool.self, forKey: .runInParallel) ?? false
        organizationPresetName = try c.decodeIfPresent(String.self, forKey: .organizationPresetName)
        logEnabled = try c.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? true
        copyEngine = try c.decodeIfPresent(String.self, forKey: .copyEngine) ?? CopyEngine.rsync.rawValue
        duplicatePolicy = try c.decodeIfPresent(String.self, forKey: .duplicatePolicy) ?? OrganizationPreset.DuplicatePolicy.increment.rawValue
        duplicateCounterTemplate = try c.decodeIfPresent(String.self, forKey: .duplicateCounterTemplate) ?? "_001"
        useChecksum = try c.decodeIfPresent(Bool.self, forKey: .useChecksum) ?? false
        checksumChoice = try c.decodeIfPresent(String.self, forKey: .checksumChoice) ?? FilmCanHashAlgorithm.xxh128.rawValue
        postVerify = try c.decodeIfPresent(Bool.self, forKey: .postVerify) ?? false
        onlyCopyChanged = try c.decodeIfPresent(Bool.self, forKey: .onlyCopyChanged) ?? false
        reuseOrganizedFiles = try c.decodeIfPresent(Bool.self, forKey: .reuseOrganizedFiles) ?? false
        allowResume = try c.decodeIfPresent(Bool.self, forKey: .allowResume) ?? false
        deleteExtraFiles = try c.decodeIfPresent(Bool.self, forKey: .deleteExtraFiles) ?? false
        updateInPlace = try c.decodeIfPresent(Bool.self, forKey: .updateInPlace) ?? false
        customArgs = try c.decodeIfPresent(String.self, forKey: .customArgs) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(copyFolderContents, forKey: .copyFolderContents)
        try c.encode(runInParallel, forKey: .runInParallel)
        try c.encodeIfPresent(organizationPresetName, forKey: .organizationPresetName)
        try c.encode(logEnabled, forKey: .logEnabled)
        try c.encode(copyEngine, forKey: .copyEngine)
        try c.encode(duplicatePolicy, forKey: .duplicatePolicy)
        try c.encode(duplicateCounterTemplate, forKey: .duplicateCounterTemplate)
        try c.encode(useChecksum, forKey: .useChecksum)
        try c.encode(checksumChoice, forKey: .checksumChoice)
        try c.encode(postVerify, forKey: .postVerify)
        try c.encode(onlyCopyChanged, forKey: .onlyCopyChanged)
        try c.encode(reuseOrganizedFiles, forKey: .reuseOrganizedFiles)
        try c.encode(allowResume, forKey: .allowResume)
        try c.encode(deleteExtraFiles, forKey: .deleteExtraFiles)
        try c.encode(updateInPlace, forKey: .updateInPlace)
        try c.encode(customArgs, forKey: .customArgs)
    }
}

extension TransferResultRecord {
    private enum CodingKeys: String, CodingKey {
        case id, destination, success, errorMessage, warningMessage, filesTransferred, filesSkipped, bytesTransferred
        case totalBytes, startTime, endTime, logFilePath, hashListPath, hashRoots
        case visibleFilesTransferred, visibleFilesSkipped, wasPaused, wasVerified
        case organizationPresetName, duplicatePolicy, duplicateHits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        destination = try c.decodeIfPresent(String.self, forKey: .destination) ?? ""
        success = try c.decodeIfPresent(Bool.self, forKey: .success) ?? false
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        warningMessage = try c.decodeIfPresent(String.self, forKey: .warningMessage)
        filesTransferred = try c.decodeIfPresent(Int.self, forKey: .filesTransferred) ?? 0
        filesSkipped = try c.decodeIfPresent(Int.self, forKey: .filesSkipped) ?? 0
        bytesTransferred = try c.decodeIfPresent(Int64.self, forKey: .bytesTransferred) ?? 0
        totalBytes = try c.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        startTime = try c.decodeIfPresent(Date.self, forKey: .startTime) ?? Date()
        endTime = try c.decodeIfPresent(Date.self, forKey: .endTime)
        logFilePath = try c.decodeIfPresent(String.self, forKey: .logFilePath)
        hashListPath = try c.decodeIfPresent(String.self, forKey: .hashListPath)
        hashRoots = try c.decodeIfPresent([String].self, forKey: .hashRoots) ?? []
        visibleFilesTransferred = try c.decodeIfPresent(Int.self, forKey: .visibleFilesTransferred)
        visibleFilesSkipped = try c.decodeIfPresent(Int.self, forKey: .visibleFilesSkipped)
        wasPaused = try c.decodeIfPresent(Bool.self, forKey: .wasPaused) ?? false
        wasVerified = try c.decodeIfPresent(Bool.self, forKey: .wasVerified) ?? false
        organizationPresetName = try c.decodeIfPresent(String.self, forKey: .organizationPresetName)
        duplicatePolicy = try c.decodeIfPresent(String.self, forKey: .duplicatePolicy)
        duplicateHits = try c.decodeIfPresent(Int.self, forKey: .duplicateHits) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(destination, forKey: .destination)
        try c.encode(success, forKey: .success)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(warningMessage, forKey: .warningMessage)
        try c.encode(filesTransferred, forKey: .filesTransferred)
        try c.encode(filesSkipped, forKey: .filesSkipped)
        try c.encode(bytesTransferred, forKey: .bytesTransferred)
        try c.encode(totalBytes, forKey: .totalBytes)
        try c.encode(startTime, forKey: .startTime)
        try c.encodeIfPresent(endTime, forKey: .endTime)
        try c.encodeIfPresent(logFilePath, forKey: .logFilePath)
        try c.encodeIfPresent(hashListPath, forKey: .hashListPath)
        try c.encode(hashRoots, forKey: .hashRoots)
        try c.encodeIfPresent(visibleFilesTransferred, forKey: .visibleFilesTransferred)
        try c.encodeIfPresent(visibleFilesSkipped, forKey: .visibleFilesSkipped)
        try c.encode(wasPaused, forKey: .wasPaused)
        try c.encode(wasVerified, forKey: .wasVerified)
        try c.encodeIfPresent(organizationPresetName, forKey: .organizationPresetName)
        try c.encodeIfPresent(duplicatePolicy, forKey: .duplicatePolicy)
        try c.encode(duplicateHits, forKey: .duplicateHits)
    }

    init(from result: TransferResult) {
        destination = result.destination
        success = result.success
        errorMessage = result.errorMessage
        warningMessage = result.warningMessage
        filesTransferred = result.filesTransferred
        filesSkipped = result.filesSkipped
        bytesTransferred = result.bytesTransferred
        totalBytes = result.totalBytes
        startTime = result.startTime
        endTime = result.endTime
        logFilePath = result.logFilePath
        hashListPath = result.hashListPath
        hashRoots = result.hashRoots
        visibleFilesTransferred = result.visibleFilesTransferred
        visibleFilesSkipped = result.visibleFilesSkipped
        wasPaused = result.wasPaused
        wasVerified = result.wasVerified
        organizationPresetName = result.organizationPresetName
        duplicatePolicy = result.duplicatePolicy?.rawValue
        duplicateHits = result.duplicateHits
    }
}

extension TransferOptionsSnapshot {
    init(config: BackupConfiguration, presetName: String?) {
        copyFolderContents = config.copyFolderContents
        runInParallel = config.runInParallel
        organizationPresetName = presetName
        logEnabled = config.logEnabled
        copyEngine = config.rsyncOptions.copyEngine.rawValue
        duplicatePolicy = config.duplicatePolicy.rawValue
        duplicateCounterTemplate = config.duplicateCounterTemplate
        useChecksum = config.rsyncOptions.useChecksum
        checksumChoice = FilmCanHashAlgorithm.xxh128.rawValue
        postVerify = config.rsyncOptions.postVerify
        onlyCopyChanged = config.rsyncOptions.onlyCopyChanged
        reuseOrganizedFiles = config.rsyncOptions.reuseOrganizedFiles
        allowResume = config.rsyncOptions.allowResume
        deleteExtraFiles = config.rsyncOptions.delete
        updateInPlace = config.rsyncOptions.inplace
        customArgs = config.rsyncOptions.customArgs
    }
}
