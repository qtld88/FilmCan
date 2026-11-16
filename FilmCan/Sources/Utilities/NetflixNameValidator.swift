import Foundation

enum NetflixNameValidator {
    enum Issue: Equatable {
        case prohibitedChars(name: String, chars: String)
        case duplicateRoll(name: String)
    }

    /// Characters Netflix prohibits in roll/file names.
    static let prohibited = Set("@#$%^&*()`;:<>?,[]{}/\\'\"|~")

    static func validate(rollNames: [String]) -> [Issue] {
        var issues: [Issue] = []
        for name in rollNames {
            let bad = name.filter { prohibited.contains($0) }
            if !bad.isEmpty {
                issues.append(.prohibitedChars(name: name, chars: String(Array(Set(bad)))))
            }
        }
        var seen = Set<String>()
        for name in rollNames {
            if !seen.insert(name).inserted {
                if !issues.contains(.duplicateRoll(name: name)) {
                    issues.append(.duplicateRoll(name: name))
                }
            }
        }
        return issues
    }

    /// Replace each prohibited character with "_".
    static func sanitize(_ name: String) -> String {
        String(name.map { prohibited.contains($0) ? "_" : $0 })
    }

    /// "Auto-fix": the roll name each source gets AT THE DESTINATION, prohibited
    /// characters replaced and duplicates numbered (`_001`…). Only sources whose name
    /// changes are listed. Pure: the card is never renamed (FilmCan writes nothing on
    /// a card but `.filmcan/seal.json`).
    static func fixedRollNames(sources: [String]) -> [String: String] {
        var used = Set<String>()
        var out: [String: String] = [:]
        for path in sources {
            let original = (path as NSString).lastPathComponent
            let base = sanitize(original)
            var candidate = base
            var n = 1
            while used.contains(candidate) { candidate = "\(base)_\(String(format: "%03d", n))"; n += 1 }
            used.insert(candidate)
            if candidate != original { out[path] = candidate }
        }
        return out
    }
}
