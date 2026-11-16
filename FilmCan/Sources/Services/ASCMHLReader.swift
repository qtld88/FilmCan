import Foundation

/// Parses an ASC MHL v2.0 manifest. Returns one entry per <hash> (file hashes only;
/// <directoryhash> blocks are skipped). Replaces the legacy MHLReader.
enum ASCMHLReader {
    struct Entry: Equatable {
        let relPath: String
        let size: Int64?
        let hash: String   // value of the file's hash element (xxh128/xxh64/md5/…)
        let mtime: Int64?
        /// Name of the hash element the value came from ("xxh128", "md5", …).
        var algorithm: String? = nil
        /// `hashdate` / `action` attributes of that hash element, as written.
        var hashDate: String? = nil
        var action: String? = nil

        /// The entry as a writer seed: carried, keeping its algorithm, date and action.
        var carried: MHLEntry {
            MHLEntry(relPath: relPath, size: size ?? 0, hash: hash, mtime: mtime,
                     algorithm: algorithm ?? MHLEntry.xxh128, hashDate: hashDate,
                     action: action, isCarried: true)
        }
    }

    /// `lastmodificationdate` is an `xs:dateTime` in ASC MHL v2.0. FilmCan wrote an
    /// integer epoch before 1.3.x, so both forms are read (to the second).
    static func parseModificationDate(_ raw: String) -> Int64? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let epoch = Int64(s) { return epoch }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return Int64(d.timeIntervalSince1970.rounded(.down)) }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return Int64(d.timeIntervalSince1970.rounded(.down)) }
        // xs:dateTime allows no time zone: read it as UTC.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss.SSS"] {
            local.dateFormat = format
            if let d = local.date(from: s) { return Int64(d.timeIntervalSince1970.rounded(.down)) }
        }
        return nil
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
    /// Every hash element of the current <hash> block, in order.
    private var curHashes: [(algorithm: String, value: String, hashDate: String?, action: String?)] = []
    private var curHashAttrs: [String: String] = [:]
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
            curPath = nil; curSize = nil; curMtime = nil; curHashes = []
        case "path" where inHash:
            curSize = attrs["size"].flatMap { Int64($0) }
            curMtime = attrs["lastmodificationdate"].flatMap(ASCMHLReader.parseModificationDate)
        case let h where ASCMHLParser.hashElements.contains(h) && inHash:
            capturingHashValue = true
            curHashAttrs = attrs
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
            curHashes.append((name, charBuf.trimmingCharacters(in: .whitespacesAndNewlines),
                              curHashAttrs["hashdate"], curHashAttrs["action"]))
            capturingHashValue = false
        case "hash":
            // A block may list several algorithms: xxh128 (what FilmCan checks) wins,
            // otherwise the first one listed is kept, with its own name.
            let pick = curHashes.first { $0.algorithm == MHLEntry.xxh128 } ?? curHashes.first
            if let path = curPath, let pick {
                entries.append(.init(relPath: path, size: curSize, hash: pick.value, mtime: curMtime,
                                     algorithm: pick.algorithm, hashDate: pick.hashDate,
                                     action: pick.action))
            }
            inHash = false
        default:
            break
        }
    }
}
