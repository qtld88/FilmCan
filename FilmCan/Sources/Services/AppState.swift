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
    let rsyncService = RsyncService()
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
        var config = BackupConfiguration.empty
        config.name = "Movie \(storage.configurations.count + 1)"
        // Start fresh (no prefilled sources/destinations)
        
        storage.add(config)
        selectedConfigId = config.id
        return config
    }
}
