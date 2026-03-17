import Foundation

enum LogFolderNamer {
    static func resolveFolderPath(
        template: String,
        destination: String,
        sources: [String],
        date: Date = Date()
    ) -> String {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let expanded = (trimmed as NSString).expandingTildeInPath

        let formatterDate = DateFormatter()
        formatterDate.dateFormat = "yyyyMMdd"
        let formatterTime = DateFormatter()
        formatterTime.dateFormat = "HHmmss"
        let formatterDateTime = DateFormatter()
        formatterDateTime.dateFormat = "yyyyMMdd-HHmmss"

        let dateStr = formatterDate.string(from: date)
        let timeStr = formatterTime.string(from: date)
        let dateTimeStr = formatterDateTime.string(from: date)

        let sourcePath = sources.first ?? ""
        let sourceName = (sourcePath as NSString).lastPathComponent
        let sourceParent = ((sourcePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let sourceDriveName = volumeName(for: sourcePath)
        let destinationDriveName = volumeName(for: destination)
        let destinationName = (destination as NSString).lastPathComponent

        let fileName = sourceName
        let ext = (fileName as NSString).pathExtension
        let baseName = ext.isEmpty ? fileName : (fileName as NSString).deletingPathExtension

        let fileCreatedDate = fileDateString(for: sourcePath, attribute: .creationDate)
        let fileModifiedDate = fileDateString(for: sourcePath, attribute: .modificationDate)

        let tokenValues: [String: String] = [
            "{source}": sourceName,
            "{sourceParent}": sourceParent,
            "{driveName}": sourceDriveName,
            "{sourceDriveName}": sourceDriveName,
            "{destinationDriveName}": destinationDriveName,
            "{destination}": destinationName,
            "{date}": dateStr,
            "{time}": timeStr,
            "{datetime}": dateTimeStr,
            "{counter}": "001",
            "{filename}": baseName,
            "{ext}": ext.isEmpty ? "" : ".\(ext)",
            "{filecreationdate}": fileCreatedDate,
            "{filemodifieddate}": fileModifiedDate
        ]

        var resolved = expanded.replacingOccurrences(of: "\\", with: "/")
        for (token, value) in tokenValues {
            resolved = resolved.replacingOccurrences(of: token, with: value)
        }

        return sanitizePath(resolved)
    }

    private static func sanitizePath(_ path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let isAbsolute = normalized.hasPrefix("/")
        let components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .compactMap { sanitizePathComponent(String($0)) }

        guard !components.isEmpty else { return isAbsolute ? "/" : "" }
        let joined = components.joined(separator: "/")
        return isAbsolute ? "/" + joined : joined
    }

    private static func sanitizePathComponent(_ name: String) -> String? {
        if name == "." || name == ".." { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_. ()")
        var result = ""
        result.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            if allowed.contains(scalar) {
                result.append(Character(scalar))
            } else {
                result.append("_")
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func fileDateString(for path: String, attribute: FileAttributeKey) -> String {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let date = attrs?[attribute] as? Date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return date.map { formatter.string(from: $0) } ?? formatter.string(from: Date())
    }

    private static func volumeName(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let name = values.volumeName, !name.isEmpty {
            return name
        }
        let rootName = FileManager.default.displayName(atPath: "/")
        return rootName.isEmpty ? "Drive" : rootName
    }
}
