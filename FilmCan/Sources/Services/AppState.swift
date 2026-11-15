import Foundation
import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var selectedConfigId: UUID? {
        didSet {
            storage.setLastSelectedConfigId(selectedConfigId)
        }
    }
    @Published var isTransferring: Bool = false
    @Published var showProgress: Bool = false
    @Published var activeTourTargetId: String?
    
    let storage = ConfigurationStorage.shared
    let notificationService = NotificationService.shared
    
    private init() {
        selectedConfigId = storage.lastUsedConfigId
    }
    
    var selectedConfig: BackupConfiguration? {
        guard let id = selectedConfigId else { return nil }
        return storage.configurations.first { $0.id == id }
    }
    
    func selectConfig(_ config: BackupConfiguration) {
        selectedConfigId = config.id
    }
    
    /// Adds a movie built by `FilmStarter` (and its own settings record) and selects it.
    @discardableResult
    func add(_ started: FilmStarter.Result) -> BackupConfiguration {
        if let preset = started.preset { storage.organizationPresets.append(preset) }
        storage.add(started.config)
        selectedConfigId = started.config.id
        return started.config
    }

    private var nextMovieName: String {
        FilmStarter.nextName(existing: storage.configurations.map(\.name))
    }

    /// A blank movie (first-run defaults).
    @discardableResult
    func createNewConfig() -> BackupConfiguration {
        add(FilmStarter.blank(name: nextMovieName))
    }

    /// A blank movie with the Netflix Ingest folder settings.
    @discardableResult
    func createNetflixIngestConfig() -> BackupConfiguration {
        add(FilmStarter.netflixIngest(name: nextMovieName))
    }

    /// Movies to start a new one from, most recently used first.
    var filmsToStartFrom: [BackupConfiguration] {
        storage.configurations.sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    /// A new movie with the settings of an existing one (a copy, not a link).
    @discardableResult
    func createNewConfig(like source: BackupConfiguration) -> BackupConfiguration {
        add(FilmStarter.like(source, name: nextMovieName, presets: storage.organizationPresets))
    }

    /// A new movie from a `.filmcan-movie` file. Always a new movie, never an overwrite.
    @discardableResult
    func createNewConfig(fromSettingsFile data: Data, fileName: String?) throws -> BackupConfiguration {
        let started = try MovieSettingsFile.makeMovie(
            from: data, name: fileName, existingNames: storage.configurations.map(\.name))
        return add(started)
    }

    /// The `.filmcan-movie` bytes for one movie.
    func settingsFileData(for movie: BackupConfiguration) throws -> Data {
        try MovieSettingsFile.export(movie: movie, presets: storage.organizationPresets)
    }
}
