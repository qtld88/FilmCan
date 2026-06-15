import Foundation

/// Writes a spec-faithful ASC MHL v2.0 manifest (single sealed generation) for one
/// roll. Replaces the legacy MHLWriter. Lifecycle mirrors it so call sites barely
/// change: init / seed / append / flush / seal / finalizeAsPartial / cancel.
actor ASCMHLWriter {
    struct Entry { let relPath: String; let size: Int64; let hash: String }

    private let url: URL
    private let rollName: String
    private var entries: [Entry] = []
    private var finalized = false
    private let creationDate: String

    init(url: URL, rollName: String) throws {
        self.url = url
        self.rollName = rollName
        self.creationDate = Self.iso8601(Date())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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

    func seal() async throws {
        guard !finalized else { return }
        try render()
        finalized = true
    }

    func finalizeAsPartial(reason: String) async throws {
        guard !finalized else { return }
        try render(partialReason: reason)
        finalized = true
    }

    func cancel() {
        finalized = true
        entries.removeAll()
        try? FileManager.default.removeItem(at: url)
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
        try xml.write(to: url, atomically: true, encoding: .utf8)
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
}
