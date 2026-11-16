import Foundation

/// One file's manifest entry, shared by the ASC MHL and the simple hidden writers.
struct MHLEntry: Sendable {
    let relPath: String
    let size: Int64
    let hash: String
    let mtime: Int64?
    /// Hash element the value belongs to ("xxh128", "md5", …). FilmCan only hashes
    /// xxh128; another algorithm comes from a carried entry of another tool.
    var algorithm: String = MHLEntry.xxh128
    /// For an entry carried from an earlier generation: the `hashdate` and `action`
    /// it was recorded with (nil = absent there). A fresh entry leaves both nil and
    /// the ASC writer stamps it `original` with this generation's date.
    var hashDate: String? = nil
    var action: String? = nil
    /// True when the entry comes from an earlier manifest rather than this run.
    var isCarried: Bool = false

    static let xxh128 = "xxh128"
}

/// Common interface for hash-list writers so the fan-out engine can target either
/// the ASC MHL format (Netflix-ready: visible `ascmhl/` + generation chain) or a
/// lightweight hidden `.filmcan/hashlists/<roll>.mhl`. Both implementors are actors.
protocol MHLWriting: Actor {
    /// Absolute path of the manifest this writer produces (for history / DestResult).
    nonisolated var manifestPath: String { get }
    func seed(_ existing: [MHLEntry])
    func append(relPath: String, size: Int64, hash: String, mtime: Int64?) async throws
    func flush() throws
    func seal() async throws
    func finalizeAsPartial(reason: String) async throws
    func cancel()
}
