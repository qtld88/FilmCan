import Foundation

struct EngineOptions: Equatable, Codable {
    var postVerify: Bool = true
    var onlyCopyChanged: Bool = true
    var useHashListPrecheck: Bool = false
    var reuseOrganizedFiles: Bool = false
    var allowResume: Bool = true
    /// Retired: the copy order was never applied by the engine and the option was
    /// removed from Options. Kept only so saved configs still read and older
    /// FilmCan versions can still open configs written by this one.
    var fileOrdering: FileOrdering = .defaultOrder
    var parallelCopyEnabled: Bool = true
    var customVerifyEnabled: Bool = true
    // New backups default to Fast verify (size+xxh128 on the copied stream).
    // Paranoid (re-read both sides from disk) is opt-in — it roughly halves
    // throughput, so it must never be the silent default for a fresh tab.
    var verificationMode: VerifyMode = .fast
}
