import Foundation

enum FileOrdering: String, Codable, CaseIterable, Identifiable {
    case defaultOrder = "defaultOrder"
    case smallFirst = "smallFirst"
    case largeFirst = "largeFirst"
    case creationDate = "creationDate"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultOrder: return "Default order"
        case .smallFirst: return "Small files first"
        case .largeFirst: return "Large files first"
        case .creationDate: return "Creation date (oldest first)"
        }
    }
}
