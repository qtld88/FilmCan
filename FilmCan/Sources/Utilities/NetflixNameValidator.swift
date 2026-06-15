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
}
