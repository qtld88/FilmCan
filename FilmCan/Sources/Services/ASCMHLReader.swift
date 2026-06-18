import Foundation

/// Parses an ASC MHL v2.0 manifest. Returns one entry per <hash> (file hashes only;
/// <directoryhash> blocks are skipped). Replaces the legacy MHLReader.
enum ASCMHLReader {
    struct Entry: Equatable {
        let relPath: String
        let size: Int64?
        let hash: String   // value of the file's hash element (xxh128/xxh64/md5/…)
        let mtime: Int64?
    }

    static func read(url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        let parser = ASCMHLParser()
        try parser.parse(data: data)
        return parser.entries
    }
}

private final class ASCMHLParser: NSObject, XMLParserDelegate {
    var entries: [ASCMHLReader.Entry] = []

    private var inHash = false
    private var curPath: String?
    private var curSize: Int64?
    private var curMtime: Int64?
    private var curHash: String?
    private var charBuf = ""
    private var capturingHashValue = false

    private static let hashElements: Set<String> = ["xxh128", "xxh3", "xxh64", "xxh32", "md5", "sha1", "c4"]

    func parse(data: Data) throws {
        let p = XMLParser(data: data)
        p.delegate = self
        guard p.parse() else { throw Err.unknown }
    }
    enum Err: Error { case unknown }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName q: String?, attributes attrs: [String: String] = [:]) {
        charBuf = ""
        switch name {
        case "hash":
            inHash = true
            curPath = nil; curSize = nil; curMtime = nil; curHash = nil
        case "path" where inHash:
            curSize = attrs["size"].flatMap { Int64($0) }
            curMtime = attrs["lastmodificationdate"].flatMap { Int64($0) }
        case let h where ASCMHLParser.hashElements.contains(h) && inHash:
            capturingHashValue = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { charBuf += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName q: String?) {
        switch name {
        case "path" where inHash:
            curPath = charBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        case let h where ASCMHLParser.hashElements.contains(h) && capturingHashValue:
            curHash = charBuf.trimmingCharacters(in: .whitespacesAndNewlines)
            capturingHashValue = false
        case "hash":
            if let path = curPath, let hash = curHash {
                entries.append(.init(relPath: path, size: curSize, hash: hash, mtime: curMtime))
            }
            inHash = false
        default:
            break
        }
    }
}
