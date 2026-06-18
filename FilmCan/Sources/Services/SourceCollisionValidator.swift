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
