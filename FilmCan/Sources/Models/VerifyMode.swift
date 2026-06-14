import Foundation

enum VerifyMode: String, Codable, CaseIterable, Identifiable {
    case paranoid
    case fast
    case off

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paranoid: return "Paranoid"
        case .fast: return "Fast"
        case .off: return "Off"
        }
    }

    var description: String {
        switch self {
        case .paranoid:
            return "Re-reads source from disk after copy and verifies all destinations bit-for-bit. Catches in-memory corruption. Recommended."
        case .fast:
            return "Verifies destinations against the source hash computed during the copy. No re-read — about twice as fast. Use for scratch copies."
        case .off:
            return "No verification. Fastest, but a write error or corruption won't be detected."
        }
    }
}
