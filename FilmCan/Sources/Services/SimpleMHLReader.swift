import Foundation

/// Parses the lightweight hidden hash list written by `SimpleMHLWriter`
/// (`<file name=".." mtime="..."><hash>HEX</hash></file>`), also the pre-1.3 legacy
/// format (no `mtime`). Attributes are read in any order; unknown ones are ignored.
/// The format carries no size, so `size` is reported as 0. A regex rather than
/// `XMLParser`: a legacy list (prefixed `<filmcan:partial>` with no namespace
/// declaration) or a list cut short by a crash must still yield its complete lines.
enum SimpleMHLReader {
    static func read(url: URL) throws -> [MHLEntry] {
        let data = try Data(contentsOf: url)
        return parse(data)
    }

    private static let fileRegex = try? NSRegularExpression(
        pattern: #"<file\s+([^>]*?)\s*>\s*<hash>([^<]*)</hash>\s*</file>"#)
    private static let attributeRegex = try? NSRegularExpression(
        pattern: #"([A-Za-z_][\w.-]*)\s*=\s*"([^"]*)""#)

    static func parse(_ data: Data) -> [MHLEntry] {
        guard let xml = String(data: data, encoding: .utf8),
              let fileRegex, let attributeRegex else { return [] }
        var out: [MHLEntry] = []
        let ns = xml as NSString
        fileRegex.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            let attrText = ns.substring(with: m.range(at: 1))
            let attrNS = attrText as NSString
            var attrs: [String: String] = [:]
            for a in attributeRegex.matches(in: attrText, range: NSRange(location: 0, length: attrNS.length)) {
                attrs[attrNS.substring(with: a.range(at: 1))] = unescape(attrNS.substring(with: a.range(at: 2)))
            }
            guard let name = attrs["name"] else { return }
            let hash = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(MHLEntry(relPath: name, size: 0, hash: hash,
                                mtime: attrs["mtime"].flatMap { Int64($0) }))
        }
        return out
    }

    private static func unescape(_ s: String) -> String {
        // `&amp;` last, so an escaped entity like `&amp;lt;` stays `&lt;`.
        s.replacingOccurrences(of: "&lt;", with: "<")
         .replacingOccurrences(of: "&gt;", with: ">")
         .replacingOccurrences(of: "&quot;", with: "\"")
         .replacingOccurrences(of: "&apos;", with: "'")
         .replacingOccurrences(of: "&amp;", with: "&")
    }
}
