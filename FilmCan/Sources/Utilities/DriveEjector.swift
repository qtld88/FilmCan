import Foundation
import DiskArbitration

/// Whole-disk unmount + eject via DiskArbitration.
///
/// `NSWorkspace.unmountAndEjectDevice(at:)` operates on a single volume. On a
/// multi-partition camera card it can unmount one volume while leaving the
/// physical device attached — macOS then remounts it seconds later and the
/// drive auto-detection re-adds it. We resolve the *whole* disk and unmount it
/// with `kDADiskUnmountOptionWhole`, then eject, so the device actually leaves.
enum DriveEjector {

    enum EjectError: LocalizedError {
        case notAnEjectableVolume
        case sessionUnavailable
        case diskLookupFailed
        case unmountRefused(String)
        case ejectRefused(String)

        var errorDescription: String? {
            switch self {
            case .notAnEjectableVolume:
                return "This isn't on an ejectable volume."
            case .sessionUnavailable:
                return "Couldn't reach the disk subsystem. Try again."
            case .diskLookupFailed:
                return "Couldn't identify the drive for this path."
            case .unmountRefused(let why):
                return "The drive is still in use and couldn't be unmounted. \(why)"
            case .ejectRefused(let why):
                return "The drive was unmounted but couldn't be ejected. \(why)"
            }
        }
    }

    /// Unmount (whole disk) then eject the device backing `volumeURL`.
    /// Returns on the main actor. Never throws — result carries the failure.
    static func eject(volumeURL: URL) async -> Result<Void, EjectError> {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.filmcan.app.eject")
            queue.async {
                guard let session = DASessionCreate(kCFAllocatorDefault) else {
                    continuation.resume(returning: .failure(.sessionUnavailable))
                    return
                }
                DASessionSetDispatchQueue(session, queue)

                guard
                    let volumeDisk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL),
                    let wholeDisk = DADiskCopyWholeDisk(volumeDisk)
                else {
                    DASessionSetDispatchQueue(session, nil)
                    continuation.resume(returning: .failure(.diskLookupFailed))
                    return
                }

                let ctx = EjectContext(session: session, wholeDisk: wholeDisk, continuation: continuation)
                let raw = Unmanaged.passRetained(ctx).toOpaque()

                DADiskUnmount(wholeDisk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), unmountCallback, raw)
            }
        }
    }

    // MARK: - DiskArbitration plumbing

    private final class EjectContext {
        let session: DASession
        let wholeDisk: DADisk
        let continuation: CheckedContinuation<Result<Void, EjectError>, Never>
        init(session: DASession, wholeDisk: DADisk,
             continuation: CheckedContinuation<Result<Void, EjectError>, Never>) {
            self.session = session
            self.wholeDisk = wholeDisk
            self.continuation = continuation
        }
        func finish(_ result: Result<Void, EjectError>) {
            DASessionSetDispatchQueue(session, nil)
            continuation.resume(returning: result)
        }
    }

    private static func dissenterMessage(_ dissenter: DADissenter) -> String {
        if let s = DADissenterGetStatusString(dissenter) {
            return (s as String)
        }
        let status = DADissenterGetStatus(dissenter)
        return "(error \(String(format: "0x%08X", status)))"
    }

    // Unmount completion: on success proceed to eject; otherwise fail and release.
    private static let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<EjectContext>.fromOpaque(context).takeUnretainedValue()
        if let dissenter {
            Unmanaged<EjectContext>.fromOpaque(context).release()
            ctx.finish(.failure(.unmountRefused(dissenterMessage(dissenter))))
            return
        }
        // Still alive across the second async hop — keep the +1 retain, pass same ctx.
        DADiskEject(ctx.wholeDisk, DADiskEjectOptions(kDADiskEjectOptionDefault), ejectCallback, context)
    }

    // Eject completion: terminal — release the retained context here.
    private static let ejectCallback: DADiskEjectCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<EjectContext>.fromOpaque(context).takeRetainedValue()
        if let dissenter {
            ctx.finish(.failure(.ejectRefused(dissenterMessage(dissenter))))
        } else {
            ctx.finish(.success(()))
        }
    }
}
