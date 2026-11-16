import Foundation

enum GenericRollNameScanner {
    /// Folder names already present in the roll parent of `source` on each destination.
    static func existingNames(source: String, destinations: [String],
                              preset: OrganizationPreset?, date: Date,
                              metadata: ShootMetadata, mediaKind: SourceMediaKind,
                              fileManager: FileManager = .default) -> [String] {
        let base = GenericCardName.baseName((source as NSString).lastPathComponent)
        var names: [String] = []
        for destination in destinations {
            let roll = FanOutCopier.resolveRollFolder(
                destRoot: destination, rootName: base, rootPath: source,
                isDirectoryRoot: true, preset: preset, copyFolderContents: false,
                date: date, metadata: metadata, mediaKind: mediaKind,
                rollNameIsAssigned: true)
            let parent = (roll as NSString).deletingLastPathComponent
            names.append(contentsOf: (try? fileManager.contentsOfDirectory(atPath: parent)) ?? [])
        }
        return names
    }
}
