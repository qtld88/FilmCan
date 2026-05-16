import Foundation

struct DestProgress: Identifiable, Equatable {
    let id: String
    let displayName: String
    var status: DestStatus = .pending
    var bytesCompleted: Int64 = 0
    var bytesTotal: Int64 = 0
    var filesCompleted: Int = 0
    var filesTotal: Int = 0
    var currentFile: String = ""
    var speedBytesPerSecond: Double = 0
    var estimatedTimeRemaining: TimeInterval?
    var verifyMode: VerifyMode = .paranoid
    var verifyBytesCompleted: Int64 = 0
    var verifyBytesTotal: Int64 = 0
    var failureReason: String?
    var requiresFullFsync: Bool = false
}
