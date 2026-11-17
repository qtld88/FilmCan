import Foundation

/// Recognises the same card's clips whatever roll name, drive or folder layout a run
/// gave them.
///
/// A clip key is "name|size|modified", one per file of at least 1 MiB on the card
/// (small sidecar files change between cameras and runs). A card with no file of
/// 1 MiB (a sound recorder's short takes) uses its files of at least 64 KiB instead.
/// Folders are left out, so
/// copying the card folder or only its content gives the same keys. A card that was
/// formatted (quick or full) and filled again has new clips: the same names come
/// back (C0001.MP4) but the size and the modification time differ, so its keys do not
/// match the earlier card's.
///
/// FAT32 and exFAT cards store local time without a time zone, so the Mac reads the
/// same card's dates shifted by whole hours after a time-zone or daylight-saving
/// change. Matching (`matchingClipCount`) accepts one such shift for the whole card.
enum CardFingerprint {

    static let minimumClipBytes: Int64 = 1 << 20
    /// Used only when no file of the card reaches `minimumClipBytes`.
    static let shortTakeMinimumBytes: Int64 = 64 << 10
    /// Widest gap between two time zones (UTC-12 … UTC+14), in hours.
    static let maxClockShiftHours: Int64 = 14

    static func key(name: String, size: Int64, modified: Date) -> String {
        "\(name)|\(size)|\(Int64(modified.timeIntervalSince1970.rounded(.down)))"
    }

    /// Clip keys of a source on disk: every visible file of at least 1 MiB below it,
    /// or the file itself for a single-file source. Reads metadata only, no data.
    static func keys(forSource path: String) -> [String] {
        let fm = FileManager.default
        let props: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let root = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else {
            return clipKey(for: root, props: props, minimumBytes: shortTakeMinimumBytes).map { [$0.key] } ?? []
        }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: props,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var found: [(key: String, size: Int64)] = []
        for case let url as URL in enumerator {
            if let clip = clipKey(for: url, props: props, minimumBytes: shortTakeMinimumBytes) {
                found.append(clip)
            }
        }
        let clips = found.filter { $0.size >= minimumClipBytes }
        return (clips.isEmpty ? found : clips).map(\.key).sorted()
    }

    /// How many clips of `card` are in `recorded`: same name and size, and dates equal
    /// or shifted by one whole number of hours (at most `maxClockShiftHours`), the same
    /// shift for every clip counted.
    static func matchingClipCount(_ card: [String], _ recorded: [String]) -> Int {
        var recordedTimes: [String: [Int64]] = [:]
        for key in recorded {
            guard let p = split(key) else { continue }
            recordedTimes[p.nameSize, default: []].append(p.time)
        }
        var countByShift: [Int64: Int] = [:]
        for key in Set(card) {
            guard let p = split(key), let times = recordedTimes[p.nameSize] else { continue }
            var shifts = Set<Int64>()
            for t in times {
                let shift = t - p.time
                if shift % 3600 == 0, abs(shift) <= maxClockShiftHours * 3600 { shifts.insert(shift) }
            }
            for shift in shifts { countByShift[shift, default: 0] += 1 }
        }
        return countByShift.values.max() ?? 0
    }

    /// "name|size" and the date of a clip key. The name may itself contain "|".
    private static func split(_ key: String) -> (nameSize: String, time: Int64)? {
        guard let bar = key.lastIndex(of: "|"), let time = Int64(key[key.index(after: bar)...]) else { return nil }
        return (String(key[..<bar]), time)
    }

    /// Clip keys of several sources, read off the main thread (a full card walk can
    /// take seconds on a slow reader). Keyed by the path as given.
    static func keys(forSources paths: [String]) async -> [String: [String]] {
        await Task.detached(priority: .userInitiated) {
            var out: [String: [String]] = [:]
            for path in paths { out[path] = CardFingerprint.keys(forSource: path) }
            return out
        }.value
    }

    private static func clipKey(for url: URL, props: [URLResourceKey],
                                minimumBytes: Int64) -> (key: String, size: Int64)? {
        guard let values = try? url.resourceValues(forKeys: Set(props)),
              values.isDirectory != true,
              let size = values.fileSize, Int64(size) >= minimumBytes,
              let modified = values.contentModificationDate
        else { return nil }
        return (key(name: url.lastPathComponent, size: Int64(size), modified: modified), Int64(size))
    }

    /// Weaker key for catalog entries recorded before clip keys existed: name and size
    /// of each large file. Used only when a whole set matches, never a single clip.
    static func legacyKey(relPath: String, size: Int64) -> String {
        "\((relPath as NSString).lastPathComponent)|\(size)"
    }
}
