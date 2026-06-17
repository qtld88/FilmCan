import Foundation

/// Whether a source holds camera footage (OCF) or production sound (OPA). For the
/// Netflix Ingest preset this routes the source under `Camera_Media/` or
/// `Sound_Media/`; other presets ignore it.
enum SourceMediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case camera
    case sound

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .sound: return "Sound"
        }
    }

    var symbol: String {
        switch self {
        case .camera: return "video.fill"
        case .sound: return "speaker.wave.2.fill"
        }
    }
}
