import Foundation

/// Which hash-list format the FilmCan engine writes alongside a backup.
enum HashListStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// ASC MHL v2.0 — visible `ascmhl/` folder + generation chain. Netflix-ready.
    case ascMHL
    /// Lightweight hidden `.filmcan/hashlists/<roll>.mhl` — no chain, no generations.
    case simpleHidden

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ascMHL: return "ASC MHL (Netflix-ready)"
        case .simpleHidden: return "Simple (hidden)"
        }
    }

    var shortName: String {
        switch self {
        case .ascMHL: return "ASC MHL"
        case .simpleHidden: return "Simple"
        }
    }

    var description: String {
        switch self {
        case .ascMHL: return "Visible ascmhl/ folder + chain of custody"
        case .simpleHidden: return "Hidden .filmcan hash list, no chain"
        }
    }
}
