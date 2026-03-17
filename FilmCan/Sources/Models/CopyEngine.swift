import Foundation

enum CopyEngine: String, Codable, CaseIterable, Identifiable {
    case rsync = "rsync"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rsync:
            return "rsync"
        case .custom:
            return "FilmCan Engine"
        }
    }

    var description: String {
        switch self {
        case .rsync:
            return "Industry-standard sync tool with advanced features like incremental sync, resume, and custom filters."
        case .custom:
            return "Streamlined copier optimized for speed with built-in verification. Best for full backups to local drives."
        }
    }

    var supportsIncrementalSync: Bool { self == .rsync }
    var supportsResume: Bool { self == .rsync }
    var supportsCustomFilters: Bool { self == .rsync }
}
