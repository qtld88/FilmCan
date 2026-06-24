import Foundation

enum DestStatus: Equatable {
    case pending
    /// Run started, engine is enumerating sources / scanning resume state — no
    /// bytes are moving yet. Shown so the card isn't a dead 0% bar during the
    /// pre-flight gap (which can be >10s on slow disks).
    case preparing
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
