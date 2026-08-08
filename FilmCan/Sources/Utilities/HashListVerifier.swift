import Foundation

enum HashListVerifier {
    struct Report {
        let total: Int
        let missing: Int
        let mismatched: Int
    }

    /// The directory the manifest's relPaths are relative to.
    /// ASC MHL lives at `<rollFolder>/ascmhl/<name>.mhl` → two levels up.
    /// The simple hidden list lives at `<destRoot>/.filmcan/hashlists/<roll>.mhl` → three up.
    /// Anything else falls back to a single supplied root, then the manifest's own directory.
    static func rollFolder(forManifestPath path: String, rootsFallback: [String]) -> String {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        if parent.lastPathComponent == "ascmhl" {
            return parent.deletingLastPathComponent().path
        }
        if parent.lastPathComponent == "hashlists",
           parent.deletingLastPathComponent().lastPathComponent == FilmCanPaths.hidden {
            return parent.deletingLastPathComponent().deletingLastPathComponent().path
        }
        if rootsFallback.count == 1, let root = rootsFallback.first { return root }
        return parent.path
    }

    /// Verify every entry in a manifest against the files on disk.
    /// Returns `nil` when the manifest cannot be read OR carries no entries —
    /// an empty result must never present as a clean bill of health.
    static func verify(hashListPath: String, rootsFallback: [String] = []) -> Report? {
        let url = URL(fileURLWithPath: hashListPath)
        guard let entries = readEntries(url: url), !entries.isEmpty else { return nil }

        let base = rollFolder(forManifestPath: hashListPath, rootsFallback: rootsFallback)
        var missing = 0, mismatched = 0
        for e in entries {
            let filePath = e.relPath.hasPrefix("/")
                ? e.relPath
                : (base as NSString).appendingPathComponent(e.relPath)
            guard FileManager.default.fileExists(atPath: filePath) else { missing += 1; continue }
            guard let actual = Hashing.hash(for: URL(fileURLWithPath: filePath), algorithm: .xxh128) else {
                mismatched += 1; continue
            }
            if actual.lowercased() != e.hash.lowercased() { mismatched += 1 }
        }
        return Report(total: entries.count, missing: missing, mismatched: mismatched)
    }

    /// ASC MHL first (the default style); fall back to the simple hidden format.
    private static func readEntries(url: URL) -> [MHLEntry]? {
        if let asc = try? ASCMHLReader.read(url: url), !asc.isEmpty {
            return asc.map { MHLEntry(relPath: $0.relPath, size: $0.size ?? 0,
                                      hash: $0.hash, mtime: $0.mtime) }
        }
        if let simple = try? SimpleMHLReader.read(url: url), !simple.isEmpty {
            return simple
        }
        return nil
    }
}
