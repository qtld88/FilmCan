import Foundation

actor NetworkSpeedProbe {
    static let shared = NetworkSpeedProbe()

    struct CacheEntry: Codable {
        let mbps: Double
        let timestamp: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let cacheURL: URL
    private let ttl: TimeInterval = 24 * 60 * 60
    private let probeBytes = 50 * 1024 * 1024

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("FilmCan")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("drive-speeds.json")
        loadCache()
    }

    func probe(volumeRoot: String, volumeUUID: String) async -> Double? {
        if let entry = cache[volumeUUID], Date().timeIntervalSince(entry.timestamp) < ttl {
            return entry.mbps
        }
        let mbps = await runProbe(volumeRoot: volumeRoot)
        if let mbps {
            cache[volumeUUID] = CacheEntry(mbps: mbps, timestamp: Date())
            persistCache()
        }
        return mbps
    }

    private func runProbe(volumeRoot: String) async -> Double? {
        await Task.detached(priority: .utility) { [probeBytes] in
            let path = (volumeRoot as NSString).appendingPathComponent(".filmcan-speedprobe.tmp")
            let data = Data(count: probeBytes)
            let fm = FileManager.default
            guard fm.createFile(atPath: path, contents: nil) else { return nil }
            defer { try? fm.removeItem(atPath: path) }
            guard let handle = FileHandle(forWritingAtPath: path) else { return nil }
            defer { try? handle.close() }
            let start = Date()
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
            } catch {
                return nil
            }
            let elapsed = Date().timeIntervalSince(start)
            guard elapsed > 0 else { return nil }
            return Double(probeBytes) / elapsed / 1_000_000
        }.value
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else { return }
        cache = decoded
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: cacheURL)
    }
}
