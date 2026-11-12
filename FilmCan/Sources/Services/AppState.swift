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
    
    func createNewConfig() -> BackupConfiguration {
        // Start fresh (no prefilled sources/destinations)
        let config = BackupConfiguration.newFilm(name: "Movie \(storage.configurations.count + 1)")

        storage.add(config)
        selectedConfigId = config.id
        return config
    }

    /// Films to start a new one from, most recently used first.
    var filmsToStartFrom: [BackupConfiguration] {
        storage.configurations.sorted {
            ($0.lastUsedAt ?? $0.createdAt) > ($1.lastUsedAt ?? $1.createdAt)
        }
    }

    /// Shared presets to start a new film from.
    var presetsToStartFrom: [OrganizationPreset] {
        FilmPresetOwnership.shared(storage.organizationPresets)
    }

    /// A new film with the settings of an existing one (a copy, not a link).
    @discardableResult
    func createNewConfig(like source: BackupConfiguration) -> BackupConfiguration {
        var config = BackupConfiguration.newFilm(
            name: "Movie \(storage.configurations.count + 1)", like: source)
        if let id = source.selectedOrganizationPresetId,
           let preset = storage.organizationPresets.first(where: { $0.id == id }) {
            let copy = FilmPresetOwnership.ownCopy(
                of: FilmTemplate.replacingLeadingFilmFolder(in: preset, filmName: source.name),
                for: config.id)
            storage.organizationPresets.append(copy)
            config.selectedOrganizationPresetId = copy.id
            config.mirrorOrganization(from: copy)
        }
        storage.add(config)
        selectedConfigId = config.id
        return config
    }

    /// A new film started from a shared preset.
    @discardableResult
    func createNewConfig(fromPreset preset: OrganizationPreset) -> BackupConfiguration {
        var config = BackupConfiguration.newFilm(name: "Movie \(storage.configurations.count + 1)")
        config.takeSettings(from: preset)
        var copy = FilmPresetOwnership.ownCopy(of: preset, for: config.id)
        // Same log folder in the copy as in the film (Netflix pre-fills "Reports").
        copy.logLocation = config.logLocation
        copy.customLogPath = config.customLogPath
        storage.organizationPresets.append(copy)
        config.selectedOrganizationPresetId = copy.id
        storage.add(config)
        selectedConfigId = config.id
        return config
    }
}
