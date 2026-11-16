import Foundation
import Combine
import DiskArbitration
import AppKit

/// Volumes a running copy reads or writes. Refcounted per volume root (`/Volumes/X`).
/// Lock-protected, not main-actor: the DiskArbitration approval callback reads it
/// synchronously on its own queue.
final class VolumesInUse: ObservableObject, @unchecked Sendable {
    static let shared = VolumesInUse()

    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var leases: [UUID: [String]] = [:]

    /// `/Volumes/X` for any path on a mounted external/network volume; nil for the boot disk.
    static func volumeRoot(for path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return "/Volumes/\(components[2])"
    }

    func acquire(paths: [String]) -> UUID {
        let roots = Array(Set(paths.compactMap(Self.volumeRoot(for:))))
        let token = UUID()
        lock.lock()
        leases[token] = roots
        for root in roots { counts[root, default: 0] += 1 }
        lock.unlock()
        notifyChange()
        return token
    }

    func release(_ token: UUID) {
        lock.lock()
        let roots = leases.removeValue(forKey: token) ?? []
        for root in roots {
            let left = (counts[root] ?? 1) - 1
            counts[root] = left > 0 ? left : nil
        }
        lock.unlock()
        notifyChange()
    }

    func isBusy(path: String) -> Bool {
        guard let root = Self.volumeRoot(for: path) else { return false }
        lock.lock(); defer { lock.unlock() }
        return counts[root] != nil
    }

    var busyRoots: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(counts.keys)
    }

    private func notifyChange() {
        DispatchQueue.main.async { self.objectWillChange.send() }
    }
}

/// Refuses Finder (and any other app's) unmount of a volume a copy is using.
/// Finder's Force Eject is not covered.
enum FinderEjectGuard {
    static let busyMessage = "FilmCan is copying to or from this drive. Stop the copy first."

    private static var session: DASession?
    private static let queue = DispatchQueue(label: "com.filmcan.app.eject-guard")

    static func start() {
        guard session == nil, let newSession = DASessionCreate(kCFAllocatorDefault) else { return }
        DARegisterDiskUnmountApprovalCallback(newSession, nil, approval, nil)
        DASessionSetDispatchQueue(newSession, queue)
        session = newSession
    }

    private static let approval: DADiskUnmountApprovalCallback = { disk, _ in
        guard isBusy(disk) else { return nil }
        let dissenter = DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), busyMessage as CFString)
        return Unmanaged.passRetained(dissenter)
    }

    private static func isBusy(_ disk: DADisk) -> Bool {
        let busy = VolumesInUse.shared.busyRoots
        guard !busy.isEmpty else { return false }
        let description = DADiskCopyDescription(disk) as? [CFString: Any]
        if let url = description?[kDADiskDescriptionVolumePathKey] as? URL {
            return VolumesInUse.shared.isBusy(path: url.path)
        }
        // Whole-disk unmount (no volume path): busy if any busy volume lives on it.
        guard let session, let bsdName = bsdName(disk) else { return false }
        return busy.contains { root in
            guard let volumeDisk = DADiskCreateFromVolumePath(
                      kCFAllocatorDefault, session, URL(fileURLWithPath: root) as CFURL),
                  let whole = DADiskCopyWholeDisk(volumeDisk) else { return false }
            return self.bsdName(whole) == bsdName || self.bsdName(volumeDisk) == bsdName
        }
    }

    private static func bsdName(_ disk: DADisk) -> String? {
        DADiskGetBSDName(disk).map { String(cString: $0) }
    }
}

/// The app-side eject: refuses while a copy uses the drive, warns on an unsealed
/// card (sources), then unmounts and ejects the whole device.
@MainActor
enum VolumeEjectFlow {
    enum Outcome {
        case ejected, cancelled
        case failed(String)
    }

    static func eject(path: String, warnIfUnsealed: Bool) async -> Outcome {
        guard let root = VolumesInUse.volumeRoot(for: path) else {
            return .failed("This isn't on an ejectable volume.")
        }
        if VolumesInUse.shared.isBusy(path: path) {
            return .failed(FinderEjectGuard.busyMessage)
        }
        if warnIfUnsealed {
            let state = await CardSealService.evaluate(source: URL(fileURLWithPath: path))
            if state != .sealed {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "This card isn't sealed as backed-up"
                alert.informativeText = "FilmCan hasn't verified a complete backup of this card, or its contents changed since the last backup. Eject anyway?"
                alert.addButton(withTitle: "Eject Anyway")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return .cancelled }
            }
        }
        switch await DriveEjector.eject(volumeURL: URL(fileURLWithPath: root)) {
        case .success:
            return .ejected
        case .failure(let error):
            DebugLog.warn("Eject failed for \(root): \(error)")
            return .failed(error.errorDescription ?? "The drive couldn't be ejected.")
        }
    }
}
