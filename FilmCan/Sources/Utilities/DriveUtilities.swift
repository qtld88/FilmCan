import Foundation

enum DriveUtilities {
    enum IconStyle {
        case filled
        case regular
    }

    struct Summary {
        let id: String
        let name: String
        let isExternal: Bool
        let isRoot: Bool
        let formatDescription: String?
        let fileSystemType: String?
        let isReadOnly: Bool?

        var formatLabel: String? {
            if let formatDescription, !formatDescription.isEmpty {
                return formatDescription
            }
            if let fileSystemType, !fileSystemType.isEmpty {
                return fileSystemType.uppercased()
            }
            return nil
        }
    }
    
    static func summary(for path: String) -> Summary {
        let url = URL(fileURLWithPath: path)
        let volumeFileSystemTypeKey = URLResourceKey(rawValue: "volumeFileSystemType")
        let values = try? url.resourceValues(forKeys: [
            .volumeUUIDStringKey,
            .volumeNameKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeLocalizedFormatDescriptionKey,
            volumeFileSystemTypeKey,
            .volumeIsReadOnlyKey
        ])
        let fileSystemType = values?.allValues[volumeFileSystemTypeKey] as? String
        
        let id = values?.volumeUUIDString ?? volumeRootPath(for: path) ?? values?.volumeName ?? path
        let name = values?.volumeName ?? "Drive"
        let isExternal = (values?.volumeIsInternal == false) || (values?.volumeIsRemovable == true)
        let isRoot = isDriveRoot(path: path, volumeName: values?.volumeName)
        return Summary(
            id: id,
            name: name,
            isExternal: isExternal,
            isRoot: isRoot,
            formatDescription: values?.volumeLocalizedFormatDescription,
            fileSystemType: fileSystemType,
            isReadOnly: values?.volumeIsReadOnly
        )
    }
    
    static func driveId(for path: String) -> String {
        summary(for: path).id
    }

    static func driveIconName(isExternal: Bool, style: IconStyle = .filled) -> String {
        if isExternal {
            return style == .filled ? "externaldrive.fill" : "externaldrive"
        }
        return "internaldrive"
    }

    static func itemIconName(isDirectory: Bool, style: IconStyle = .filled) -> String {
        switch style {
        case .filled:
            return isDirectory ? "folder.fill" : "doc.fill"
        case .regular:
            return isDirectory ? "folder" : "doc"
        }
    }

    static func iconName(
        isExternal: Bool,
        isRoot: Bool,
        isDirectory: Bool,
        style: IconStyle = .filled,
        treatExternalAsDrive: Bool = true,
        treatRootAsDrive: Bool = true
    ) -> String {
        if (treatRootAsDrive && isRoot) || (treatExternalAsDrive && isExternal) {
            return driveIconName(isExternal: isExternal, style: style)
        }
        return itemIconName(isDirectory: isDirectory, style: style)
    }

    static func iconName(
        for path: String,
        style: IconStyle = .filled,
        treatExternalAsDrive: Bool = true,
        treatRootAsDrive: Bool = true
    ) -> String {
        let summary = summary(for: path)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return iconName(
            isExternal: summary.isExternal,
            isRoot: summary.isRoot,
            isDirectory: isDir.boolValue,
            style: style,
            treatExternalAsDrive: treatExternalAsDrive,
            treatRootAsDrive: treatRootAsDrive
        )
    }

    static func capacity(for path: String) -> (total: Int64?, available: Int64?) {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        var total: Int64? = nil
        var available: Int64? = nil

        if let values,
           let cap = values.volumeTotalCapacity,
           cap > 0 {
            total = Int64(cap)
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                  let cap = attrs[.systemSize] as? Int64,
                  cap > 0 {
            total = cap
        }

        if let values,
           let cap = values.volumeAvailableCapacity {
            available = max(Int64(cap), 0)
        } else if let values,
                  let cap = values.volumeAvailableCapacityForImportantUsage {
            available = max(Int64(cap), 0)
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                  let cap = attrs[.systemFreeSize] as? Int64 {
            available = max(cap, 0)
        }

        return (total, available)
    }

    static func isExFAT(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let volumeFileSystemTypeKey = URLResourceKey(rawValue: "volumeFileSystemType")
        let values = try? url.resourceValues(forKeys: [
            .volumeLocalizedFormatDescriptionKey,
            volumeFileSystemTypeKey
        ])

        if let format = values?.volumeLocalizedFormatDescription?.lowercased(),
           format.contains("exfat") {
            return true
        }

        if let fsType = values?.allValues[volumeFileSystemTypeKey] as? String,
           fsType.lowercased() == "exfat" {
            return true
        }

        return false
    }
    
    private static func isDriveRoot(path: String, volumeName: String?) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalizedPath == "/" {
            return true
        }
        if let root = volumeRootPath(for: path) {
            return normalizedPath == root
        }
        guard let volumeName, !volumeName.isEmpty else { return false }
        let expectedRoot = "/Volumes/\(volumeName)"
        return normalizedPath == expectedRoot
    }

    private static func volumeRootPath(for path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return "/Volumes/\(components[2])"
    }
}
