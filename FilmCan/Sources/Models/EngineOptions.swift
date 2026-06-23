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
    // New backups default to Fast verify (size+xxh128 on the copied stream).
    // Paranoid (re-read both sides from disk) is opt-in — it roughly halves
    // throughput, so it must never be the silent default for a fresh tab.
    var verificationMode: VerifyMode = .fast
}
