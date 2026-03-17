import Foundation

enum HashListVerifier {
    struct Report {
        let total: Int
        let missing: Int
        let mismatched: Int
    }

    static func verify(hashListPath: String, rootsFallback: [String] = []) -> Report? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hashListPath)),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }
        let roots = rootsFallback
        var total = 0
        var missing = 0
        var mismatched = 0
        var algorithm = algorithmFromPath(hashListPath)

        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                if let parsed = parseAlgorithmHeader(trimmed) {
                    algorithm = parsed
                }
                continue
            }
            guard let separatorRange = trimmed.range(of: "  ") else { continue }
            let hash = String(trimmed[..<separatorRange.lowerBound])
            let pathPart = String(trimmed[separatorRange.upperBound...])
            let filePath = resolvePath(pathPart, rootsFallback: roots)
            total += 1
            guard FileManager.default.fileExists(atPath: filePath) else {
                missing += 1
                continue
            }
            guard let actual = Hashing.hash(for: URL(fileURLWithPath: filePath), algorithm: algorithm) else {
                mismatched += 1
                continue
            }
            if actual.lowercased() != hash.lowercased() {
                mismatched += 1
            }
        }

        return Report(total: total, missing: missing, mismatched: mismatched)
    }

    private static func resolvePath(_ raw: String, rootsFallback: [String]) -> String {
        if raw.hasPrefix("/") {
            return raw
        }
        if rootsFallback.count == 1, let root = rootsFallback.first {
            return (root as NSString).appendingPathComponent(raw)
        }
        if rootsFallback.count > 1 {
            let components = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            if components.count == 2 {
                let label = String(components[0])
                let rest = String(components[1])
                if let root = rootsFallback.first(where: { ($0 as NSString).lastPathComponent == label }) {
                    return (root as NSString).appendingPathComponent(rest)
                }
            }
        }
        return raw
    }

    private static func parseAlgorithmHeader(_ line: String) -> FilmCanHashAlgorithm? {
        let lower = line.lowercased()
        guard let range = lower.range(of: "filmcan-hash:") else { return nil }
        let value = lower[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return FilmCanHashAlgorithm(rawValue: value)
    }

    private static func algorithmFromPath(_ path: String) -> FilmCanHashAlgorithm {
        return .xxh128
    }
}
