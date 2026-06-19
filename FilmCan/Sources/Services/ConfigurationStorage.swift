import Foundation
import Combine

class ConfigurationStorage: ObservableObject {
    static let shared = ConfigurationStorage()
    
    @Published var configurations: [BackupConfiguration] = []
    @Published var lastUsedConfigId: UUID?
    @Published var organizationPresets: [OrganizationPreset] = []
    @Published var transferHistory: [TransferHistoryEntry] = []
    @Published private(set) var lastSaveError: String?
    
    private let fileManager = FileManager.default
    private let configFileURL: URL
    private let presetsFileURL: URL
    private let historyFileURL: URL
    private let configBackupFileURL: URL
    private let presetsBackupFileURL: URL
    private let historyBackupFileURL: URL
    private let totalTransferCountKey = "totalTransferCount"
    private static let storageFolderName = "FilmCan"
    private static let legacyStorageFolderNames = ["RushesTransfer"]
    
    private static func resolveStorageFolderURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent(storageFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func migrateLegacyStorageIfNeeded(fileManager: FileManager, targetFolder: URL) {
        let targetConfig = targetFolder.appendingPathComponent("configs.json")
        let targetPresets = targetFolder.appendingPathComponent("presets.json")
        let targetHistory = targetFolder.appendingPathComponent("history.json")

        // Nothing to migrate if all target files already exist.
        if fileManager.fileExists(atPath: targetConfig.path)
            && fileManager.fileExists(atPath: targetPresets.path)
            && fileManager.fileExists(atPath: targetHistory.path) {
            return
        }

        let appSupport = targetFolder.deletingLastPathComponent()
        for legacyName in legacyStorageFolderNames {
            let legacyFolder = appSupport.appendingPathComponent(legacyName, isDirectory: true)
            guard fileManager.fileExists(atPath: legacyFolder.path) else { continue }

            copyFirstExisting(
                fileManager: fileManager,
                from: legacyFolder,
                candidates: ["configs.json", "configurations.json"],
                to: targetConfig
            )
            copyFirstExisting(
                fileManager: fileManager,
                from: legacyFolder,
                candidates: ["presets.json", "organizationPresets.json"],
                to: targetPresets
            )
            copyFirstExisting(
                fileManager: fileManager,
                from: legacyFolder,
                candidates: ["history.json", "transferHistory.json"],
                to: targetHistory
            )

            if fileManager.fileExists(atPath: targetConfig.path)
                && fileManager.fileExists(atPath: targetPresets.path)
                && fileManager.fileExists(atPath: targetHistory.path) {
                break
            }
        }
    }

    private static func copyFirstExisting(
        fileManager: FileManager,
        from folder: URL,
        candidates: [String],
        to destination: URL
    ) {
        guard !fileManager.fileExists(atPath: destination.path) else { return }
        for name in candidates {
            let source = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            do {
                try fileManager.copyItem(at: source, to: destination)
                return
            } catch {
                continue
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let lastUsedKey = "lastUsedConfigurationId"

    private struct MoviesHistoryExport: Codable {
        let configurations: [BackupConfiguration]
        let transferHistory: [TransferHistoryEntry]
        let lastUsedConfigId: UUID?
    }
    
    private init() {
        let storageFolder = Self.resolveStorageFolderURL(fileManager: fileManager)
        Self.migrateLegacyStorageIfNeeded(fileManager: fileManager, targetFolder: storageFolder)
        configFileURL = storageFolder.appendingPathComponent("configs.json")
        presetsFileURL = storageFolder.appendingPathComponent("presets.json")
        historyFileURL = storageFolder.appendingPathComponent("history.json")
        configBackupFileURL = configFileURL.appendingPathExtension("bak")
        presetsBackupFileURL = presetsFileURL.appendingPathExtension("bak")
        historyBackupFileURL = historyFileURL.appendingPathExtension("bak")
        load()
    }

    init(baseDirectory: URL) {
        configFileURL = baseDirectory.appendingPathComponent("configs.json")
        presetsFileURL = baseDirectory.appendingPathComponent("presets.json")
        historyFileURL = baseDirectory.appendingPathComponent("history.json")
        configBackupFileURL = configFileURL.appendingPathExtension("bak")
        presetsBackupFileURL = presetsFileURL.appendingPathExtension("bak")
        historyBackupFileURL = historyFileURL.appendingPathExtension("bak")
        load()
    }
    
    // MARK: - CRUD Operations
    
    func add(_ config: BackupConfiguration) {
        configurations.append(config)
        save()
    }
    
    func update(_ config: BackupConfiguration) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
            save()
        }
    }
    
    func delete(_ config: BackupConfiguration) {
        configurations.removeAll { $0.id == config.id }
        save()
    }
    
    func delete(at indexSet: IndexSet) {
        configurations.remove(atOffsets: indexSet)
        save()
    }

    func moveConfig(from sourceId: UUID, to destinationId: UUID) {
        guard let fromIndex = configurations.firstIndex(where: { $0.id == sourceId }),
              let toIndex = configurations.firstIndex(where: { $0.id == destinationId }),
              fromIndex != toIndex else { return }
        var updated = configurations
        let item = updated.remove(at: fromIndex)
        let insertionIndex = min(max(toIndex, 0), updated.count)
        updated.insert(item, at: insertionIndex)
        configurations = updated
        save()
    }
    
    // MARK: - Persistence
    
    @discardableResult
    func save() -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            // Encode ALL three before any write so an encode error can't leave a
            // partially-updated set on disk.
            let configData  = try encoder.encode(configurations)
            let presetData  = try encoder.encode(organizationPresets)
            let historyData = try encoder.encode(transferHistory)
            try writeWithBackup(configData,  to: configFileURL,  backupURL: configBackupFileURL)
            try writeWithBackup(presetData,  to: presetsFileURL, backupURL: presetsBackupFileURL)
            try writeWithBackup(historyData, to: historyFileURL, backupURL: historyBackupFileURL)
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error.localizedDescription
            #if DEBUG
            DebugLog.warn("Failed to save configurations: \(error)")
            #endif
            return false
        }
    }
    
