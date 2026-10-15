import Foundation

/// Guesses whether a Finder selection item is camera media or production sound.
/// A folder is Sound when strictly more than half of its (visible, bounded-scan)
/// files have an audio extension; a single file is classified by its own extension.
enum MediaKindGuesser {
    static let audioExtensions: Set<String> = ["wav", "bwf", "aif", "aiff", "mp3", "m4a", "flac"]

    /// Files examined per folder — keeps the guess instant on a full card.
    static let scanLimit = 2000

    static func guess(path: String, fileManager: FileManager = .default) -> SourceMediaKind {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else { return .camera }
        if !isDir.boolValue { return isAudio(path) ? .sound : .camera }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: path).resolvingSymlinksInPath(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return .camera }

        var total = 0
        var audio = 0
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            total += 1
            if isAudio(url.path) { audio += 1 }
            if total >= scanLimit { break }
        }
        return total > 0 && audio * 2 > total ? .sound : .camera
    }

    private static func isAudio(_ path: String) -> Bool {
        audioExtensions.contains((path as NSString).pathExtension.lowercased())
    }
}
