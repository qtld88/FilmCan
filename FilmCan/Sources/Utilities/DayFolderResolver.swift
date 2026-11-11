import Foundation

/// Finds the "folder of the day" on a card that is never wiped (sound recorders keep
/// every shooting day in its own dated folder, e.g. `26Y11M09`).
///
/// Pick rule: the folder dated today; else the latest one dated before today (night
/// shoot past midnight, card read the next morning); else the latest one (recorder
/// clock ahead). Several folders with the winning date are all returned.
enum DayFolderResolver {

    static let ruleTokens: Set<String> = ["{jour}", "{today}"]

    static func isRuleToken(_ component: String) -> Bool {
        ruleTokens.contains(component.lowercased())
    }

    // `26Y11M09` is the Sound Devices layout; the others are common recorder/DIT names.
    static func dayKey(_ name: String) -> Int? {
        let patterns: [(String, Bool)] = [
            (#"^(\d{2})Y(\d{2})M(\d{2})$"#, true),
            (#"^(\d{4})[-_.]?(\d{2})[-_.]?(\d{2})$"#, false),
            (#"^(\d{2})(\d{2})(\d{2})$"#, true),
        ]
        for (pattern, shortYear) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                  match.numberOfRanges == 4 else { continue }
            let parts = (1...3).compactMap { i -> Int? in
                Range(match.range(at: i), in: name).flatMap { Int(name[$0]) }
            }
            guard parts.count == 3 else { continue }
            let year = shortYear ? 2000 + parts[0] : parts[0]
            let (month, day) = (parts[1], parts[2])
            guard (2000...2099).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
            return year * 10_000 + month * 100 + day
        }
        return nil
    }

    static func todayKey(_ date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static func pick(_ candidates: [(path: String, key: Int)], today: Int) -> [String] {
        guard !candidates.isEmpty else { return [] }
        let keys = Set(candidates.map(\.key))
        let winner: Int
        if keys.contains(today) {
            winner = today
        } else if let past = keys.filter({ $0 < today }).max() {
            winner = past
        } else {
            winner = keys.max()!
        }
        return candidates.filter { $0.key == winner }.map(\.path).sorted()
    }

    static func findDayFolders(in rootPath: String, today: Date = Date(), maxDepth: Int = 3,
                               fileManager fm: FileManager = .default) -> [String] {
        if dayKey((rootPath as NSString).lastPathComponent) != nil { return [rootPath] }
        var candidates: [(path: String, key: Int)] = []
        var level = [URL(fileURLWithPath: rootPath, isDirectory: true)]
        for _ in 0..<maxDepth {
            var next: [URL] = []
            for dir in level {
                for child in subdirectories(of: dir, fileManager: fm) {
                    if let key = dayKey(child.lastPathComponent) {
                        candidates.append((child.path, key))
                    } else {
                        next.append(child)
                    }
                }
            }
            level = next
            if level.isEmpty { break }
        }
        return pick(candidates, today: todayKey(today))
    }

    static func dayFolders(inAnyOf parents: [URL], today: Date = Date(),
                           fileManager fm: FileManager = .default) -> [URL] {
        let candidates = parents.flatMap { subdirectories(of: $0, fileManager: fm) }
            .compactMap { url in dayKey(url.lastPathComponent).map { (path: url.path, key: $0) } }
        return pick(candidates, today: todayKey(today)).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // Drops the volume root and older dated folders of the same card so yesterday is not copied again.
    static func replacingStaleDays(in sources: [String], volumePath: String, fresh: [String]) -> [String] {
        guard !fresh.isEmpty else { return sources }
        var result = sources.filter { path in
            if fresh.contains(path) { return true }
            if path == volumePath { return false }
            guard path.hasPrefix(volumePath + "/") else { return true }
            return dayKey((path as NSString).lastPathComponent) == nil
        }
        for path in fresh where !result.contains(path) { result.append(path) }
        return result
    }

    private static func subdirectories(of dir: URL, fileManager fm: FileManager) -> [URL] {
        let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().compactMap { name in
            let child = dir.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            return fm.fileExists(atPath: child.path, isDirectory: &isDirectory) && isDirectory.boolValue ? child : nil
        }
    }
}