    func load() {
        let hasConfig = fileManager.fileExists(atPath: configFileURL.path)
            || fileManager.fileExists(atPath: configBackupFileURL.path)
        guard hasConfig else {
            configurations = []
            organizationPresets = []
            transferHistory = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let loadedConfigs: [BackupConfiguration] = decodeWithFallback(
            type: [BackupConfiguration].self,
            primaryURL: configFileURL,
            backupURL: configBackupFileURL,
            decoder: decoder
        ) {
            configurations = loadedConfigs
        } else {
            #if DEBUG
            DebugLog.warn("Failed to load configurations from primary and backup files.")
            #endif
            configurations = []
        }
        
        if fileManager.fileExists(atPath: presetsFileURL.path) || fileManager.fileExists(atPath: presetsBackupFileURL.path) {
            if let loadedPresets: [OrganizationPreset] = decodeWithFallback(
                type: [OrganizationPreset].self,
                primaryURL: presetsFileURL,
                backupURL: presetsBackupFileURL,
                decoder: decoder
            ) {
                organizationPresets = loadedPresets
            } else {
                #if DEBUG
                DebugLog.warn("Failed to load presets from primary and backup files.")
                #endif
                organizationPresets = []
            }
        } else {
            organizationPresets = []
        }

        if fileManager.fileExists(atPath: historyFileURL.path) || fileManager.fileExists(atPath: historyBackupFileURL.path) {
            if let loadedHistory: [TransferHistoryEntry] = decodeWithFallback(
                type: [TransferHistoryEntry].self,
                primaryURL: historyFileURL,
                backupURL: historyBackupFileURL,
                decoder: decoder
            ) {
                transferHistory = loadedHistory
            } else {
                #if DEBUG
                DebugLog.warn("Failed to load history from primary and backup files.")
                #endif
                transferHistory = []
            }
        } else {
            transferHistory = []
        }
        seedTotalTransferCountIfNeeded()
        
        // Load last used
        if let lastUsedIdString = userDefaults.string(forKey: lastUsedKey),
           let lastUsedId = UUID(uuidString: lastUsedIdString) {
            lastUsedConfigId = lastUsedId
        }
    }

    private func writeWithBackup(_ data: Data, to destination: URL, backupURL: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }
            try? fileManager.copyItem(at: destination, to: backupURL)
        }
        try data.write(to: destination, options: .atomic)
    }

    private func decodeWithFallback<T: Decodable>(
        type: T.Type,
        primaryURL: URL,
        backupURL: URL,
        decoder: JSONDecoder
    ) -> T? {
        if let data = try? Data(contentsOf: primaryURL),
           let decoded = try? decoder.decode(T.self, from: data) {
            return decoded
        }
        if let data = try? Data(contentsOf: backupURL),
           let decoded = try? decoder.decode(T.self, from: data) {
            return decoded
        }
        return nil
    }
    
    func markAsUsed(_ config: BackupConfiguration) {
        lastUsedConfigId = config.id
        userDefaults.set(config.id.uuidString, forKey: lastUsedKey)
        
        // Update lastUsedAt
        if var updatedConfig = configurations.first(where: { $0.id == config.id }) {
            updatedConfig.lastUsedAt = Date()
            update(updatedConfig)
        }
    }

    func setLastSelectedConfigId(_ id: UUID?) {
        lastUsedConfigId = id
        if let id {
            userDefaults.set(id.uuidString, forKey: lastUsedKey)
        } else {
            userDefaults.removeObject(forKey: lastUsedKey)
        }
    }
    
    func getLastUsed() -> BackupConfiguration? {
        guard let id = lastUsedConfigId else { return nil }
        return configurations.first { $0.id == id }
    }
    
    // MARK: - Remember Last Paths
    
    private let lastSourceKey = "lastSourcePath"
    private let lastDestKey = "lastDestinationPath"
    
    var lastSourcePath: String? {
        get { userDefaults.string(forKey: lastSourceKey) }
        set { userDefaults.set(newValue, forKey: lastSourceKey) }
    }
    
    var lastDestinationPath: String? {
        get { userDefaults.string(forKey: lastDestKey) }
        set { userDefaults.set(newValue, forKey: lastDestKey) }
    }

    // MARK: - Organization Presets

    func addPreset(_ preset: OrganizationPreset) {
        organizationPresets.append(preset)
        save()
    }

    func updatePreset(_ preset: OrganizationPreset) {
        if let index = organizationPresets.firstIndex(where: { $0.id == preset.id }) {
            organizationPresets[index] = preset
            save()
        }
    }

    func deletePreset(_ preset: OrganizationPreset) {
        organizationPresets.removeAll { $0.id == preset.id }
        save()
    }

    // MARK: - Import / Export

    func exportPresetsData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(organizationPresets)
    }

    func exportMoviesHistoryData() throws -> Data {
        let allIds = Set(configurations.map(\.id))
        return try exportMoviesHistoryData(for: allIds)
    }

    func exportMoviesHistoryData(for configIds: Set<UUID>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let filteredConfigs = configurations.filter { configIds.contains($0.id) }
        let filteredHistory = transferHistory.filter { entry in
            entry.configId.map(configIds.contains) ?? false
        }
        let filteredLastUsed = lastUsedConfigId.flatMap { configIds.contains($0) ? $0 : nil }
        let payload = MoviesHistoryExport(
            configurations: filteredConfigs,
            transferHistory: filteredHistory,
            lastUsedConfigId: filteredLastUsed
        )
        return try encoder.encode(payload)
    }

    func importPresets(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let incoming = try decoder.decode([OrganizationPreset].self, from: data)
        var updated = organizationPresets
        for preset in incoming {
            if let index = updated.firstIndex(where: { $0.id == preset.id }) {
                updated[index] = preset
            } else {
                updated.append(preset)
            }
        }
        organizationPresets = updated
        save()
    }

    func importMoviesHistory(from data: Data, retentionLimit: Int) throws {
        let payload = try decodeMoviesHistoryPayload(from: data)
        applyMoviesHistoryImport(payload, retentionLimit: retentionLimit)
    }

    func importMoviesHistory(from data: Data, retentionLimit: Int, selectedConfigIds: Set<UUID>) throws {
        guard !selectedConfigIds.isEmpty else { return }
        let payload = try decodeMoviesHistoryPayload(from: data)
        let filteredConfigs = payload.configurations.filter { selectedConfigIds.contains($0.id) }
        let filteredHistory = payload.transferHistory.filter { entry in
            entry.configId.map(selectedConfigIds.contains) ?? false
        }
        let filteredLastUsed = payload.lastUsedConfigId.flatMap { selectedConfigIds.contains($0) ? $0 : nil }
        let filteredPayload = MoviesHistoryExport(
            configurations: filteredConfigs,
            transferHistory: filteredHistory,
            lastUsedConfigId: filteredLastUsed
        )
        applyMoviesHistoryImport(filteredPayload, retentionLimit: retentionLimit)
    }

    func decodeMoviesHistoryConfigurations(from data: Data) throws -> [BackupConfiguration] {
        try decodeMoviesHistoryPayload(from: data).configurations
    }

    private func decodeMoviesHistoryPayload(from data: Data) throws -> MoviesHistoryExport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MoviesHistoryExport.self, from: data)
    }

    private func applyMoviesHistoryImport(_ payload: MoviesHistoryExport, retentionLimit: Int) {
        var updatedConfigs = configurations
        for config in payload.configurations {
            if let index = updatedConfigs.firstIndex(where: { $0.id == config.id }) {
                updatedConfigs[index] = config
            } else {
                updatedConfigs.append(config)
            }
        }
        configurations = updatedConfigs

        var updatedHistory = transferHistory
        for entry in payload.transferHistory {
            if let index = updatedHistory.firstIndex(where: { $0.id == entry.id }) {
                updatedHistory[index] = entry
            } else {
                updatedHistory.append(entry)
            }
        }
        updatedHistory.sort { $0.endedAt > $1.endedAt }
        if retentionLimit > 0, updatedHistory.count > retentionLimit {
            updatedHistory = Array(updatedHistory.prefix(retentionLimit))
        }
        transferHistory = updatedHistory

        if let lastUsed = payload.lastUsedConfigId {
            lastUsedConfigId = lastUsed
            userDefaults.set(lastUsed.uuidString, forKey: lastUsedKey)
        }

        seedTotalTransferCountIfNeeded()
        save()
    }

    func appendHistory(_ entry: TransferHistoryEntry, retentionLimit: Int) {
        transferHistory.insert(entry, at: 0)
        if retentionLimit > 0, transferHistory.count > retentionLimit {
            transferHistory = Array(transferHistory.prefix(retentionLimit))
        }
        incrementTotalTransferCount()
        save()
    }

    func clearHistory() {
        transferHistory = []
        save()
    }

    func clearHistory(for configId: UUID) {
        transferHistory.removeAll { $0.configId == configId }
        save()
    }

    func deleteHistoryEntry(_ entry: TransferHistoryEntry) {
        transferHistory.removeAll { $0.id == entry.id }
        save()
    }

    var totalTransferCount: Int {
        get { userDefaults.integer(forKey: totalTransferCountKey) }
        set { userDefaults.set(newValue, forKey: totalTransferCountKey) }
    }

    private func incrementTotalTransferCount() {
        totalTransferCount = max(0, totalTransferCount) + 1
    }

    private func seedTotalTransferCountIfNeeded() {
        let stored = userDefaults.integer(forKey: totalTransferCountKey)
        if userDefaults.object(forKey: totalTransferCountKey) == nil || stored < transferHistory.count {
            totalTransferCount = transferHistory.count
        }
    }
}
