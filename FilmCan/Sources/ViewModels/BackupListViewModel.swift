import Foundation
import Combine

@MainActor
class BackupListViewModel: ObservableObject {
    @Published var searchText: String = ""
    
    private let storage = AppState.shared.storage
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Re-publish storage changes so the view updates when configurations change
        storage.$configurations
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
    
    var filteredConfigurations: [BackupConfiguration] {
        let configs = storage.configurations
        let query = normalizedSearch(searchText)
        let filtered: [BackupConfiguration]
        if query.isEmpty {
            filtered = configs
        } else {
            filtered = configs.filter { config in
                matchesQuery(config.name, query: query)
            }
        }
        return filtered
    }
    
    func delete(_ config: BackupConfiguration) {
        storage.delete(config)
    }
    
    func delete(at indexSet: IndexSet) {
        let configsToDelete = indexSet.map { filteredConfigurations[$0] }
        for config in configsToDelete {
            storage.delete(config)
        }
    }

    private func normalizedSearch(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private func matchesQuery(_ name: String, query: String) -> Bool {
        let normalizedName = normalizedSearch(name)
        if normalizedName.contains(query) {
            return true
        }
        let nameTokens = normalizedName.split { !$0.isLetter && !$0.isNumber }
        let queryTokens = query.split { !$0.isLetter && !$0.isNumber }
        guard !queryTokens.isEmpty else { return true }
        return queryTokens.allSatisfy { token in
            nameTokens.contains { $0.hasPrefix(token) }
        }
    }

}
