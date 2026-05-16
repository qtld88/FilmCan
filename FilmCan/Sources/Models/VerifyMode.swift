import Foundation

enum VerifyMode: String, Codable, CaseIterable, Identifiable {
    case paranoid
    case fast

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paranoid: return "Paranoid"
        case .fast: return "Fast"
        }
    }

    var description: String {
        switch self {
        case .paranoid:
            return "Re-reads source from disk after copy and verifies all destinations bit-for-bit. Catches in-memory corruption. Recommended."
        case .fast:
            return "Verifies destinations against source hash from copy stream. Faster. Use only for scratch copies where a master verified copy lives elsewhere."
        }
    }
}
