import Foundation

/// Lightweight hidden hash list at `<dest>/.filmcan/hashlists/<roll>.mhl` — no chain,
/// no generations. For users who don't need a Netflix/ASC delivery-grade manifest.
/// The format matches the legacy reader (`<file name="..."><hash>HEX</hash></file>`),
/// so resume-skip still works via `FanOutCopier.loadExistingMHLEntries`.
actor SimpleMHLWriter: MHLWriting {
    nonisolated let manifestPath: String

    private let dirURL: URL
    private let fileURL: URL
    private var entries: [MHLEntry] = []
    private var finalized = false

    init(destRoot: String, rollName: String) throws {
        // Directory is created lazily in render(), so a roll with nothing copied
        // this run leaves no hidden hash-list folder behind.
        let dir = URL(fileURLWithPath: destRoot)
            .appendingPathComponent(".filmcan").appendingPathComponent("hashlists")
        let url = dir.appendingPathComponent("\(rollName).mhl")
        self.dirURL = dir
        self.fileURL = url
        self.manifestPath = url.path
    }

    func seed(_ existing: [MHLEntry]) {
        guard !finalized, !existing.isEmpty else { return }
        let known = Set(entries.map { $0.relPath })
        entries = existing.filter { !known.contains($0.relPath) } + entries
    }

    func append(relPath: String, size: Int64, hash: String) async throws {
        guard !finalized else { return }
        entries.append(MHLEntry(relPath: relPath, size: size, hash: hash))
        if entries.count % Constants.mhlFlushEveryFiles == 0 { try render() }
    }

    func flush() throws { try render() }

    func seal() async throws {
        guard !finalized else { return }
        guard !entries.isEmpty else { finalized = true; return }
        try render()
        finalized = true
    }

    /// A simple hash list has no chain, so a partial run just leaves what it wrote.
    func finalizeAsPartial(reason: String) async throws {
        guard !finalized else { return }
        guard !entries.isEmpty else { finalized = true; return }
        try render()
        finalized = true
    }

    func cancel() {
        finalized = true
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func render() throws {
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n<hashlist>\n"
        for e in entries {
            xml += "<file name=\"\(Self.esc(e.relPath))\"><hash>\(e.hash)</hash></file>\n"
        }
        xml += "</hashlist>\n"
        try xml.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
