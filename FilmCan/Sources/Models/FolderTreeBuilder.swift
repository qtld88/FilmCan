import Foundation

/// One folder (or file) line of the "what will be created" preview.
struct FolderTreeLine: Equatable {
    let depth: Int
    let name: String
    let isNew: Bool
    /// Set on the user-named Camera/Sound folder line (name "" = still to name).
    var mediaKind: SourceMediaKind? = nil
    var isRoot = false
    var role: Role = .folder
    var isEditable: Bool { isRoot || mediaKind != nil }
    /// The copied folder itself, or its contents: the line that switches between both.
    var togglesCopyMode: Bool { role == .copiedFolder || role == .contents }

    enum Role: Equatable { case folder, copiedFolder, copiedFile, contents }

    /// A folder that will be created gets a "new" mark; files and "contents of" lines do not.
    static func showsNewBadge(_ line: FolderTreeLine) -> Bool {
        line.isNew && !line.name.isEmpty && (line.role == .folder || line.role == .copiedFolder)
    }
}

/// Resolves, with the engine's own path function, the folders a copy creates under
/// a destination. Shared by Quick Copy and the main window so both read the same.
enum FolderTreeBuilder {

    struct Source: Equatable {
        let path: String
        let isDirectory: Bool
        var kind: SourceMediaKind = .camera
        /// Roll folder given to a generic-named card (Untitled_01); nil ⇒ the card's own name.
        var rollName: String? = nil
        var name: String { (path as NSString).lastPathComponent }
    }

    struct Options {
        /// The preset the engine runs with; nil ⇒ no organization.
        var preset: OrganizationPreset?
        var organizationActive = false
        var copyContents = false
        var date = Date()
        var metadata: ShootMetadata = .empty
        /// Quick Copy only: the preset has no separate Camera/Sound folder, so the user names one.
        var lacksMediaFolder = false
        var hasTypedMediaFolder: (SourceMediaKind) -> Bool = { _ in false }
        /// Preset whose templates locate the Camera/Sound component (before typed names).
        var mediaIndexPreset: OrganizationPreset?
        var pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    }

    static func template(for kind: SourceMediaKind, in p: OrganizationPreset) -> String {
        kind == .sound && !isBlank(p.soundFolderTemplate) ? p.soundFolderTemplate : p.folderTemplate
    }

    /// The `Camera_Media` / `Sound_Media` component, else the last one below the root.
    static func mediaComponentIndex(in template: String, kind: SourceMediaKind) -> Int? {
        let parts = template.split(separator: "/")
        let marker = kind == .sound ? "Sound_Media" : "Camera_Media"
        if let index = parts.firstIndex(where: { $0 == marker }), index > 0 { return index }
        return parts.count >= 2 ? parts.count - 1 : nil
    }

    static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Path of each source under `destination`, relative to it.
    static func relativePaths(for destination: String, sources: [Source], options: Options) -> [String] {
        let prefixes = [destination, (destination as NSString).resolvingSymlinksInPath]
            .map { $0.hasSuffix("/") ? $0 : $0 + "/" }
        return sources.map { source in
            let full = FanOutCopier.resolveDestFilePath(
                destRoot: destination, rootName: source.rollName ?? source.name, rootPath: source.path, relPath: "",
                preset: options.preset, copyFolderContents: false,
                date: options.date, metadata: options.metadata, mediaKind: source.kind,
                rollNameIsAssigned: source.rollName != nil)
            guard let prefix = prefixes.first(where: { full.hasPrefix($0) }) else { return source.name }
            return String(full.dropFirst(prefix.count))
        }
    }

    /// What will be created under `destination`; `isNew` = does not exist yet.
    static func lines(for destination: String, sources: [Source], options o: Options) -> [FolderTreeLine] {
        var lines: [FolderTreeLine] = []
        var seen = Set<String>()
        for (source, rel) in zip(sources, relativePaths(for: destination, sources: sources, options: o)) {
            var components = rel.split(separator: "/").map(String.init)
            var rollName: String?
            if o.copyContents && source.isDirectory && source.rollName == nil {
                // Contents land flat in the parent; the roll folder only holds the hash list.
                rollName = components.popLast()
            }
            var mediaIndex: Int?
            if o.lacksMediaFolder {
                let end = rollName != nil ? components.count : components.count - 1
                if !o.hasTypedMediaFolder(source.kind) {
                    components.insert("", at: max(end, 0))
                    mediaIndex = max(end, 0)
                } else {
                    mediaIndex = end - 1
                }
            } else if o.organizationActive, let p = o.mediaIndexPreset {
                let folderCount = rollName != nil ? components.count : components.count - 1
                mediaIndex = mediaComponentIndex(in: template(for: source.kind, in: p), kind: source.kind)
                    .flatMap { $0 < folderCount ? $0 : nil }
            }
            var cumulative = destination
            for (depth, component) in components.enumerated() {
                let isMedia = depth == mediaIndex
                if component.isEmpty {
                    if seen.insert(cumulative + "/\u{0}\(source.kind.rawValue)").inserted {
                        lines.append(FolderTreeLine(depth: depth, name: "", isNew: true, mediaKind: source.kind))
                    }
                    continue
                }
                cumulative = (cumulative as NSString).appendingPathComponent(component)
                if seen.insert(cumulative).inserted {
                    let isItem = rollName == nil && depth == components.count - 1
                    let isRoot = o.organizationActive && depth == 0 && !isItem
                    let role: FolderTreeLine.Role = isItem ? (source.isDirectory ? .copiedFolder : .copiedFile) : .folder
                    lines.append(FolderTreeLine(depth: depth, name: component, isNew: !o.pathExists(cumulative),
                                                mediaKind: isMedia && !isRoot && !isItem ? source.kind : nil,
                                                isRoot: isRoot, role: role))
                }
            }
            if rollName != nil {
                lines.append(FolderTreeLine(depth: components.count, name: "contents of \(source.name)",
                                            isNew: true, role: .contents))
            }
        }
        return lines
    }
}
