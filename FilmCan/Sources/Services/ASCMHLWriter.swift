import Foundation

/// Writes a spec-faithful ASC MHL v2.0 manifest as a new generation in a roll's
/// `ascmhl/` folder, and records that generation (with its C4 hash) in the
/// `ascmhl_chain.xml` index. Each backup run creates a new generation
/// (`NNNN_<roll>_<date>Z.mhl`); the chain ties them into a chain of custody the
/// ASC MHL tooling requires.
actor ASCMHLWriter {
    struct Entry { let relPath: String; let size: Int64; let hash: String }

    private let ascmhlDir: URL
    private let rollName: String
    /// Generation number (1-based), determined from the existing chain at init.
    nonisolated let sequence: Int
    nonisolated let manifestFileName: String
    /// Absolute path of this generation's manifest (for DestResult.mhlPath).
    nonisolated let manifestPath: String
    private let manifestURL: URL
    private var entries: [Entry] = []
    private var finalized = false
    private let creationDate: String

    init(ascmhlDir: URL, rollName: String) throws {
        self.ascmhlDir = ascmhlDir
        self.rollName = rollName
        try FileManager.default.createDirectory(at: ascmhlDir, withIntermediateDirectories: true)
        let seq = ASCMHLChain.nextSequence(ascmhlDir: ascmhlDir)
        self.sequence = seq
        let now = Date()
        self.creationDate = Self.iso8601(now)
        let name = String(format: "%04d_%@_%@.mhl", seq, rollName, Self.fileStamp(now))
        self.manifestFileName = name
        let url = ascmhlDir.appendingPathComponent(name)
        self.manifestURL = url
        self.manifestPath = url.path
    }

    func seed(_ existing: [Entry]) {
        guard !finalized, !existing.isEmpty else { return }
        let known = Set(entries.map { $0.relPath })
        entries = existing.filter { !known.contains($0.relPath) } + entries
    }

    func append(relPath: String, size: Int64, hash: String) async throws {
        guard !finalized else { return }
        entries.append(Entry(relPath: relPath, size: size, hash: hash))
        if entries.count % Constants.mhlFlushEveryFiles == 0 { try render() }
    }

    func flush() throws { try render() }

    /// Finalize this generation: write the manifest and record it (with its C4) in
    /// the chain index.
    func seal() async throws {
        guard !finalized else { return }
        try render()
        let data = try Data(contentsOf: manifestURL)
        try ASCMHLChain.append(ascmhlDir: ascmhlDir, sequence: sequence,
                               manifestFileName: manifestFileName, manifestData: data)
        finalized = true
    }

    /// A partial generation writes its manifest but is NOT added to the chain, so
    /// resume falls back to the last complete generation.
    func finalizeAsPartial(reason: String) async throws {
        guard !finalized else { return }
        try render(partialReason: reason)
        finalized = true
    }

    func cancel() {
        finalized = true
        entries.removeAll()
        try? FileManager.default.removeItem(at: manifestURL)
    }

    // MARK: - Rendering

    private func render(partialReason: String? = nil) throws {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let host = Host.current().localizedName ?? "unknown"
        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">"# + "\n"
        xml += "  <creatorinfo>\n"
        xml += "    <creationdate>\(creationDate)</creationdate>\n"
        xml += "    <hostname>\(Self.esc(host))</hostname>\n"
        xml += "    <tool version=\"\(Self.esc(appVersion))\">FilmCan</tool>\n"
        xml += "  </creatorinfo>\n"
        xml += "  <processinfo>\n"
        xml += "    <process>in-place</process>\n"
        if let reason = partialReason {
            xml += "    <!-- filmcan:partial reason=\"\(Self.esc(reason))\" -->\n"
        }
        xml += "    <ignore>\n      <pattern>.DS_Store</pattern>\n      <pattern>ascmhl</pattern>\n    </ignore>\n"
        xml += "  </processinfo>\n"
        xml += "  <hashes>\n"
        for e in entries {
            xml += "    <hash>\n"
            xml += "      <path size=\"\(e.size)\">\(Self.esc(e.relPath))</path>\n"
            xml += "      <xxh128 action=\"original\" hashdate=\"\(creationDate)\">\(e.hash)</xxh128>\n"
            xml += "    </hash>\n"
        }
        xml += "  </hashes>\n"
        xml += "</hashlist>\n"
        try xml.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func iso8601(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.string(from: date).replacingOccurrences(of: "Z", with: "+00:00")
    }

    /// Filename timestamp like the reference tool: `2026-06-15_120000Z` (UTC).
    private static func fileStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date) + "Z"
    }
}
