import Foundation

enum FilmCanHashAlgorithm: String, Codable, CaseIterable, Identifiable {
    case xxh128 = "xxh128"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .xxh128: return "xxHash128"
        }
    }

    var fileExtension: String {
        switch self {
        case .xxh128: return "xxh128"
        }
    }

    var headerTag: String {
        rawValue
    }
}
