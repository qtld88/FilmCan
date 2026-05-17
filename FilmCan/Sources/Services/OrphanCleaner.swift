import Foundation

actor OrphanCleaner {
    static let shared = OrphanCleaner()
    private let fm = FileManager.default

    func cleanOrphans(at directories: [URL]) async {
        for dir in directories {
            await cleanDir(dir)
        }
    }

    private func cleanDir(_ dir: URL) async {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        while let fileURL = enumerator.nextObject() as? URL {
            if fileURL.lastPathComponent.hasPrefix(".filmcan-") {
                try? fm.removeItem(at: fileURL)
            }
        }
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
