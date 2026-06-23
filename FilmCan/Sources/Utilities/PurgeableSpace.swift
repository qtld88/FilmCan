import Foundation

/// Frees APFS purgeable space on demand so an optimistic space pre-flight is
/// backed by real, immediately-writable bytes before a copy starts.
///
/// macOS reports purgeable space (local Time Machine snapshots, evictable
/// caches) as "free" in Finder, but it is not necessarily reclaimed fast enough
/// during an active write — a large copy into mostly-purgeable free space can
/// fail mid-write with ENOSPC. The supported lever to reclaim it up front is
/// `tmutil thinlocalsnapshots`, which is exactly what Disk Utility and the OS
/// use under space pressure. FilmCan's sandbox is disabled, so shelling out to
/// `/usr/bin/tmutil` is permitted.
enum PurgeableSpace {

    /// Try to ensure `targetBytes` are immediately writable at `path`. If statfs
    /// already has room, does nothing. Otherwise thins local snapshots on the
    /// path's volume to cover the shortfall (plus a margin) and returns the new
    /// immediately-writable figure. Best-effort: never throws.
    @discardableResult
    static func ensureWritable(_ targetBytes: Int64, at path: String) -> Int64 {
        let writable = DriveUtilities.immediatelyWritableBytes(for: path) ?? 0
        if writable >= targetBytes { return writable }

        guard let mount = volumeMountPoint(for: path) else { return writable }

        // Ask for the shortfall plus a 2 GB margin so the write has headroom.
        let shortfall = targetBytes - writable
        let request = shortfall + 2 * 1024 * 1024 * 1024
        let mb = { (b: Int64) in b / (1024 * 1024) }
        DebugLog.info("PurgeableSpace: need \(mb(targetBytes)) MB, only \(mb(writable)) MB immediately writable on \(mount) — thinning local snapshots for \(mb(request)) MB")
        thinLocalSnapshots(mount: mount, purgeBytes: request)

        let after = DriveUtilities.immediatelyWritableBytes(for: path) ?? writable
        DebugLog.info("PurgeableSpace: after reclaim \(mb(after)) MB immediately writable (freed ~\(mb(after - writable)) MB)")
        return after
    }

    /// `tmutil thinlocalsnapshots <mount> <purgeBytes> <urgency>`. Urgency 4 is
    /// the most aggressive (what the OS uses when genuinely out of space).
    private static func thinLocalSnapshots(mount: String, purgeBytes: Int64) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        proc.arguments = ["thinlocalsnapshots", mount, String(purgeBytes), "4"]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            DebugLog.warn("tmutil thinlocalsnapshots failed to launch: \(error.localizedDescription)")
        }
    }

    /// Mount point of the volume backing `path` (e.g. "/", "/Volumes/CARD").
    private static func volumeMountPoint(for path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeURLKey]),
           let volume = values.volume {
            return volume.path
        }
        return nil
    }
}
