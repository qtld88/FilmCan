import Foundation

/// Disables macOS Spotlight indexing on a volume by dropping the documented
/// `.metadata_never_index` marker at its root. No root privilege required —
/// same tier as the existing `.filmcan` namespace. Best-effort and idempotent.
///
/// Safety: `disableIndexing(forVolumeContaining:)` refuses to touch the
/// internal/boot volume. The marker is intentionally left in place (never
/// removed) — it keeps camera cards and backup drives from being re-scanned.
enum SpotlightIndexing {

    static let markerName = ".metadata_never_index"
    static let defaultsKey = "disableSpotlightIndexing"

    /// Read the gate. Absent key ⇒ enabled (opt-out feature).
    static func shouldDisable(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Ensure the never-index marker exists at `root`. Never overwrites an
    /// existing marker. Returns true if the marker is present after the call.
    @discardableResult
    static func writeMarker(atVolumeRoot root: String) -> Bool {
        let marker = (root as NSString).appendingPathComponent(markerName)
        if FileManager.default.fileExists(atPath: marker) { return true }
        return FileManager.default.createFile(atPath: marker, contents: Data())
    }

    /// Resolve the volume root backing `path` and, only if that volume is
    /// external/removable, drop the marker. Boot/internal volumes are never
    /// touched. Best-effort: failures are swallowed (logged by the caller).
    @discardableResult
    static func disableIndexing(forVolumeContaining path: String) -> Bool {
        guard let root = DriveUtilities.volumeRootPath(for: path) else { return false }
        guard DriveUtilities.summary(for: root).isExternal else { return false }
        return writeMarker(atVolumeRoot: root)
    }
}
