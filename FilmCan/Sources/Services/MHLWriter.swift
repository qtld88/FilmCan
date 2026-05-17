import Foundation

actor MHLWriter {
    private let url: URL
    private let sourceName: String
    private var entries: [(hash: String, fileName: String)] = []
    private var finalized = false

    init(url: URL, sourceName: String) throws {
        self.url = url
        self.sourceName = sourceName
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func append(hash: String, fileName: String) async throws {
        guard !finalized else { return }
        entries.append((hash, fileName))
        if entries.count % Constants.mhlFlushEveryFiles == 0 {
            try writeAllEntries()
        }
    }

    func flush() throws {
        try writeAllEntries()
    }

    func seal() async throws {
        guard !finalized else { return }
        try writeAllEntries(extraTrailer: "\n  <sealed/>")
        finalized = true
    }

    func finalizeAsPartial(reason: String) async throws {
        guard !finalized else { return }
        try writeAllEntries(extraTrailer: "\n  <filmcan:partial reason=\"\(escaped(reason))\"/>")
        finalized = true
    }

    func cancel() {
        finalized = true
        entries.removeAll()
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func writeAllEntries(extraTrailer: String = "") throws {
        var xml = header()
        for entry in entries {
            xml += entryXml(hash: entry.hash, fileName: entry.fileName)
        }
        xml += extraTrailer
        xml += trailer()
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    private func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }

    private func header() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<hashlist version=\"1.0\" source=\"\(escaped(sourceName))\" xmlns:filmcan=\"https://filmcan.app/mhl\">"
    }

    private func trailer() -> String {
        "\n</hashlist>"
    }

    private func entryXml(hash: String, fileName: String) -> String {
        "\n  <file name=\"\(escaped(fileName))\"><hash>\(hash)</hash></file>"
    }
}
