import Foundation

/// Recognises the same card's clips whatever roll name, drive or folder layout a run
/// gave them.
///
/// A clip key is "name|size|modified", one per file of at least 1 MiB on the card
/// (small sidecar files change between cameras and runs). Folders are left out, so
/// copying the card folder or only its content gives the same keys. A card that was
/// formatted (quick or full) and filled again has new clips: the same names come
/// back (C0001.MP4) but the size and the modification time differ, so its keys do not
/// match the earlier card's.
enum CardFingerprint {

    static let minimumClipBytes: Int64 = 1 << 20

    static func key(name: String, size: Int64, modified: Date) -> String {
        "\(name)|\(size)|\(Int64(modified.timeIntervalSince1970.rounded(.down)))"
    }

    /// Clip keys of a source on disk: every visible file of at least 1 MiB below it,
    /// or the file itself for a single-file source. Reads metadata only, no data.
    static func keys(forSource path: String) -> [String] {
        let fm = FileManager.default
        let props: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let root = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return [] }
        guard isDir.boolValue else {
            return clipKey(for: root, props: props).map { [$0] } ?? []
        }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: props,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        var keys: [String] = []
        for case let url as URL in enumerator {
            if let key = clipKey(for: url, props: props) { keys.append(key) }
        }
        return keys.sorted()
    }

    private static func clipKey(for url: URL, props: [URLResourceKey]) -> String? {
        guard let values = try? url.resourceValues(forKeys: Set(props)),
              values.isDirectory != true,
              let size = values.fileSize, Int64(size) >= minimumClipBytes,
              let modified = values.contentModificationDate
        else { return nil }
        return key(name: url.lastPathComponent, size: Int64(size), modified: modified)
    }

    /// Weaker key for catalog entries recorded before clip keys existed: name and size
    /// of each large file. Used only when a whole set matches, never a single clip.
    static func legacyKey(relPath: String, size: Int64) -> String {
        "\((relPath as NSString).lastPathComponent)|\(size)"
    }
}
