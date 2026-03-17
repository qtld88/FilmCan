import Foundation
import Combine

class ConfigurationStorage: ObservableObject {
    static let shared = ConfigurationStorage()
    
    @Published var configurations: [BackupConfiguration] = []
    @Published var lastUsedConfigId: UUID?
    @Published var organizationPresets: [OrganizationPreset] = []
    @Published var transferHistory: [TransferHistoryEntry] = []
    
    private let fileManager = FileManager.default
    private let configFileURL: URL
    private let presetsFileURL: URL
    private let historyFileURL: URL
    private let totalTransferCountKey = "totalTransferCount"
    
    private static func resolveConfigFileURL(fileManager: FileManager) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("FilmCan", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("configs.json")
    }
    
    private let userDefaults = UserDefaults.standard
    private let lastUsedKey = "lastUsedConfigurationId"

    private struct MoviesHistoryExport: Codable {
        let configurations: [BackupConfiguration]
        let transferHistory: [TransferHistoryEntry]
        let lastUsedConfigId: UUID?
    }
    
    private init() {
        configFileURL = Self.resolveConfigFileURL(fileManager: fileManager)
        presetsFileURL = configFileURL.deletingLastPathComponent().appendingPathComponent("presets.json")
        historyFileURL = configFileURL.deletingLastPathComponent().appendingPathComponent("history.json")
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
    
    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(configurations)
            try data.write(to: configFileURL)
            let presetData = try encoder.encode(organizationPresets)
            try presetData.write(to: presetsFileURL)
            let historyData = try encoder.encode(transferHistory)
            try historyData.write(to: historyFileURL)
        } catch {
            #if DEBUG
            DebugLog.warn("Failed to save configurations: \(error)")
            #endif
        }
    }
    
    func load() {
        guard fileManager.fileExists(atPath: configFileURL.path) else {
            configurations = []
            organizationPresets = []
            transferHistory = []
            return
        }
        
        do {
            let data = try Data(contentsOf: configFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            configurations = try decoder.decode([BackupConfiguration].self, from: data)
        } catch {
            #if DEBUG
            DebugLog.warn("Failed to load configurations: \(error)")
            #endif
            configurations = []
        }
        
        if fileManager.fileExists(atPath: presetsFileURL.path) {
            do {
                let data = try Data(contentsOf: presetsFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                organizationPresets = try decoder.decode([OrganizationPreset].self, from: data)
            } catch {
                #if DEBUG
                DebugLog.warn("Failed to load presets: \(error)")
                #endif
                organizationPresets = []
            }
        } else {
            organizationPresets = []
        }

        if fileManager.fileExists(atPath: historyFileURL.path) {
            do {
                let data = try Data(contentsOf: historyFileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                transferHistory = try decoder.decode([TransferHistoryEntry].self, from: data)
            } catch {
                #if DEBUG
                DebugLog.warn("Failed to load history: \(error)")
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
