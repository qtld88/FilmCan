import Foundation

enum SourceFilterMatching {

    static func matchesPattern(_ name: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            let regex = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
            return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return name.range(of: trimmed, options: .caseInsensitive) != nil
    }

    static func hasCustomFilterPatterns(
        include: [String],
        exclude: [String],
        copyOnly: [String]
    ) -> Bool {
        let normalizedInclude = Self.normalizedPatterns(include)
        let normalizedCopyOnly = Self.normalizedPatterns(copyOnly)
        if !normalizedInclude.isEmpty || !normalizedCopyOnly.isEmpty {
            return true
        }
        let normalizedExclude = Self.normalizedPatterns(exclude)
        let defaultSet = Set(DefaultExcludes.patterns)
        let nonDefaultExcludes = normalizedExclude.filter { !defaultSet.contains($0) }
        return !nonDefaultExcludes.isEmpty
    }

    static func normalizedPatterns(_ patterns: [String]) -> [String] {
        patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
