import Foundation

/// Parses the lightweight hidden hash list written by `SimpleMHLWriter`
/// (`<file name=".."><hash>HEX</hash></file>`), also the pre-1.3 legacy format.
/// The format carries no size, so `size` is reported as 0.
enum SimpleMHLReader {
    static func read(url: URL) throws -> [MHLEntry] {
        let data = try Data(contentsOf: url)
        return parse(data)
    }

    static func parse(_ data: Data) -> [MHLEntry] {
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var out: [MHLEntry] = []
        let ns = xml as NSString
        let pattern = #"<file name=\"(.*?)\"><hash>(.*?)</hash></file>"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        re.enumerateMatches(in: xml, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 3 else { return }
            let name = ns.substring(with: m.range(at: 1))
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&apos;", with: "'")
            let hash = ns.substring(with: m.range(at: 2))
            out.append(MHLEntry(relPath: name, size: 0, hash: hash, mtime: nil))
        }
        return out
    }
}
