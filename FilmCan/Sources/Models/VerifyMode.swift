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
            return "Re-reads each destination from disk and verifies it against the source hash from the copy. Skips the source re-read paranoid does, so ~twice as fast — but does not catch in-memory source corruption."
        case .off:
            return "No verification. Fastest, but a write error or corruption won't be detected."
        }
    }
}
