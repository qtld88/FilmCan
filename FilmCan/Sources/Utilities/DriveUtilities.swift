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
            .volumeTotalCapacityKey
        ])
        var total: Int64? = nil

        if let values,
           let cap = values.volumeTotalCapacity,
           cap > 0 {
            total = Int64(cap)
        } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                  let cap = attrs[.systemSize] as? Int64,
                  cap > 0 {
            total = cap
        }

        return (total, liveAvailableBytes(for: path))
    }

    /// Best estimate of how many bytes a backup can actually write here.
    ///
    /// Two macOS metrics disagree and each is wrong in one direction:
    ///   - `statfs` `.systemFreeSize` updates immediately on delete but, on APFS,
    ///     EXCLUDES purgeable space — it under-reports (e.g. 11 GB when Finder
    ///     shows 65 GB), which falsely blocks a copy that would succeed.
    ///   - `volumeAvailableCapacityForImportantUsage` matches Finder and includes
    ///     reclaimable/purgeable space, but is cached and lags for a while after
    ///     the user frees space — it over-reports "full" right after a delete.
    ///
    /// Taking the MAX of the two is correct in both directions: right after a
    /// delete statfs is the higher (fresh) value; in the purgeable case
    /// ImportantUsage is the higher (Finder-matching) value. This fixes both the
    /// "emptied the drive but still shows full" report AND the false
    /// "Not enough space" that blocked valid backups to the internal drive.
    static func liveAvailableBytes(for path: String) -> Int64? {
        var best: Int64? = nil
        func consider(_ value: Int64?) {
            guard let value, value > 0 else { return }
            best = max(best ?? 0, value)
        }

        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path) {
            consider(attrs[.systemFreeSize] as? Int64)
        }
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) {
            consider(values.volumeAvailableCapacityForImportantUsage)
        }
        if best == nil,
           let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]) {
            consider(values.volumeAvailableCapacity.map(Int64.init))
        }
        return best
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
