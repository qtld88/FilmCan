import Foundation

/// Rejects source sets where two sources would land in the SAME destination root
/// folder (their resolved roll/root folder collides). Generalizes the Netflix
/// roll-uniqueness rule to all presets.
enum SourceCollisionValidator {
    /// `resolvedRoots` is the resolved destination root folder per source (order-stable).
    /// Returns the colliding folder names, empty if none.
    static func collisions(resolvedRoots: [String]) -> [String] {
        var seen: [String: Int] = [:]
        for r in resolvedRoots { seen[r, default: 0] += 1 }
        return seen.filter { $0.value > 1 }.keys
            .map { ($0 as NSString).lastPathComponent }.sorted()
    }
}

/// Rejects a plan where two different source files resolve to the same destination
/// file. Paths compare case- and normalization-insensitively, as on APFS and exFAT
/// by default: "A001.MOV" and "a001.mov" are one file there.
enum TargetPathValidator {
    /// `targets`: one (source file, resolved destination file) per planned file.
    /// Returns the clashing destination paths relative to `destRoot`, sorted.
    static func collisions(targets: [(source: String, target: String)], destRoot: String) -> [String] {
        var firstSourceByKey: [String: String] = [:]
        var clashes = Set<String>()
        for t in targets {
            let key = (t.target as NSString).standardizingPath
                .precomposedStringWithCanonicalMapping.lowercased()
            if let other = firstSourceByKey[key] {
                if other != t.source { clashes.insert(display(t.target, destRoot: destRoot)) }
            } else {
                firstSourceByKey[key] = t.source
            }
        }
        return clashes.sorted()
    }

    private static func display(_ path: String, destRoot: String) -> String {
        let root = destRoot.hasSuffix("/") ? destRoot : destRoot + "/"
        return path.hasPrefix(root) ? String(path.dropFirst(root.count)) : path
    }
}
