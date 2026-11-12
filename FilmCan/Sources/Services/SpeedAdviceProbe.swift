import Foundation
import IOKit

/// Reads the drive facts the speed advice needs. Best effort: anything macOS does not
/// report stays unknown, and unknown facts never produce advice.
enum SpeedAdviceProbe {
    static func drive(path: String, role: SpeedDrive.Role) -> SpeedDrive {
        let info = DriveSpeedClassifier.info(for: path)
        let capacity = DriveUtilities.capacity(for: path)
        let name = DriveUtilities.summary(for: path).name
        let tree = info.isNetwork ? UsbTree() : usbTree(for: URL(fileURLWithPath: path))
        return SpeedDrive(path: path, name: name, role: role, info: info,
                          hubID: tree.hubID,
                          capacityBytes: capacity.total, availableBytes: capacity.available,
                          isRotational: tree.isRotational)
    }

    struct UsbTree {
        var hubID: UInt64? = nil
        var isRotational: Bool? = nil
    }

    /// Walks up from the volume's disk: the first "Medium Type" found tells whether the
    /// drive spins; the first external USB hub above the USB device names the hub.
    static func usbTree(for url: URL) -> UsbTree {
        var out = UsbTree()
        guard let bsdName = DriveSpeedClassifier.bsdNameForVolume(url: url),
              let matching = IOBSDNameMatching(kIOMainPortDefault, 0, bsdName) else { return out }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return out }

        var current: io_registry_entry_t = service
        var passedUSBDevice = false
        var depth = 0
        while depth < 40 {
            depth += 1
            if out.isRotational == nil,
               let chars = property(current, "Device Characteristics") as? [String: Any],
               let medium = chars["Medium Type"] as? String {
                if medium == "Rotational" { out.isRotational = true }
                else if medium == "Solid State" { out.isRotational = false }
            }
            if className(current).contains("IOUSBHostDevice") {
                if passedUSBDevice, out.hubID == nil, isExternalHub(current) {
                    var id: UInt64 = 0
                    if IORegistryEntryGetRegistryEntryID(current, &id) == KERN_SUCCESS { out.hubID = id }
                }
                passedUSBDevice = true
            }
            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS else { return out }
            current = parent
        }
        IOObjectRelease(current)
        return out
    }

    private static func isExternalHub(_ entry: io_registry_entry_t) -> Bool {
        guard let deviceClass = property(entry, "bDeviceClass") as? Int, deviceClass == 9 else { return false }
        if let builtIn = property(entry, "Built-In") as? Bool, builtIn { return false }
        let name = (property(entry, "USB Product Name") as? String ?? "").lowercased()
        return !name.contains("internal")
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func className(_ entry: io_registry_entry_t) -> String {
        guard let name = IOObjectCopyClass(entry)?.takeRetainedValue() else { return "" }
        return name as String
    }
}

/// Advice the user dismissed; it does not come back for the same drives.
struct SpeedAdviceDismissals {
    static let defaultsKey = "speedAdvice.dismissed"
    var defaults: UserDefaults = .standard

    var keys: Set<String> {
        Set(defaults.stringArray(forKey: Self.defaultsKey) ?? [])
    }

    func dismiss(_ advice: SpeedAdvice) {
        var all = keys
        all.insert(advice.dismissKey)
        defaults.set(all.sorted(), forKey: Self.defaultsKey)
    }
}

/// The after-copy sentence per movie, until that movie's next run.
@MainActor
final class SpeedNoteStore: ObservableObject {
    static let shared = SpeedNoteStore()
    @Published private(set) var notes: [UUID: String] = [:]

    func set(_ note: String?, for configId: UUID) {
        notes[configId] = note
    }
}
