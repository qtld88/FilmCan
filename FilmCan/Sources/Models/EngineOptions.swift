import Foundation

struct EngineOptions: Equatable, Codable {
    var postVerify: Bool = true
    var onlyCopyChanged: Bool = true
    var useHashListPrecheck: Bool = false
    var reuseOrganizedFiles: Bool = false
    var allowResume: Bool = true
    var fileOrdering: FileOrdering = .defaultOrder
    var parallelCopyEnabled: Bool = true
    var customVerifyEnabled: Bool = true
    var verificationMode: VerifyMode = .paranoid
}
