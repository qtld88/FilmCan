import Foundation

/// The editor's "is there room?" check before Run.
///
/// Only checked destinations count, and only those whose drive is mounted: an
/// unchecked drive receives nothing, and an unplugged one has no free space to read
/// (the run reports it as unreachable instead). Destinations on the same drive share
/// its free space, so their needs add up, as in `FanOutCopier`'s own space gate.
enum DestinationSpaceCheck {

    struct Shortfall: Equatable {
        let destination: String
        let needed: Int64
        let available: Int64
        let writableNow: Int64
    }

    /// What a destination's drive says right now.
    struct Probe: Equatable {
        /// Same value for every destination on one drive.
        let volumeKey: String
        let available: Int64?
        let writableNow: Int64?
    }

    /// Destinations that may not fit. `probe` returns nil when the drive is not mounted.
    static func shortfalls(destinations: [String],
                           requiredBytes: Int64,
                           probe: (String) -> Probe?) -> [Shortfall] {
        guard requiredBytes > 0 else { return [] }

        var order: [String] = []
        var byVolume: [String: (paths: [String], probe: Probe)] = [:]
        for dest in destinations {
            guard let p = probe(dest) else { continue }
            // Unknown free space is not a shortfall; the engine checks again.
            guard p.available != nil || p.writableNow != nil else { continue }
            if byVolume[p.volumeKey] == nil {
                order.append(p.volumeKey)
                byVolume[p.volumeKey] = ([dest], p)
            } else {
                byVolume[p.volumeKey]?.paths.append(dest)
            }
        }

        var result: [Shortfall] = []
        for key in order {
            guard let group = byVolume[key] else { continue }
            let needed = requiredBytes * Int64(group.paths.count)
            let available = group.probe.available ?? 0
            let writableNow = group.probe.writableNow ?? available
            guard needed > writableNow else { continue }
            for path in group.paths {
                result.append(Shortfall(destination: path, needed: needed,
                                        available: available, writableNow: writableNow))
            }
        }
        return result
    }

    /// The nearest existing folder at or above `path`, without leaving its drive.
    /// A destination folder that a run will create still has its drive's space.
    /// Nil when the drive itself is missing: climbing out of `/Volumes/<name>`
    /// would land on the startup disk and report its space instead.
    static func existingFolder(for path: String, fileExists: (String) -> Bool) -> String? {
        var current = (path as NSString).standardizingPath
        while true {
            if fileExists(current) { return current }
            let parent = (current as NSString).deletingLastPathComponent
            if parent == current || parent == "/Volumes" { return nil }
            current = parent
        }
    }

    /// The real drive, as the editor sees it now.
    static func liveProbe(_ path: String) -> Probe? {
        let fm = FileManager.default
        guard let folder = existingFolder(for: path, fileExists: { fm.fileExists(atPath: $0) })
        else { return nil }
        let volume = (try? URL(fileURLWithPath: folder).resourceValues(forKeys: [.volumeURLKey]))?
            .volume?.path ?? folder
        return Probe(volumeKey: volume,
                     available: DriveUtilities.liveAvailableBytes(for: folder),
                     writableNow: DriveUtilities.immediatelyWritableBytes(for: folder))
    }
}
