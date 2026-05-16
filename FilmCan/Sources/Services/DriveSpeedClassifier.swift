import Foundation

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
