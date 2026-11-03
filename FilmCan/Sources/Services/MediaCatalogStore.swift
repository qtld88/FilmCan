import Foundation

@MainActor
final class MediaCatalogStore: ObservableObject {
    static let shared = MediaCatalogStore()
    @Published private(set) var rolls: [CatalogRoll] = []
    private let fileURL: URL

    /// Default: ~/Library/Application Support/FilmCan/catalog.json (same folder as
    /// `ConfigurationStorage`). Tests pass a temp URL.
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let folder = appSupport.appendingPathComponent("FilmCan", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.fileURL = folder.appendingPathComponent("catalog.json")
        }
        load()
    }

    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            rolls = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            rolls = try decoder.decode([CatalogRoll].self, from: data)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("catalog.json.corrupt-\(stamp)")
            try? fm.moveItem(at: fileURL, to: quarantine)
            DebugLog.warn("Catalog unreadable, quarantined to \(quarantine.lastPathComponent): \(error)")
            rolls = []
        }
    }

    func save() {
        let fm = FileManager.default
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(rolls)
            if fm.fileExists(atPath: fileURL.path) {
                let bak = fileURL.appendingPathExtension("bak")
                try? fm.removeItem(at: bak)
                try? fm.copyItem(at: fileURL, to: bak)
            }
            try data.write(to: fileURL, options: .atomic)
        } catch {
            DebugLog.warn("Catalog save failed: \(error)")
        }
    }

    func forget(rollId: UUID) {
        rolls.removeAll { $0.id == rollId }
        save()
    }

    /// Replace the in-memory catalog and persist (used by tests and by `record`).
    func merge(_ roll: CatalogRoll) {
        rolls = MediaCatalog.merge(roll, into: rolls)
    }

    /// Record a finished run. Called once per run with the exploded per-destination results.
    func record(config: BackupConfiguration, sources: [String],
                results: [TransferResult], runDate: Date) async {
        // sourcePath -> (copies, first successful roll folder)
        var copiesBySource: [String: [CatalogCopy]] = [:]
        var firstFolderBySource: [String: String] = [:]
        var order: [String] = []

        for result in results {
            guard let dr = result.destinationResults.first else { continue }
            for (sourcePath, rollFolder) in dr.rollFolders {
                let info = Self.volumeInfo(for: rollFolder)
                let copy = CatalogCopy(
                    destVolumeUUID: info.uuid,
                    destVolumeName: info.name ?? dr.displayName,
                    rollFolderPath: rollFolder,
                    verified: result.success && result.wasVerified,
                    date: runDate
                )
                if copiesBySource[sourcePath] == nil { order.append(sourcePath) }
                copiesBySource[sourcePath, default: []].append(copy)
                if firstFolderBySource[sourcePath] == nil, result.success {
                    firstFolderBySource[sourcePath] = rollFolder
                }
            }
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let fallbackDay = dayFormatter.string(from: runDate)

        for sourcePath in order {
            guard let copies = copiesBySource[sourcePath], let first = copies.first else { continue }
            let listFolder = firstFolderBySource[sourcePath] ?? first.rollFolderPath
            let files = await Task.detached(priority: .utility) {
                Self.listFiles(inRollFolder: listFolder)
            }.value
            let standardized = (sourcePath as NSString).standardizingPath
            let roll = CatalogRoll(
                configId: config.id,
                projectName: config.name,
                shootDay: config.day.isEmpty ? fallbackDay : config.day,
                rollName: (listFolder as NSString).lastPathComponent,
                mediaKind: config.sourceMediaKinds[sourcePath] ?? .camera,
                sourceVolumeUUID: Self.volumeInfo(for: standardized).uuid,
                sourcePath: standardized,
                firstBackedUp: runDate,
                files: files,
                copies: copies
            )
            rolls = MediaCatalog.merge(roll, into: rolls)
        }
        if !order.isEmpty { save() }
    }

    /// Currently mounted volume UUIDs.
    func mountedVolumeUUIDs() -> Set<String> {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeUUIDStringKey], options: []) ?? []
        var set = Set<String>()
        for url in urls {
            if let uuid = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString {
                set.insert(uuid)
            }
        }
        return set
    }

    nonisolated static func volumeInfo(for path: String) -> (uuid: String?, name: String?) {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeNameKey])
        return (values?.volumeUUIDString, values?.volumeName)
    }

    nonisolated static func listFiles(inRollFolder folder: String) -> [CatalogFile] {
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: []) else { return [] }
        let rootPath = root.standardizedFileURL.path
        var files: [CatalogFile] = []
        for case let url as URL in enumerator {
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(rootPath + "/") else { continue }
            let rel = String(full.dropFirst(rootPath.count + 1))
            let comps = rel.split(separator: "/")
            if comps.first == "ascmhl" {
                if comps.count == 1 { enumerator.skipDescendants() }
                continue
            }
            if HistoryRecorder.isHiddenPath("/" + rel) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true { continue }
            files.append(CatalogFile(relPath: rel, size: Int64(values?.fileSize ?? 0)))
        }
        return files.sorted { $0.relPath < $1.relPath }
    }
}
