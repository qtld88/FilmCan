import Foundation

/// Reads and writes the ASC MHL chain index (`ascmhl_chain.xml`) — the file that
/// records each manifest generation and the C4 hash of that manifest, forming the
/// chain of custody the ASC MHL tooling requires.
enum ASCMHLChain {
    struct Ref: Equatable { let seq: Int; let path: String; let c4: String }

    static func chainURL(ascmhlDir: URL) -> URL {
        ascmhlDir.appendingPathComponent("ascmhl_chain.xml")
    }

    static func read(ascmhlDir: URL) -> [Ref] {
        let url = chainURL(ascmhlDir: ascmhlDir)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let parser = ChainParser()
        guard parser.parse(data: data) else { return [] }
        return parser.refs.sorted { $0.seq < $1.seq }
    }

    static func nextSequence(ascmhlDir: URL) -> Int {
        // Consider both sealed (chain) and on-disk generations, so a partial
        // generation written on cancel still advances the next sequence number.
        let chainMax = read(ascmhlDir: ascmhlDir).map { $0.seq }.max() ?? 0
        let diskMax = manifestFilesOnDisk(ascmhlDir: ascmhlDir).map { $0.seq }.max() ?? 0
        return max(chainMax, diskMax) + 1
    }

    /// The latest SEALED generation recorded in the chain (delivery view).
    static func latestManifestPath(ascmhlDir: URL) -> String? {
        read(ascmhlDir: ascmhlDir).max(by: { $0.seq < $1.seq })?.path
    }

    /// All generation manifests physically present (sealed or partial), with the
    /// leading NNNN sequence parsed from the filename.
    static func manifestFilesOnDisk(ascmhlDir: URL) -> [(seq: Int, url: URL)] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: ascmhlDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return items.compactMap { url in
            guard url.pathExtension == "mhl",
                  let underscore = url.lastPathComponent.firstIndex(of: "_"),
                  let seq = Int(url.lastPathComponent[..<underscore]) else { return nil }
            return (seq, url)
        }
    }

    /// The latest generation manifest ON DISK (sealed OR partial) — used for resume,
    /// which must see a partial generation a cancelled run left behind. Ties on
    /// sequence break by modification date (newest wins).
    static func latestManifestFileName(ascmhlDir: URL) -> String? {
        let files = manifestFilesOnDisk(ascmhlDir: ascmhlDir)
        guard !files.isEmpty else { return nil }
        func mtime(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return files.sorted {
            $0.seq != $1.seq ? $0.seq < $1.seq : mtime($0.url) < mtime($1.url)
        }.last?.url.lastPathComponent
    }

    /// Append (or replace) the generation `sequence` with the C4 of `manifestData`,
    /// preserving all other generations, and rewrite the chain file.
    static func append(ascmhlDir: URL, sequence: Int, manifestFileName: String,
                       manifestData: Data) throws {
        try FileManager.default.createDirectory(at: ascmhlDir, withIntermediateDirectories: true)
        let c4 = C4Hash.id(of: manifestData)
        var refs = read(ascmhlDir: ascmhlDir).filter { $0.seq != sequence }
        refs.append(Ref(seq: sequence, path: manifestFileName, c4: c4))
        refs.sort { $0.seq < $1.seq }

        var xml = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        xml += #"<ascmhldirectory xmlns="urn:ASC:MHL:DIRECTORY:v2.0">"# + "\n"
        for r in refs {
            xml += "  <hashlist sequencenr=\"\(r.seq)\">\n"
            xml += "    <path>\(esc(r.path))</path>\n"
            xml += "    <c4>\(r.c4)</c4>\n"
            xml += "  </hashlist>\n"
        }
        xml += "</ascmhldirectory>\n"
        try xml.write(to: chainURL(ascmhlDir: ascmhlDir), atomically: true, encoding: .utf8)
    }

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}

private final class ChainParser: NSObject, XMLParserDelegate {
    var refs: [ASCMHLChain.Ref] = []
    private var curSeq: Int?
    private var curPath: String?
    private var curC4: String?
    private var buf = ""

    func parse(data: Data) -> Bool {
        let p = XMLParser(data: data); p.delegate = self; return p.parse()
    }
    func parser(_ p: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName q: String?, attributes a: [String: String] = [:]) {
        buf = ""
        if name == "hashlist" { curSeq = a["sequencenr"].flatMap { Int($0) }; curPath = nil; curC4 = nil }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { buf += s }
    func parser(_ p: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName q: String?) {
        switch name {
        case "path": curPath = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        case "c4": curC4 = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        case "hashlist":
            if let s = curSeq, let pth = curPath, let c = curC4 {
                refs.append(.init(seq: s, path: pth, c4: c))
            }
        default: break
        }
    }
}
