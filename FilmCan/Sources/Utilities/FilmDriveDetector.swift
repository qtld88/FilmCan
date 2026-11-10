import Foundation

/// Drive-name rules ("A0*", "SOUND*/ZOOM*") and the mounted sources/destinations a
/// movie would pick up. Reads the disk, writes nothing: the main window's editor
/// saves what it finds into the movie, Quick Copy only fills its form.
enum FilmDriveDetector {

    struct Detected: Equatable {
        struct Source: Equatable {
            let path: String
            /// nil ⇒ let the caller guess from the content.
            let kind: SourceMediaKind?
        }
        var sources: [Source] = []
        var destinations: [String] = []
    }

    /// The movie's own sources and destinations that exist right now (excluded ones
    /// left out), plus the mounted drives its auto-detect rules match.
    static func detect(film: BackupConfiguration,
                       volumes: [URL] = mountedExternalVolumes(),
                       pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                       cardRole: (String) -> CardRole? = detectedCardRole) -> Detected {
        var result = Detected()

        var destinations = film.includedDestinationPaths.filter(pathExists)
        if film.destinationAutoDetectEnabled {
            for path in matchingPaths(rules: film.destinationAutoDetectPatterns, volumes: volumes)
            where !destinations.contains(path) {
                destinations.append(path)
            }
        }
        result.destinations = destinations

        func isOnDestination(_ path: String) -> Bool {
            destinations.contains { $0 == path || $0.hasPrefix(path + "/") || path.hasPrefix($0 + "/") }
        }
        func add(_ path: String, _ kind: SourceMediaKind?) {
            guard !isOnDestination(path), !film.excludedSourcePaths.contains(path) else { return }
            if let index = result.sources.firstIndex(where: { $0.path == path }) {
                if result.sources[index].kind == nil, let kind {
                    result.sources[index] = .init(path: path, kind: kind)
                }
                return
            }
            result.sources.append(.init(path: path, kind: kind))
        }

        for path in film.includedSourcePaths where pathExists(path) {
            add(path, film.sourceMediaKinds[path])
        }
        if film.sourceAutoDetectEnabled {
            for path in matchingPaths(rules: film.sourceAutoDetectPatterns, volumes: volumes) {
                add(path, film.sourceMediaKinds[path])
            }
        }
        if film.soundAutoDetectEnabled {
            for path in matchingPaths(rules: film.soundAutoDetectPatterns, volumes: volumes) {
                add(path, .sound)
            }
        }
        if film.cardAutoDetectEnabled {
            for volume in volumes {
                guard let role = cardRole(volume.path), role != .notACard else { continue }
                add(volume.path, role == .sound ? .sound : .camera)
            }
        }
        return result
    }

    /// Card recognised on `path` (the user's "not a card" / role override wins).
    static func detectedCardRole(_ path: String) -> CardRole? {
        if let override = FanOutCopier.sourceVolumeUUID(path).flatMap({ CardRoleOverrides.role(forVolumeUUID: $0) }) {
            return override
        }
        guard let signature = CameraCardDetector.detect(rootPath: path) else { return nil }
        return signature.brand.isSound ? .sound : .camera
    }

    // MARK: Rules

    static func matchingPaths(rules: [String], volumes: [URL]) -> [String] {
        let rules = rules
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var paths: [String] = []
        for volumeURL in volumes {
            for rule in rules {
                let (pattern, subpath) = splitRule(rule)
                guard matches(volumeURL.lastPathComponent, pattern: pattern) else { continue }
                for resolved in resolveSubpathMatches(rootURL: volumeURL, subpath: subpath)
                where !paths.contains(resolved) {
                    paths.append(resolved)
                }
            }
        }
        return paths
    }

    static func mountedExternalVolumes() -> [URL] {
        let volumesURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: volumesURL, includingPropertiesForKeys: [.volumeIsInternalKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return entries.filter { url in
            let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey])
            return values?.volumeIsInternal != true
        }
    }

    static func splitRule(_ rule: String) -> (String, String) {
        guard let separatorIndex = rule.firstIndex(of: "/") else {
            return (rule, "")
        }
        let drive = String(rule[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = String(rule[rule.index(after: separatorIndex)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (drive, folder)
    }

    static func matches(_ name: String, pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("*") {
            let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            let regex = "^" + escaped.replacingOccurrences(of: "\\*", with: ".*") + "$"
            return name.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
        }
        return name.compare(trimmed, options: [.caseInsensitive]) == .orderedSame
    }

    static func resolveSubpathMatches(rootURL: URL, subpath: String) -> [String] {
        let trimmed = subpath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [rootURL.path] }

        if !trimmed.contains("*") {
            let resolvedURL = rootURL.appendingPathComponent(trimmed)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: resolvedURL.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return [resolvedURL.path]
            }
            return []
        }

        let components = trimmed
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return [rootURL.path] }

        var currentURLs: [URL] = [rootURL]
        let fm = FileManager.default

        for componentPattern in components {
            var nextURLs: [URL] = []
            for baseURL in currentURLs {
                guard let children = try? fm.contentsOfDirectory(
                    at: baseURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for child in children where matches(child.lastPathComponent, pattern: componentPattern) {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        nextURLs.append(child)
                    }
                }
            }
            currentURLs = nextURLs
            if currentURLs.isEmpty { break }
        }

        return currentURLs.map { $0.path }
    }
}
