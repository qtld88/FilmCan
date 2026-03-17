import Foundation

enum PreviewCalculator {
    private struct CacheEntry {
        let size: Int64
        let files: Int
        let folders: Int
        let itemCount: Int
        let modified: Date?
    }

    private static var cache: [String: CacheEntry] = [:]
    private static let cacheLock = NSLock()

    static func calculateTotalsAndSizes(for sources: [String]) -> (Int64, Int, Int, [String: Int64], [String: Int]) {
        var totalBytes: Int64 = 0
        var totalFiles = 0
        var totalFolders = 0
        var sizes: [String: Int64] = [:]
        var itemCounts: [String: Int] = [:]
        let fm = FileManager.default

        for path in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else { continue }

            let modDate = (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
            if let cached = cachedEntry(for: path, modified: modDate) {
                totalBytes += cached.size
                totalFiles += cached.files
                totalFolders += cached.folders
                sizes[path] = cached.size
                itemCounts[path] = cached.itemCount
                continue
            }

            if !isDir.boolValue {
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let size = attrs[.size] as? Int64 {
                    totalBytes += size
                    sizes[path] = size
                    totalFiles += 1
                    itemCounts[path] = 1
                    storeCache(
                        path: path,
                        entry: CacheEntry(size: size, files: 1, folders: 0, itemCount: 1, modified: modDate)
                    )
                }
                continue
            }

            var sourceBytes: Int64 = 0
            var sourceItems = 0
            var sourceFiles = 0
            var sourceFolders = 0
            if let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let url as URL in enumerator {
                    if let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) {
                        if values.isDirectory == true {
                            totalFolders += 1
                            sourceFolders += 1
                        } else {
                            totalFiles += 1
                            sourceFiles += 1
                            sourceItems += 1
                            let size = Int64(values.fileSize ?? 0)
                            totalBytes += size
                            sourceBytes += size
                        }
                    }
                }
            }
            sizes[path] = sourceBytes
            itemCounts[path] = sourceItems
            storeCache(
                path: path,
                entry: CacheEntry(
                    size: sourceBytes,
                    files: sourceFiles,
                    folders: sourceFolders,
                    itemCount: sourceItems,
                    modified: modDate
                )
            )
        }

        return (totalBytes, totalFiles, totalFolders, sizes, itemCounts)
    }

    private static func cachedEntry(for path: String, modified: Date?) -> CacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = cache[path] else { return nil }
        guard entry.modified == modified else { return nil }
        return entry
    }

    private static func storeCache(path: String, entry: CacheEntry) {
        cacheLock.lock()
        cache[path] = entry
        cacheLock.unlock()
    }
}
