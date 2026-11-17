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
            rolls = MediaCatalog.mergingSameCards(
                Self.groupingLegacyQuickCopy(try decoder.decode([CatalogRoll].self, from: data)))
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let quarantine = fileURL.deletingLastPathComponent()
                .appendingPathComponent("catalog.json.corrupt-\(stamp)")
            try? fm.moveItem(at: fileURL, to: quarantine)
            DebugLog.warn("Catalog unreadable, quarantined to \(quarantine.lastPathComponent): \(error)")
            rolls = []
        }
    }

    /// Quick Copy used to file each run as its own project ("Quick Copy — <folder>");
    /// the typed project was not recorded, so those rolls fold into one "Quick Copy".
    nonisolated static func groupingLegacyQuickCopy(_ rolls: [CatalogRoll]) -> [CatalogRoll] {
        rolls.map { roll in
            guard roll.projectName.hasPrefix("Quick Copy — ") else { return roll }
            var grouped = roll
            grouped.projectName = "Quick Copy"
            return grouped
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

    /// Removes every roll recorded for one movie (used when the demo is stopped).
    func forget(configId: UUID) {
        guard rolls.contains(where: { $0.configId == configId }) else { return }
        rolls.removeAll { $0.configId == configId }
        save()
    }

    /// Replace the in-memory catalog and persist (used by tests and by `record`).
    func merge(_ roll: CatalogRoll) {
        rolls = MediaCatalog.merge(roll, into: rolls)
    }

    /// Record a finished run. Called once per run with the exploded per-destination results.
    /// `plan` is what the engine planned: a copy is marked verified only when its
    /// destination holds a hash-compared copy of every planned file of that source.
    /// `mediaKinds` are the run's effective Camera/Sound tags (including the Sound
    /// auto-detect); without them the config's explicit tags are used.
    func record(config: BackupConfiguration, sources: [String],
                results: [TransferResult], runDate: Date,
                plan: RunPlan? = nil, mediaKinds: [String: SourceMediaKind]? = nil) async {
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
                    verified: result.success && dr.success
                        && Self.isProven(dr, sourcePath: sourcePath, plan: plan),
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
            let clipKeys = await Task.detached(priority: .utility) {
                CardFingerprint.keys(forSource: standardized)
            }.value
            var roll = CatalogRoll(
                configId: config.id,
                projectName: config.name,
                shootDay: config.day.isEmpty ? fallbackDay : config.day,
                rollName: (listFolder as NSString).lastPathComponent,
                mediaKind: (mediaKinds ?? config.sourceMediaKinds)[sourcePath] ?? .camera,
                sourceVolumeUUID: Self.volumeInfo(for: standardized).uuid,
                sourcePath: standardized,
                firstBackedUp: runDate,
                files: files,
                copies: copies
            )
            roll.clipKeys = clipKeys.isEmpty ? nil : clipKeys
            rolls = MediaCatalog.merge(roll, into: rolls)
        }
        if !order.isEmpty { save() }
    }

    /// True when `dr` holds a hash-compared copy of every planned file of `sourcePath`.
    nonisolated static func isProven(_ dr: DestResult, sourcePath: String, plan: RunPlan?) -> Bool {
        guard let plan else { return false }
        let needed = Set(plan.files(inRoot: sourcePath).map(\.sourcePath))
        return !needed.isEmpty && needed.isSubset(of: dr.verifiedSourcePaths)
    }

    /// Earlier copies of a card, found by its clips (not its name). The clip keys come
    /// from `CardFingerprint.keys(forSources:)`, read off the main thread.
    func earlierCopies(ofClipKeys clipKeys: [String], mediaKind: SourceMediaKind) -> [CatalogEarlierCopy] {
        MediaCatalog.earlierCopies(ofClipKeys: clipKeys, mediaKind: mediaKind, in: rolls)
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
