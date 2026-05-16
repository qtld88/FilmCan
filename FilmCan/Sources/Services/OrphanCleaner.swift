import Foundation

actor OrphanCleaner {
    static let shared = OrphanCleaner()
    private let fm = FileManager.default
    private let timeout: TimeInterval = 24 * 60 * 60

    func scheduleCleanup(for urls: [URL]) async {
        for url in urls { await reap(url) }
    }

    private func reap(_ url: URL) async {
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            let attrs = try fm.attributesOfItem(atPath: url.path)
            if let modDate = attrs[.modificationDate] as? Date,
               Date().timeIntervalSince(modDate) > timeout {
                try fm.removeItem(at: url)
            }
        } catch { /* best-effort */ }
    }

    func cleanPartialFiles(in dir: URL, except: Set<String>) async {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        while let fileURL = enumerator.nextObject() as? URL {
            guard fileURL.lastPathComponent.hasPrefix(".filmcan-"),
                  !except.contains(fileURL.lastPathComponent) else { continue }
            try? fm.removeItem(at: fileURL)
        }
    }
}
