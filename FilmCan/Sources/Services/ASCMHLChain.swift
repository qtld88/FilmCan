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
        (read(ascmhlDir: ascmhlDir).map { $0.seq }.max() ?? 0) + 1
    }

    static func latestManifestPath(ascmhlDir: URL) -> String? {
        read(ascmhlDir: ascmhlDir).max(by: { $0.seq < $1.seq })?.path
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
