import Foundation

/// Pure pre-flight detection of destination files that would be overwritten but are
/// NOT recorded in that destination's manifest (an "unmanifested collision"). The
/// engine resolves these by `DuplicatePolicy` before any copy begins, so the
/// fan-out never blind-overwrites and never prompts mid-copy.
enum ConflictScanner {
    struct Target: Sendable {
        let destPath: String
        let rootName: String
        let fileName: String      // manifest-relative name
        let resolvedPath: String  // absolute on-disk target path
    }

    struct Conflict: Sendable {
        let destPath: String
        let rootName: String
        let fileName: String
        let resolvedPath: String
    }

    static func key(destPath: String, rootName: String) -> String { "\(destPath)\0\(rootName)" }

    /// `manifestedRelPathsByDestRoot` maps `key(destPath:rootName:)` to the set of
    /// manifest-relative names already recorded for that roll at that destination.
    static func scan(
        plannedTargets: [Target],
        manifestedRelPathsByDestRoot: [String: Set<String>]
    ) -> [Conflict] {
        var out: [Conflict] = []
        for t in plannedTargets {
            guard FileManager.default.fileExists(atPath: t.resolvedPath) else { continue }
            let recorded = manifestedRelPathsByDestRoot[key(destPath: t.destPath, rootName: t.rootName)] ?? []
            if recorded.contains(t.fileName) { continue }
            out.append(Conflict(destPath: t.destPath, rootName: t.rootName,
                                fileName: t.fileName, resolvedPath: t.resolvedPath))
        }
        return out
    }
}
