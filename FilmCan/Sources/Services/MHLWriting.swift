import Foundation

/// One file's manifest entry, shared by the ASC MHL and the simple hidden writers.
struct MHLEntry: Sendable {
    let relPath: String
    let size: Int64
    let hash: String
}

/// Common interface for hash-list writers so the fan-out engine can target either
/// the ASC MHL format (Netflix-ready: visible `ascmhl/` + generation chain) or a
/// lightweight hidden `.filmcan/hashlists/<roll>.mhl`. Both implementors are actors.
protocol MHLWriting: Actor {
    /// Absolute path of the manifest this writer produces (for history / DestResult).
    nonisolated var manifestPath: String { get }
    func seed(_ existing: [MHLEntry])
    func append(relPath: String, size: Int64, hash: String) async throws
    func flush() throws
    func seal() async throws
    func finalizeAsPartial(reason: String) async throws
    func cancel()
}
