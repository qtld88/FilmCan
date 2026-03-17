import Foundation

enum HashListNamer {
    static func makeFileName(
        configName: String,
        destination: String,
        sources: [String],
        date: Date = Date(),
        algorithm: FilmCanHashAlgorithm = .xxh128
    ) -> String {
        let formatterDateTime = DateFormatter()
        formatterDateTime.dateFormat = "yyyyMMdd-HHmmss"
        let dateTimeStr = formatterDateTime.string(from: date)

        let sourceName = shortSourceName(from: sources)
        let destName = (destination as NSString).lastPathComponent
        let base = "hashlist_\(sanitize(configName))_\(sanitize(sourceName))_\(sanitize(destName))_\(dateTimeStr)"
        return base + ".\(algorithm.fileExtension)"
    }

    private static func shortSourceName(from sources: [String]) -> String {
        guard !sources.isEmpty else { return "Source" }
        if sources.count == 1 {
            return (sources[0] as NSString).lastPathComponent
        }
        let parents = sources.map { ($0 as NSString).deletingLastPathComponent }
        if let first = parents.first, parents.allSatisfy({ $0 == first }) {
            return (first as NSString).lastPathComponent
        }
        return "MultipleSources"
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ()")
        var result = ""
        result.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            if allowed.contains(scalar) {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Backup" : trimmed
    }
}
