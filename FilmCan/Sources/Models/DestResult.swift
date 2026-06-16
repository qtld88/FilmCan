import Foundation

struct DestResult: Equatable {
    var destinationPath: String
    var displayName: String
    var success: Bool = false
    var filesTransferred: Int = 0
    var filesSkipped: Int = 0
    var filesFailedAfterCopy: Int = 0
    var bytesTransferred: Int64 = 0
    var failureReason: DestFailureReason?
    var mhlPath: String?
    var durationSec: TimeInterval = 0
    var verifyMode: VerifyMode = .paranoid
    /// Manifest-relative names of files actually copied this run (truthful list,
    /// independent of the cumulative hash list).
    var transferredFileNames: [String] = []
}
