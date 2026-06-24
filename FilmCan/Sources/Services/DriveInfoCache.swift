import Foundation
import Combine

/// Snapshot of everything the list/flow views need about a drive, served from memory.
struct DriveInfoSnapshot {
    let summary: DriveUtilities.Summary
    let isExFAT: Bool
    var totalBytes: Int64?
    var liveAvailableBytes: Int64?
    var immediatelyWritableBytes: Int64?
    var capacityFetchedAt: Date
}

/// Caches drive metadata so view bodies never hit the disk synchronously. Reads
/// are synchronous from memory; misses/stale entries return last-known (or nil)
/// and kick an off-main populate that writes back on the main actor and
/// publishes, so observing views re-render with fresh data.
@MainActor
final class DriveInfoCache: ObservableObject {
    static let shared = DriveInfoCache()

    @Published private var entries: [String: DriveInfoSnapshot] = [:]   // keyed by volume id
    private var inFlight: Set<String> = []
    private let capacityTTL: TimeInterval = 5

    /// Synchronous read. Returns cached info or nil. On miss or stale capacity,
    /// schedules an off-main populate (does not block).
    func info(for path: String) -> DriveInfoSnapshot? {
        let id = DriveUtilities.driveId(for: path)
        let existing = entries[id]
        if existing == nil || isCapacityStale(fetchedAt: existing!.capacityFetchedAt, ttl: capacityTTL) {
            schedulePopulate(path: path, id: id)
        }
        return existing
    }

    /// Prime several paths at once (call on appear / drive-refresh).
    func prime(_ paths: [String]) {
        for path in paths { schedulePopulate(path: path, id: DriveUtilities.driveId(for: path)) }
    }

    func invalidate(path: String) {
        entries.removeValue(forKey: DriveUtilities.driveId(for: path))
    }

    func invalidateAll() {
        entries.removeAll()
    }

    func isCapacityStale(fetchedAt: Date, ttl: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetchedAt) > ttl
    }

    private func schedulePopulate(path: String, id: String) {
        guard !inFlight.contains(id) else { return }
        inFlight.insert(id)
        Task.detached(priority: .utility) {
            let info = Self.fetch(path: path)
            await MainActor.run {
                self.entries[id] = info
                self.inFlight.remove(id)
            }
        }
    }

    /// Synchronous populate for tests — performs the fetch and stores it.
    func populateNow(path: String) async {
        let id = DriveUtilities.driveId(for: path)
        let info = await Task.detached(priority: .utility) { Self.fetch(path: path) }.value
        entries[id] = info
        inFlight.remove(id)
    }

    /// Off-main disk work. Never throws; degrades to a placeholder on failure.
    nonisolated private static func fetch(path: String) -> DriveInfoSnapshot {
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
                immediatelyWritableBytes: nil, capacityFetchedAt: Date())
        }
        return DriveInfoSnapshot(
            summary: summary, isExFAT: exfat,
            totalBytes: capacity.total, liveAvailableBytes: capacity.available,
            immediatelyWritableBytes: writable, capacityFetchedAt: Date())
    }
}
