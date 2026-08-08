import Foundation
import DiskArbitration

/// Remounts a single volume read-only or read-write via DiskArbitration.
/// No root required for user-owned removable media (same tier as DriveEjector).
///
/// Flow: unmount the volume (not the whole disk), then re-mount the same DADisk
/// with the `rdonly` mount argument (read-only) or none (read-write).
enum VolumeRemounter {

    enum RemountError: LocalizedError {
        case sessionUnavailable
        case diskLookupFailed
        case unmountRefused(String)
        case mountRefused(String)

        var errorDescription: String? {
            switch self {
            case .sessionUnavailable: return "Couldn't reach the disk subsystem. Try again."
            case .diskLookupFailed:   return "Couldn't identify the drive for this path."
            case .unmountRefused(let why): return "The drive is in use and couldn't be remounted. \(why)"
            case .mountRefused(let why):   return "The drive was unmounted but couldn't be remounted. \(why)"
            }
        }
    }

    /// Remount the volume backing `volumeURL` read-only.
    static func remountReadOnly(volumeURL: URL) async -> Result<Void, RemountError> {
        await remount(volumeURL: volumeURL, readOnly: true)
    }

    /// Remount the volume backing `volumeURL` read-write.
    static func remountReadWrite(volumeURL: URL) async -> Result<Void, RemountError> {
        await remount(volumeURL: volumeURL, readOnly: false)
    }

    // MARK: - Core

    private static func remount(volumeURL: URL, readOnly: Bool) async -> Result<Void, RemountError> {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.filmcan.app.remount")
            queue.async {
                guard let session = DASessionCreate(kCFAllocatorDefault) else {
                    continuation.resume(returning: .failure(.sessionUnavailable)); return
                }
                DASessionSetDispatchQueue(session, queue)

                guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, volumeURL as CFURL) else {
                    DASessionSetDispatchQueue(session, nil)
                    continuation.resume(returning: .failure(.diskLookupFailed)); return
                }

                let ctx = RemountContext(session: session, disk: disk,
                                         readOnly: readOnly, continuation: continuation)
                let raw = Unmanaged.passRetained(ctx).toOpaque()
                DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionDefault), unmountCallback, raw)
            }
        }
    }

    private final class RemountContext {
        let session: DASession
        let disk: DADisk
        let readOnly: Bool
        // Retain the mount-arg string for the lifetime of the async mount call.
        let rdonlyArg = "rdonly" as CFString
        let continuation: CheckedContinuation<Result<Void, RemountError>, Never>
        init(session: DASession, disk: DADisk, readOnly: Bool,
             continuation: CheckedContinuation<Result<Void, RemountError>, Never>) {
            self.session = session; self.disk = disk
            self.readOnly = readOnly; self.continuation = continuation
        }
        func finish(_ r: Result<Void, RemountError>) {
            DASessionSetDispatchQueue(session, nil)
            continuation.resume(returning: r)
        }
    }

    private static func dissenterMessage(_ dissenter: DADissenter) -> String {
        if let s = DADissenterGetStatusString(dissenter) { return s as String }
        return "(error \(String(format: "0x%08X", DADissenterGetStatus(dissenter))))"
    }

    // Unmount done → mount the same disk with/without rdonly.
    private static let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<RemountContext>.fromOpaque(context).takeUnretainedValue()
        if let dissenter {
            Unmanaged<RemountContext>.fromOpaque(context).release()
            ctx.finish(.failure(.unmountRefused(dissenterMessage(dissenter))))
            return
        }
        let options = DADiskMountOptions(kDADiskMountOptionDefault)
        if ctx.readOnly {
            // NULL-terminated array of CFString mount arguments.
            var args: [Unmanaged<CFString>?] = [Unmanaged.passUnretained(ctx.rdonlyArg), nil]
            args.withUnsafeMutableBufferPointer { buf in
                DADiskMountWithArguments(ctx.disk, nil, options, mountCallback, context, buf.baseAddress)
            }
        } else {
            DADiskMount(ctx.disk, nil, options, mountCallback, context)
        }
    }

    // Mount done → terminal; release the retained context.
    private static let mountCallback: DADiskMountCallback = { _, dissenter, context in
        guard let context else { return }
        let ctx = Unmanaged<RemountContext>.fromOpaque(context).takeRetainedValue()
        if let dissenter {
            ctx.finish(.failure(.mountRefused(dissenterMessage(dissenter))))
        } else {
            ctx.finish(.success(()))
        }
    }
}
