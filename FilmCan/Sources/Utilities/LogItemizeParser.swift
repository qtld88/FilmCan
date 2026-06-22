import Foundation

/// Parses rsync `--itemize-changes` log output into the list of files that were
/// actually transferred. Extracted from `TransferViewModel` so the parsing rules
/// (itemize-code classification, path resolution across multiple roots) are
/// independently testable. Pure: no instance state, only its arguments.
enum LogItemizeParser {

    /// Read `logFile`, return the resolved paths of newly transferred files and
    /// whether any itemize line was seen at all (used to detect non-itemized logs).
    static func parseTransferredPaths(
        logFile: String,
        roots: [String],
        fallbackRoot: String
    ) -> (paths: [String], sawItemize: Bool) {
        guard let content = try? String(contentsOfFile: logFile, encoding: .utf8) else {
            return ([], false)
        }
        var results: [String] = []
        var sawItemize = false

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let (code, path) = extractItemizedPath(from: trimmed) else { continue }
            sawItemize = true
            guard shouldRecordItemizedFile(code) else { continue }
            let cleaned = cleanItemizedPath(path)
            guard !cleaned.isEmpty else { continue }
            let resolved = resolveLoggedPath(cleaned, roots: roots, fallbackRoot: fallbackRoot)
            if FilmCanPaths.isHidden(resolved) { continue }
            if resolved.hasSuffix("/") { continue }
            results.append(resolved)
        }

        return (Array(Set(results)), sawItemize)
    }

    static func resolveLoggedPath(_ raw: String, roots: [String], fallbackRoot: String) -> String {
        if raw.hasPrefix("/") { return raw }
        if roots.count == 1, let root = roots.first {
            return (root as NSString).appendingPathComponent(raw)
        }
        if roots.count > 1 {
            let components = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            if components.count == 2 {
                let label = String(components[0])
                let rest = String(components[1])
                if let root = roots.first(where: { ($0 as NSString).lastPathComponent == label }) {
                    return (root as NSString).appendingPathComponent(rest)
                }
            }
        }
        return (fallbackRoot as NSString).appendingPathComponent(raw)
    }

    static func extractItemizedPath(from line: String) -> (code: String, path: String)? {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        var cursor = line.startIndex
        for (index, token) in tokens.enumerated() {
            guard let range = line.range(of: token, range: cursor..<line.endIndex) else { continue }
            if isItemizeCode(String(token)) {
                let code = String(token)
                let pathStart = line.index(range.upperBound, offsetBy: 1, limitedBy: line.endIndex) ?? line.endIndex
                let path = String(line[pathStart...]).trimmingCharacters(in: .whitespaces)
                return (code, path)
            }
            cursor = range.upperBound
            if index == tokens.count - 1 { break }
        }
        return nil
    }

    static func isItemizeCode(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        let prefixes: Set<Character> = [">", "<", "c", "h", ".", "*"]
        let types: Set<Character> = ["f", "d", "L", "D", "S", "."]
        return prefixes.contains(chars[0]) && types.contains(chars[1])
    }

    static func shouldRecordItemizedFile(_ code: String) -> Bool {
        let chars = Array(code)
        guard chars.count >= 2 else { return false }
        guard chars[1] == "f" else { return false }
        return chars[0] == ">" || chars[0] == "c"
    }

    static func cleanItemizedPath(_ raw: String) -> String {
        var path = raw
        if let arrowRange = path.range(of: " -> ") {
            path = String(path[..<arrowRange.lowerBound])
        }
        if path.hasPrefix("./") {
            path = String(path.dropFirst(2))
        }
        return path.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
