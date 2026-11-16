import AppKit

/// "Choose a Folder…" on a source/destination row: swap the auto-detected drive
/// root (or any path) for a folder deeper on the drive.
enum FolderPick {
    /// Opens a folder picker that starts at `path`. Returns nil on cancel or same path.
    @MainActor
    static func chooseFolder(startingAt path: String, message: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: path, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let picked = url.standardizedFileURL.path
        return picked == path ? nil : picked
    }

    /// Replaces `old` by `new` at the same position; drops `old` when `new` is already listed.
    static func replacing(_ old: String, with new: String, in paths: [String]) -> [String] {
        guard let index = paths.firstIndex(of: old) else { return paths }
        var updated = paths
        if paths.contains(new) {
            updated.remove(at: index)
        } else {
            updated[index] = new
        }
        return updated
    }

    /// True when the user already picked a folder inside `root`, so auto-detection
    /// must not add `root` back next to it.
    static func hasDeeperPick(under root: String, in paths: [String]) -> Bool {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return paths.contains { $0.hasPrefix(prefix) }
    }
}
