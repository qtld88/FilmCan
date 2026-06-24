import Foundation
import Combine

/// Snapshot of everything the list/flow views need about a drive/path, served
/// from memory so view bodies NEVER touch the disk on the main thread.
struct DriveInfoSnapshot {
    let summary: DriveUtilities.Summary
    let isExFAT: Bool
    var totalBytes: Int64?
    var liveAvailableBytes: Int64?
    var immediatelyWritableBytes: Int64?
    // Per-path filesystem facts so list rows don't stat on every render.
    var pathExists: Bool = false
    var rootExists: Bool = false
    var isDirectory: Bool = false
    var fileSize: Int64? = nil
    /// True until a real off-main populate replaces this with measured data.
    var isPlaceholder: Bool = false

    /// A disk-free best guess derived purely from the path string, shown on a
    /// cold cache miss until the off-main populate fills in real data. Assumes
    /// the path is present/connected so rows render normally; the populate
    /// corrects name, capacity, connection and metadata within ~one frame.
    static func placeholder(for path: String) -> DriveInfoSnapshot {
        let root = DriveUtilities.volumeRootPath(for: path)
        let underVolumes = root != nil
        let derivedName = (root.map { ($0 as NSString).lastPathComponent })
            ?? (path as NSString).lastPathComponent
        let id = root ?? path
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let isRoot = (normalized == "/") || (root != nil && normalized == root)
        let summary = DriveUtilities.Summary(
            id: id,
            name: derivedName.isEmpty ? "Drive" : derivedName,
            isExternal: underVolumes,
            isRoot: isRoot,
            formatDescription: nil,
            fileSystemType: nil,
            isReadOnly: nil)
        return DriveInfoSnapshot(
            summary: summary, isExFAT: false,
            totalBytes: nil, liveAvailableBytes: nil, immediatelyWritableBytes: nil,
            pathExists: true, rootExists: true, isDirectory: true, fileSize: nil,
            isPlaceholder: true)
    }
}

/// Caches drive/path metadata so view bodies are pure memory reads. The disk
/// work runs off the main thread and publishes when done, so observing views
/// re-render with real data.
///
/// Two invariants prevent the main-thread hangs this was built to kill:
///  1. `info(for:)` NEVER touches the disk — it returns a cached snapshot or a
///     disk-free placeholder, never a synchronous stat fallback.
///  2. `info(for:)` schedules a populate ONLY on a cache miss, never on a hit.
///     Capacity is refreshed explicitly via `prime(_:)` (called on appear and on
///     drive-refresh), so reads can't trigger a populate→publish→re-render→read
///     churn loop.
@MainActor
final class DriveInfoCache: ObservableObject {
    static let shared = DriveInfoCache()

    // Keyed by PATH, not volume id. Volume id requires DriveUtilities.summary
    // (a disk stat) to compute — keying by it would force a synchronous main-
    // thread stat on every lookup. The volume id still lives in summary.id.
    @Published private var entries: [String: DriveInfoSnapshot] = [:]
    private var inFlight: Set<String> = []

    /// Pure memory read. Returns the cached snapshot, or a disk-free placeholder
    /// (and schedules an off-main populate) on a miss. Never blocks on disk.
    func info(for path: String) -> DriveInfoSnapshot {
        if let existing = entries[path] { return existing }
        schedulePopulate(path: path)
        return .placeholder(for: path)
    }

    /// Raw cache state without scheduling or placeholders — for tests/diagnostics.
    func cachedSnapshot(for path: String) -> DriveInfoSnapshot? { entries[path] }

    /// Force a (re)fetch of each path off-main. Call on appear / drive-refresh to
    /// keep capacity fresh; this is the only path that refreshes a hit.
    func prime(_ paths: [String]) {
        for path in paths { schedulePopulate(path: path) }
    }

    func invalidate(path: String) {
        entries.removeValue(forKey: path)
    }

    func invalidateAll() {
        entries.removeAll()
    }

    private func schedulePopulate(path: String) {
        guard !inFlight.contains(path) else { return }
        inFlight.insert(path)
        Task.detached(priority: .utility) {
            let info = Self.fetch(path: path)
            await MainActor.run {
                self.entries[path] = info
                self.inFlight.remove(path)
            }
        }
    }

    /// Synchronous populate for tests — performs the fetch and stores it.
    func populateNow(path: String) async {
        let info = await Task.detached(priority: .utility) { Self.fetch(path: path) }.value
        entries[path] = info
        inFlight.remove(path)
    }

    /// Off-main disk work. Never throws; degrades to a placeholder on failure.
    nonisolated private static func fetch(path: String) -> DriveInfoSnapshot {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let pathExists = fm.fileExists(atPath: path, isDirectory: &isDir)
        let isDirectory = isDir.boolValue
        let rootExists: Bool
        if let root = DriveUtilities.volumeRootPath(for: path) {
            rootExists = fm.fileExists(atPath: root)
        } else {
            rootExists = pathExists
        }
        var fileSize: Int64? = nil
        if pathExists && !isDirectory {
            fileSize = (try? fm.attributesOfItem(atPath: path))?[.size] as? Int64
        }

        let summary = DriveUtilities.summary(for: path)
        let capacity = DriveUtilities.capacity(for: path)
        let exfat = DriveUtilities.isExFAT(path: path)
        let writable = DriveUtilities.immediatelyWritableBytes(for: path)
        if summary.name.isEmpty {
            return DriveInfoSnapshot(
                summary: DriveUtilities.Summary(
                    id: path, name: "Drive", isExternal: false, isRoot: false,
                    formatDescription: nil, fileSystemType: nil, isReadOnly: nil),
                isExFAT: false, totalBytes: nil, liveAvailableBytes: nil,
                immediatelyWritableBytes: nil,
                pathExists: pathExists, rootExists: rootExists,
                isDirectory: isDirectory, fileSize: fileSize, isPlaceholder: false)
        }
        return DriveInfoSnapshot(
            summary: summary, isExFAT: exfat,
            totalBytes: capacity.total, liveAvailableBytes: capacity.available,
            immediatelyWritableBytes: writable,
            pathExists: pathExists, rootExists: rootExists,
            isDirectory: isDirectory, fileSize: fileSize, isPlaceholder: false)
    }
}
