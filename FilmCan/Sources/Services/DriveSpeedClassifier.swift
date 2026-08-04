import Foundation
import IOKit

enum DriveBus: Equatable {
    case thunderbolt
    case usb3plus
    case usb2
    case internal_
    case network
    case unknown
}

enum DriveFilesystem: Equatable {
    case apfs
    case hfsplus
    case exfat
    case ntfs
    case smb
    case afp
    case unknown
}

struct DriveInfo: Equatable {
    var isSSD: Bool
    var bus: DriveBus
    var filesystem: DriveFilesystem
    var isInternal: Bool
    var isExFAT: Bool
    var isNetwork: Bool
    var volumeUUID: String?
}

enum DriveSpeedClassifier {
    static func expectedSpeedMBps(_ info: DriveInfo) -> Double {
        let base: Double
        switch (info.isSSD, info.bus) {
        case (true, .thunderbolt), (true, .usb3plus), (true, .internal_):
            base = 400
        case (true, .usb2):
            base = 35
        case (false, .thunderbolt), (false, .usb3plus):
            base = 120
        case (false, .usb2):
            base = 35
        default:
            base = 100
        }
        return info.isExFAT ? base * 0.6 : base
    }

    static func requiresFullFsync(_ info: DriveInfo) -> Bool {
        if info.isExFAT { return true }
        if info.filesystem == .ntfs { return true }
        if info.filesystem == .smb || info.filesystem == .afp { return true }
        if !info.isInternal { return true }
        return false
    }

    static func slowestDestClass(_ infos: [DriveInfo]) -> Constants.SlowestDestClass {
        let classes = infos.map { classify($0) }
        let order: [Constants.SlowestDestClass] = [.exfat, .hdd, .network, .unknown, .ssdLocal, .nvmeLocal]
        for c in order {
            if classes.contains(c) { return c }
        }
        return .unknown
    }

    private static func classify(_ info: DriveInfo) -> Constants.SlowestDestClass {
        if info.isExFAT { return .exfat }
        if info.isNetwork { return .network }
        if !info.isSSD { return .hdd }
        if info.bus == .thunderbolt || info.bus == .internal_ { return .nvmeLocal }
        if info.bus == .usb3plus { return .ssdLocal }
        return .unknown
    }
}

// MARK: - IOKit live probe

extension DriveSpeedClassifier {
    static func info(for path: String) -> DriveInfo {
        let url = URL(fileURLWithPath: path)
        let isSSD = volumeIsSolidStateLive(url: url)
        let isExFAT = DriveUtilities.isExFAT(path: path)
        let (fs, isNetwork) = filesystem(for: url)
        let isInternal = volumeIsInternal(url: url)
        let bus: DriveBus = isNetwork ? .network : detectBus(for: url)
        let uuid = volumeUUID(for: url)
        return DriveInfo(
            isSSD: isSSD,
            bus: bus,
            filesystem: fs,
            isInternal: isInternal,
            isExFAT: isExFAT,
            isNetwork: isNetwork,
            volumeUUID: uuid
        )
    }

    private static func volumeIsSolidStateLive(url: URL) -> Bool {
        let key = URLResourceKey(rawValue: "NSURLVolumeIsSolidStateKey")
        if let values = try? url.resourceValues(forKeys: [key]),
           let b = values.allValues[key] as? Bool {
            return b
        }
        return false
    }

    private static func volumeIsInternal(url: URL) -> Bool {
        if let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey]),
           let b = values.volumeIsInternal {
            return b
        }
        return false
    }

    private static func volumeUUID(for url: URL) -> String? {
        if let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]),
           let s = values.volumeUUIDString {
            return s
        }
        return nil
    }

    private static func filesystem(for url: URL) -> (DriveFilesystem, Bool) {
        let key = URLResourceKey(rawValue: "NSURLVolumeLocalizedFormatDescriptionKey")
        let typeKey = URLResourceKey(rawValue: "NSURLVolumeTypeNameKey")
        var fs: DriveFilesystem = .unknown
        var isNet = false
        if let values = try? url.resourceValues(forKeys: [key, typeKey, .volumeIsLocalKey]) {
            if let local = values.allValues[.volumeIsLocalKey] as? Bool {
                isNet = !local
            }
            let typeName = (values.allValues[typeKey] as? String ?? "").lowercased()
            if typeName.contains("apfs") { fs = .apfs }
            else if typeName.contains("exfat") { fs = .exfat }
            else if typeName.contains("ntfs") { fs = .ntfs }
            else if typeName.contains("smb") { fs = .smb; isNet = true }
            else if typeName.contains("afp") { fs = .afp; isNet = true }
            else if typeName.contains("hfs") { fs = .hfsplus }
        }
        return (fs, isNet)
    }

    private static func detectBus(for url: URL) -> DriveBus {
        guard let bsdName = bsdNameForVolume(url: url) else { return .unknown }
        let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        guard let dict = matching else { return .unknown }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, dict)
        guard service != 0 else { return .unknown }
        defer { IOObjectRelease(service) }
        var parent: io_registry_entry_t = 0
        var current = service
        IOObjectRetain(current)
        while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
            let name = ioClassName(of: parent)
            if name.contains("Thunderbolt") {
                IOObjectRelease(parent); IOObjectRelease(current)
                return .thunderbolt
            }
            if name.contains("USB") {
                let speed = usbSpeed(of: parent)
                IOObjectRelease(parent); IOObjectRelease(current)
                return speed
            }
            if name.contains("AppleAPFSContainer") || name.contains("Internal") {
                IOObjectRelease(parent); IOObjectRelease(current)
                return .internal_
            }
            IOObjectRelease(current)
            current = parent
            parent = 0
        }
        IOObjectRelease(current)
        return .unknown
    }

    private static func ioClassName(of obj: io_registry_entry_t) -> String {
        var name: io_name_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        IOObjectGetClass(obj, &name)
        return withUnsafePointer(to: &name) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }
    }

    private static func usbSpeed(of obj: io_registry_entry_t) -> DriveBus {
        guard let prop = IORegistryEntryCreateCFProperty(
            obj, "Speed" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? Int else { return .usb3plus }
        return prop >= 5_000_000_000 ? .usb3plus : .usb2
    }

    private static func bsdNameForVolume(url: URL) -> String? {
        var fsInfo = statfs()
        guard statfs(url.path, &fsInfo) == 0 else { return nil }
        let mntfromname = withUnsafePointer(to: &fsInfo.f_mntfromname) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        if mntfromname.hasPrefix("/dev/") {
            return String(mntfromname.dropFirst("/dev/".count))
        }
        return nil
    }
}
