import Foundation

enum DestStatus: Equatable {
    case pending
    case active
    case complete
    case failed(DestFailureReason)
}

enum DestFailureReason: Equatable {
    case timeout
    case ioError(String)
    case full
    case verify
    case userCancel
    case sourceUnavailable

    var displayMessage: String {
        switch self {
        case .timeout: return "Destination stopped responding"
        case .ioError(let msg): return "I/O error: \(msg)"
        case .full: return "Destination is full"
        case .verify: return "Verification mismatch"
        case .userCancel: return "Cancelled by user"
        case .sourceUnavailable: return "Source unavailable"
        }
    }
}
