import Foundation

/// Volume names that many cards share (a Sony card always mounts as "Untitled").
enum GenericCardName {
    static let names: Set<String> = [
        "UNTITLED", "NO NAME", "NONAME", "DJI", "EOS_DIGITAL", "CANON", "NIKON",
        "LUMIX", "GOPRO", "SD_CARD", "SDCARD", "CARD", "DCIM"
    ]

    /// "Untitled 1" -> "Untitled"; otherwise the trimmed name.
    static func baseName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: #" \d+$"#, options: .regularExpression) else { return trimmed }
        let stripped = String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? trimmed : stripped
    }

    static func isGeneric(_ name: String) -> Bool {
        names.contains(baseName(name).uppercased())
    }

    /// "Untitled" + taken ["Untitled_01","untitled_03","Other"] -> "Untitled_04".
    static func nextNumberedName(base: String, taken: [String]) -> String {
        let pattern = "^" + NSRegularExpression.escapedPattern(for: base) + "_(\\d+)$"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        var highest = 0
        for name in taken {
            let range = NSRange(name.startIndex..., in: name)
            guard let match = regex?.firstMatch(in: name, options: [], range: range),
                  let numberRange = Range(match.range(at: 1), in: name),
                  let number = Int(name[numberRange]) else { continue }
            highest = max(highest, number)
        }
        return base + "_" + String(format: "%02d", highest + 1)
    }
}
