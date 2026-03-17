import Foundation

struct SourceFileEntry {
    let sourcePath: String
    let sourceRoot: String
    let relativePath: String
    let size: Int64
    let sourceIsDirectory: Bool
}

enum FileEnumerator {
    static func enumerateFiles(
        sources: [String],
        preset: OrganizationPreset?
    ) async -> [SourceFileEntry] {
        await Task.detached(priority: .utility) {
            var entries: [SourceFileEntry] = []
            let fm = FileManager.default

            let includePatterns = normalizedPatterns(preset?.includePatterns ?? [])
            let copyOnlyPatterns = normalizedPatterns(preset?.copyOnlyPatterns ?? [])
            var excludePatterns = normalizedPatterns(preset?.excludePatterns ?? [])
            if excludePatterns.isEmpty {
                excludePatterns = RsyncOptions.defaultExcludedPatterns
            }

            let excludedDirectoryNames: Set<String> = [
                ".Trashes",
                ".fseventsd",
                ".Spotlight-V100",
                ".DocumentRevisions-V100",
                ".TemporaryItems",
                FilmCanPaths.hidden
            ]
            let excludedDirs = excludedDirectoryNames.union([FilmCanPaths.hidden])

            let keys: Set<URLResourceKey> = [
                .isRegularFileKey,
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
                .fileAllocatedSizeKey,
                .totalFileAllocatedSizeKey
            ]

            for source in sources {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: source, isDirectory: &isDir) else { continue }

                if isDir.boolValue {
                    let sourceURL = URL(fileURLWithPath: source)
                    if let enumerator = fm.enumerator(
                        at: sourceURL,
                        includingPropertiesForKeys: Array(keys),
                        options: [],
                        errorHandler: nil
                    ) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            let path = fileURL.path
                            if FilmCanPaths.isHidden(path) {
                                enumerator.skipDescendants()
                                continue
                            }
                            let values = try? fileURL.resourceValues(forKeys: keys)
                            if values?.isSymbolicLink == true {
                                continue
                            }
                            if values?.isDirectory == true {
                                if excludedDirs.contains(fileURL.lastPathComponent) {
                                    enumerator.skipDescendants()
                                }
                                continue
                            }
                            guard values?.isRegularFile == true else { continue }

                            let relative = relativePath(from: sourceURL, fileURL: fileURL)
                            guard !relative.isEmpty else { continue }

                            if shouldInclude(
                                relativePath: relative,
                                fileName: fileURL.lastPathComponent,
                                includePatterns: includePatterns,
                                copyOnlyPatterns: copyOnlyPatterns,
                                excludePatterns: excludePatterns
                            ) {
                                let logicalSize = Int64(values?.fileSize ?? 0)
                                let allocatedSize = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
                                let size = max(logicalSize, allocatedSize)
                                entries.append(
                                    SourceFileEntry(
                                        sourcePath: path,
                                        sourceRoot: source,
                                        relativePath: relative,
                                        size: size,
                                        sourceIsDirectory: true
                                    )
                                )
                            }
                        }
                    }
                } else {
                    let fileURL = URL(fileURLWithPath: source)
                    let relative = fileURL.lastPathComponent
                    if shouldInclude(
                        relativePath: relative,
                        fileName: fileURL.lastPathComponent,
                        includePatterns: includePatterns,
                        copyOnlyPatterns: copyOnlyPatterns,
                        excludePatterns: excludePatterns
                    ) {
                        let values = try? fileURL.resourceValues(forKeys: keys)
                        let logicalSize = Int64(values?.fileSize ?? 0)
                        let allocatedSize = Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
                        let size = max(logicalSize, allocatedSize)
                        entries.append(
                            SourceFileEntry(
                                sourcePath: source,
                                sourceRoot: source,
                                relativePath: relative,
                                size: size,
                                sourceIsDirectory: false
                            )
                        )
                    }
                }
            }

            return entries
        }.value
    }

    private static func relativePath(from root: URL, fileURL: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let filePath = fileURL.path
        guard filePath.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
        let rel = String(filePath.dropFirst(rootPath.count))
        return rel
    }

    private static func normalizedPatterns(_ patterns: [String]) -> [String] {
        patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func shouldInclude(
        relativePath: String,
        fileName: String,
        includePatterns: [String],
        copyOnlyPatterns: [String],
        excludePatterns: [String]
    ) -> Bool {
        if matchesAny(patterns: excludePatterns, relativePath: relativePath, fileName: fileName) {
            return false
        }
        if !includePatterns.isEmpty {
            return matchesAny(patterns: includePatterns, relativePath: relativePath, fileName: fileName)
        }
        if !copyOnlyPatterns.isEmpty {
            return matchesAny(patterns: copyOnlyPatterns, relativePath: relativePath, fileName: fileName)
        }
        return true
    }

    private static func matchesAny(patterns: [String], relativePath: String, fileName: String) -> Bool {
        for pattern in patterns {
            let target = pattern.contains("/") ? relativePath : fileName
            if matches(target, pattern: pattern) {
                return true
            }
        }
        return false
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
}
