import Foundation

/// "Try with made-up cards": a demo movie whose cards and drives are folders on this
/// Mac. The copy is a real one (same engine, same verification); only the media is
/// made up. Everything the demo creates is tied to the demo movie and is removed by
/// `stop`: its folders, the movie, its history, its catalog rolls, its roll names.
/// Real movies are never touched.
enum DemoSession {
    static let defaultsKey = "demoConfigId"
    static let movieName = "Demo"
    static let cameraClipCount = 5
    static let soundClipCount = 3
    /// Large enough for the copy to be watched, small enough to be created at once.
    static let defaultClipBytes = 12 * 1024 * 1024

    struct Layout: Equatable {
        let root: URL
        var cameraCard: URL { root.appendingPathComponent("Demo card A001") }
        var soundCard: URL { root.appendingPathComponent("Demo sound S001") }
        var drives: [URL] {
            [root.appendingPathComponent("Demo drive 1"), root.appendingPathComponent("Demo drive 2")]
        }
    }

    static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("FilmCan", isDirectory: true)
            .appendingPathComponent("Demo", isDirectory: true)
    }

    // MARK: - Which movie is the demo

    static func demoConfigId(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: defaultsKey).flatMap(UUID.init(uuidString:))
    }

    static func isDemo(_ configId: UUID?, defaults: UserDefaults = .standard) -> Bool {
        guard let configId, let demo = demoConfigId(defaults: defaults) else { return false }
        return configId == demo
    }

    /// The demo movie exists (a demo whose movie was deleted by hand is not running).
    @MainActor
    static func isRunning(storage: ConfigurationStorage, defaults: UserDefaults = .standard) -> Bool {
        guard let id = demoConfigId(defaults: defaults) else { return false }
        return storage.configurations.contains { $0.id == id }
    }

    // MARK: - Made-up media

    /// Two made-up cards (random bytes under camera and sound file names) and two
    /// empty drives. The clips are not playable: they are there to be copied.
    static func createFiles(layout: Layout, clipBytes: Int = defaultClipBytes,
                            fileManager fm: FileManager = .default) throws {
        for folder in [layout.cameraCard, layout.soundCard] + layout.drives {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        for index in 1...cameraClipCount {
            let name = String(format: "A001C%03d_DEMO.mov", index)
            try randomData(count: clipBytes).write(to: layout.cameraCard.appendingPathComponent(name))
        }
        for index in 1...soundClipCount {
            let name = String(format: "S001T%02d_DEMO.wav", index)
            try randomData(count: max(1, clipBytes / 6)).write(to: layout.soundCard.appendingPathComponent(name))
        }
    }

    private static func randomData(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            let words = raw.bindMemory(to: UInt64.self)
            for index in words.indices { words[index] = generator.next() }
        }
        return data
    }

    static func makeConfiguration(layout: Layout) -> BackupConfiguration {
        var config = BackupConfiguration.empty
        config.name = movieName
        config.sourcePaths = [layout.cameraCard.path, layout.soundCard.path]
        config.sourceMediaKinds = [layout.soundCard.path: .sound]
        config.destinationPaths = layout.drives.map(\.path)
        // The full check: every file is read back from both sides, as on a real shoot.
        config.engineOptions.verificationMode = .paranoid
        return config
    }

    /// Phone and webhook messages stay off for the demo: nobody else should hear of it.
    static func muted(_ settings: NotificationSettings) -> NotificationSettings {
        var out = settings
        out.ntfyEnabled = false
        out.webhookEnabled = false
        return out
    }

    // MARK: - Start / stop

    /// Creates the made-up media and the demo movie, and returns the movie. A previous
    /// demo left behind is removed first.
    @MainActor
    static func start(storage: ConfigurationStorage, catalog: MediaCatalogStore,
                      rollStore: RollNumberingStore, root: URL = defaultRoot(),
                      clipBytes: Int = defaultClipBytes,
                      defaults: UserDefaults = .standard) throws -> BackupConfiguration {
        stop(storage: storage, catalog: catalog, rollStore: rollStore, root: root, defaults: defaults)
        let layout = Layout(root: root)
        do {
            try createFiles(layout: layout, clipBytes: clipBytes)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
        let config = makeConfiguration(layout: layout)
        defaults.set(config.id.uuidString, forKey: defaultsKey)
        storage.add(config)
        return config
    }

    /// Removes everything the demo made. Safe to call when no demo is running.
    @MainActor
    static func stop(storage: ConfigurationStorage, catalog: MediaCatalogStore,
                     rollStore: RollNumberingStore, root: URL = defaultRoot(),
                     defaults: UserDefaults = .standard) {
        if let id = demoConfigId(defaults: defaults) {
            let runs = storage.transferHistory.filter { $0.configId == id }.count
            if runs > 0 {
                storage.clearHistory(for: id)
                // Demo runs do not count as backups made with FilmCan.
                storage.totalTransferCount = max(0, storage.totalTransferCount - runs)
            }
            catalog.forget(configId: id)
            if rollStore.state(for: id) != RollNumberingStore.ConfigState() {
                rollStore.update(RollNumberingStore.ConfigState(), for: id)
            }
            if let config = storage.configurations.first(where: { $0.id == id }) {
                storage.delete(config)
            }
            defaults.removeObject(forKey: defaultsKey)
        }
        if FileManager.default.fileExists(atPath: root.path) {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
