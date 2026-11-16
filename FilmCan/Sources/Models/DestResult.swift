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
    /// Every roll's manifest at this destination (one per roll). `mhlPath` is only
    /// the first; repair and anything that must cover the whole run reads this.
    var mhlPaths: [String] = []
    /// Non-nil when the copy + verify succeeded but the ASC MHL manifest could not
    /// be sealed (data is safe; only the chain-of-custody deliverable is missing).
    /// Carries the seal error so the UI can explain it. Distinct from `failureReason`
    /// — this never makes `success` false.
    var manifestUnsealedReason: String?
    var durationSec: TimeInterval = 0
    var verifyMode: VerifyMode = .paranoid
    /// Manifest-relative names of files actually copied this run (truthful list,
    /// independent of the cumulative hash list).
    var transferredFileNames: [String] = []
    /// Source root path → roll folder written at this destination this run. Roots whose
    /// files were all skipped (resume) are absent.
    var rollFolders: [String: String] = [:]
    /// Absolute source paths whose bytes at this destination were compared by hash in
    /// this run: copied and checked (Fast/Paranoid), or already there and re-hashed
    /// (or recorded by an earlier checked run). The card seal and the catalog's
    /// "verified" flag require every planned file here; a run with Verification Off
    /// leaves it empty.
    var verifiedSourcePaths: Set<String> = []
}
