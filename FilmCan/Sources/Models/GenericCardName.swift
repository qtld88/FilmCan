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

/// Which generic cards still need a roll name, keyed by card (volume UUID + path on it).
/// A card swapped for another one at the same mount path (two "Untitled" cards in a
/// row) has a new key, so it shows up here again although the source list is unchanged.
enum GenericRollNaming {
    /// Names to add: one suggestion per generic source whose card has no name yet and
    /// that the user did not name (or clear) by hand. Sources sharing a card key get one.
    static func namesToFill(sources: [String],
                            isGeneric: (String) -> Bool,
                            keyFor: (String) -> String,
                            existing: [String: String],
                            userEdited: Set<String>,
                            suggest: (String, [String: String]) -> String) -> [String: String] {
        var names = existing
        var added: [String: String] = [:]
        for path in sources where isGeneric(path) {
            let key = keyFor(path)
            guard names[key] == nil, !userEdited.contains(key) else { continue }
            let name = suggest(path, names)
            names[key] = name
            added[key] = name
        }
        return added
    }
}

