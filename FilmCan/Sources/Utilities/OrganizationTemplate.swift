import Foundation

enum OrganizationTemplate {
    struct ResolvedDestination {
        let folderPath: String
        let renamedItem: String
    }

    static func resolve(
        preset: OrganizationPreset,
        sourcePath: String,
        destinationRoot: String,
        counter: Int,
        date: Date
    ) -> ResolvedDestination {
        let effectiveDate = preset.useCustomDate ? preset.customDate : date
        let sourceName = (sourcePath as NSString).lastPathComponent
        let sourceParent = ((sourcePath as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let sourceDriveName = volumeName(for: sourcePath)
        let destinationDriveName = volumeName(for: destinationRoot)
        let destinationName = (destinationRoot as NSString).lastPathComponent
        let fileModifiedDate = fileDateString(for: sourcePath, attribute: .modificationDate)
        let fileCreatedDate = fileDateString(for: sourcePath, attribute: .creationDate)

        let tokenValues = baseTokenValues(
            sourceName: sourceName,
            sourceParent: sourceParent,
            sourceDriveName: sourceDriveName,
            destinationDriveName: destinationDriveName,
            destinationName: destinationName,
            counter: counter,
            date: effectiveDate,
            fileModifiedDate: fileModifiedDate,
            fileCreatedDate: fileCreatedDate
        )

        let folderTemplate = preset.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFolder = (!preset.useFolderTemplate || folderTemplate.isEmpty)
            ? ""
            : applyTokens(folderTemplate, values: tokenValues, allowPathSeparators: true)

        let renameTemplate = preset.renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let renameOnly = preset.renameOnlyPatterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let shouldRename = renameOnly.isEmpty
            || renameOnly.contains { matches(sourceName, pattern: $0) }
        let resolvedName = (!preset.useRenameTemplate || renameTemplate.isEmpty || !shouldRename)
            ? sourceName
            : resolveRename(
                template: renameTemplate,
                sourcePath: sourcePath,
                tokenValues: tokenValues
            )

        return ResolvedDestination(folderPath: resolvedFolder, renamedItem: resolvedName)
    }

    static func resolveFolder(
        preset: OrganizationPreset,
        sourceName: String,
        destinationName: String,
        sourceParent: String = "",
        sourceDriveName: String = "",
        destinationDriveName: String = "",
        counter: Int,
        date: Date
    ) -> String {
        let effectiveDate = preset.useCustomDate ? preset.customDate : date
        let tokenValues = baseTokenValues(
            sourceName: sourceName,
            sourceParent: sourceParent,
            sourceDriveName: sourceDriveName,
            destinationDriveName: destinationDriveName,
            destinationName: destinationName,
            counter: counter,
            date: effectiveDate,
            fileModifiedDate: "",
            fileCreatedDate: ""
        )
        let folderTemplate = preset.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preset.useFolderTemplate || folderTemplate.isEmpty { return "" }
        return applyTokens(folderTemplate, values: tokenValues, allowPathSeparators: true)
    }

    static func resolveRename(
        template: String,
        sourcePath: String,
        tokenValues: [String: String]
    ) -> String {
        let fileName = (sourcePath as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension
        let baseName = ext.isEmpty ? fileName : (fileName as NSString).deletingPathExtension

        var values = tokenValues
        values["{filename}"] = baseName
        values["{ext}"] = ext.isEmpty ? "" : ".\(ext)"

        return applyTokens(template, values: values, allowPathSeparators: false)
    }

    private static func baseTokenValues(
        sourceName: String,
        sourceParent: String,
        sourceDriveName: String,
        destinationDriveName: String,
        destinationName: String,
        counter: Int,
        date: Date,
        fileModifiedDate: String,
        fileCreatedDate: String
    ) -> [String: String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HHmmss"
        let dateTimeFormatter = DateFormatter()
        dateTimeFormatter.dateFormat = "yyyyMMdd-HHmmss"

        let counterStr = String(format: "%03d", counter)

        return [
            "{source}": sourceName,
            "{sourceParent}": sourceParent,
            "{driveName}": sourceDriveName,
            "{sourceDriveName}": sourceDriveName,
            "{destinationDriveName}": destinationDriveName,
            "{destination}": destinationName,
            "{date}": dateFormatter.string(from: date),
            "{time}": timeFormatter.string(from: date),
            "{datetime}": dateTimeFormatter.string(from: date),
            "{counter}": counterStr,
            "{filemodifieddate}": fileModifiedDate,
            "{filecreationdate}": fileCreatedDate
        ]
    }

    private static func fileDateString(for path: String, attribute: FileAttributeKey) -> String {
        let fm = FileManager.default
        let attrs = try? fm.attributesOfItem(atPath: path)
        let date = attrs?[attribute] as? Date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return date.map { formatter.string(from: $0) } ?? formatter.string(from: Date())
    }

    private static func matches(_ name: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            let regex = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
            return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return name.compare(trimmed, options: [.caseInsensitive]) == .orderedSame
    }

    private static func applyTokens(_ template: String, values: [String: String], allowPathSeparators: Bool) -> String {
        var result = template
        for (token, value) in values {
            result = result.replacingOccurrences(of: token, with: value)
        }
        return sanitizeTemplate(result, allowPathSeparators: allowPathSeparators)
    }

    private static func sanitizeTemplate(_ value: String, allowPathSeparators: Bool) -> String {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        if allowPathSeparators {
            let components = normalized
                .split(separator: "/", omittingEmptySubsequences: true)
                .compactMap { sanitizePathComponent(String($0)) }
            return components.joined(separator: "/")
        }
        return sanitizePathComponent(normalized) ?? "Unnamed"
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
