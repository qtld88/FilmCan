import Foundation

actor OrphanCleaner {
    static let shared = OrphanCleaner()
    private let fm = FileManager.default
    private var activeTempNames: Set<String> = []

    func registerActive(_ name: String) { activeTempNames.insert(name) }
    func unregisterActive(_ name: String) { activeTempNames.remove(name) }

    /// Remove crash-leftover `.filmcan-*` temp files, scoped to the work this job
    /// touches: a recursive sweep of each roll folder (where copy writes its temps)
    /// plus a shallow sweep of each dest root (catches root-level probes). Scoping
    /// avoids a full recursive walk of the whole destination volume — on an SSD that
    /// already holds prior backups that walk was the bulk of the "Preparing" delay.
    func cleanOrphans(rollFolders: [URL], destRoots: [URL]) async {
        for dir in rollFolders {
            await cleanRecursive(dir)
        }
        for root in destRoots {
            cleanShallow(root)
        }
    }

    private func cleanRecursive(_ dir: URL) async {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        while let fileURL = enumerator.nextObject() as? URL {
            removeIfOrphan(fileURL)
        }
    }

    private func cleanShallow(_ dir: URL) {
        guard let items = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: []) else { return }
        for fileURL in items {
            removeIfOrphan(fileURL)
        }
    }

    private func removeIfOrphan(_ fileURL: URL) {
        let name = fileURL.lastPathComponent
        if name.hasPrefix(".filmcan-"), !activeTempNames.contains(name) {
            try? fm.removeItem(at: fileURL)
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
