import Foundation

enum LogFileNamer {
    static func makeFileName(
        template: String,
        configName: String,
        destination: String,
        sources: [String],
        date: Date = Date()
    ) -> String {
        let safeTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTemplate = safeTemplate.isEmpty ? "transfer_{datetime}" : safeTemplate

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
        let destName = (destination as NSString).lastPathComponent
        let fileName = sourceName
        let ext = (fileName as NSString).pathExtension
        let baseName = ext.isEmpty ? fileName : (fileName as NSString).deletingPathExtension
        let fileCreatedDate = fileDateString(for: sourcePath, attribute: .creationDate)
        let fileModifiedDate = fileDateString(for: sourcePath, attribute: .modificationDate)

        var name = baseTemplate
        name = name.replacingOccurrences(of: "{date}", with: dateStr)
        name = name.replacingOccurrences(of: "{time}", with: timeStr)
        name = name.replacingOccurrences(of: "{datetime}", with: dateTimeStr)
        name = name.replacingOccurrences(of: "{name}", with: configName)
        name = name.replacingOccurrences(of: "{source}", with: sourceName)
        name = name.replacingOccurrences(of: "{sourceParent}", with: sourceParent)
        name = name.replacingOccurrences(of: "{driveName}", with: sourceDriveName)
        name = name.replacingOccurrences(of: "{sourceDriveName}", with: sourceDriveName)
        name = name.replacingOccurrences(of: "{destinationDriveName}", with: destinationDriveName)
        name = name.replacingOccurrences(of: "{destination}", with: destName)
        name = name.replacingOccurrences(of: "{counter}", with: "001")
        name = name.replacingOccurrences(of: "{filename}", with: baseName)
        name = name.replacingOccurrences(of: "{ext}", with: ext.isEmpty ? "" : ".\(ext)")
        name = name.replacingOccurrences(of: "{filecreationdate}", with: fileCreatedDate)
        name = name.replacingOccurrences(of: "{filemodifieddate}", with: fileModifiedDate)

        return sanitizeRelativePath(name)
    }

    static func previewName(template: String) -> String {
        makeFileName(
            template: template,
            configName: "Backup",
            destination: "Destination",
            sources: ["Source"],
            date: Date(timeIntervalSince1970: 1_707_803_200)
        )
    }

    private static func sanitizeRelativePath(_ path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        var components = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if components.isEmpty {
            components = ["transfer_{datetime}"]
        }

        if let last = components.last, !last.lowercased().hasSuffix(".log") {
            components[components.count - 1] = last + ".log"
        }

        let sanitized = components.compactMap { sanitizePathComponent($0) }
        if sanitized.isEmpty {
            return "transfer_{datetime}.log"
        }
        return sanitized.joined(separator: "/")
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
}
