import Foundation

/// Reads and writes the ASC MHL chain index (`ascmhl_chain.xml`) — the file that
/// records each manifest generation and the C4 hash of that manifest, forming the
/// chain of custody the ASC MHL tooling requires.
enum ASCMHLChain {
    struct Ref: Equatable { let seq: Int; let path: String; let c4: String }

    static func chainURL(ascmhlDir: URL) -> URL {
        ascmhlDir.appendingPathComponent("ascmhl_chain.xml")
    }

    enum ChainError: Swift.Error, LocalizedError {
        /// The chain exists but cannot be parsed.
        case unreadable(URL)
        /// It was renamed out of the way, untouched; this generation is not chained.
        case unreadableSetAside(original: URL, keptAs: URL)

        var errorDescription: String? {
            switch self {
            case .unreadable(let url):
                return "The hash list chain \(url.lastPathComponent) in \(url.deletingLastPathComponent().path) cannot be read."
            case .unreadableSetAside(let original, let keptAs):
                return "The hash list chain \(original.lastPathComponent) in \(original.deletingLastPathComponent().path) "
                    + "could not be read. It was kept, unchanged, as \(keptAs.lastPathComponent), "
                    + "and this run's manifest was not added to any chain."
            }
        }
    }

    /// Lenient read: missing or unreadable both give no generations. For display and
    /// resume only — never to rewrite the chain (see `readStrict`).
    static func read(ascmhlDir: URL) -> [Ref] {
        (try? readStrict(ascmhlDir: ascmhlDir)) ?? []
    }

    /// No chain file → []. A chain file that does not parse → `ChainError.unreadable`.
    static func readStrict(ascmhlDir: URL) throws -> [Ref] {
        let url = chainURL(ascmhlDir: ascmhlDir)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { throw ChainError.unreadable(url) }
        let parser = ChainParser()
        guard parser.parse(data: data) else { throw ChainError.unreadable(url) }
        return parser.refs.sorted { $0.seq < $1.seq }
    }

    /// Marker FilmCan writes into a generation finalized as partial.
    static let partialMarker = "<!-- filmcan:partial"

    /// The sequence number a new generation takes, and the partial generations it
    /// supersedes. A cancelled run leaves a FilmCan partial outside the chain; the
    /// next run reads it for resume, carries its entries and takes its number, so the
    /// chain has no hole and no stray manifest is left for ASC tools (the reference
    /// `ascmhl` loads every .mhl in the folder as a generation). Only readable FilmCan
    /// partials are superseded: anything else unchained (a foreign or damaged file, a
    /// lost chain) keeps its number and the new generation goes after all of them.
    static func planGeneration(ascmhlDir: URL) -> (sequence: Int, superseded: [URL]) {
        let disk = manifestFilesOnDisk(ascmhlDir: ascmhlDir)
        let diskMax = disk.map { $0.seq }.max() ?? 0
        guard let refs = try? readStrict(ascmhlDir: ascmhlDir) else { return (diskMax + 1, []) }
        let chainMax = refs.map { $0.seq }.max() ?? 0
        let chained = Set(refs.map { $0.path })
        let unchained = disk.filter { $0.seq > chainMax && !chained.contains($0.url.lastPathComponent) }
        if !unchained.isEmpty, unchained.allSatisfy({ isReadablePartial($0.url) }) {
            return (chainMax + 1, unchained.map { $0.url })
        }
        return (max(chainMax, diskMax) + 1, [])
    }

    private static func isReadablePartial(_ url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              text.contains(partialMarker) else { return false }
        return (try? ASCMHLReader.read(url: url)) != nil
    }

    /// The sequence number the next generation takes (see `planGeneration`).
    static func nextSequence(ascmhlDir: URL) -> Int {
        planGeneration(ascmhlDir: ascmhlDir).sequence
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
        manifestFilesNewestFirst(ascmhlDir: ascmhlDir).first?.lastPathComponent
    }

    /// Every generation manifest on disk, newest first (sequence, then modification
    /// date). Resume walks it to fall back past a damaged latest generation.
    static func manifestFilesNewestFirst(ascmhlDir: URL) -> [URL] {
        func mtime(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return manifestFilesOnDisk(ascmhlDir: ascmhlDir).sorted {
            $0.seq != $1.seq ? $0.seq > $1.seq : mtime($0.url) > mtime($1.url)
        }.map { $0.url }
    }

    /// Append (or replace) the generation `sequence` with the C4 of `manifestData`,
    /// preserving all other generations, and rewrite the chain file. A chain that
    /// exists but cannot be read is never rewritten: it is renamed aside, untouched,
    /// and `ChainError.unreadableSetAside` is thrown so the run reports it.
    static func append(ascmhlDir: URL, sequence: Int, manifestFileName: String,
                       manifestData: Data) throws {
        try FileManager.default.createDirectory(at: ascmhlDir, withIntermediateDirectories: true)
        let c4 = C4Hash.id(of: manifestData)
        let existing: [Ref]
        do {
            existing = try readStrict(ascmhlDir: ascmhlDir)
        } catch ChainError.unreadable(let url) {
            let keptAs = try setAside(url)
            throw ChainError.unreadableSetAside(original: url, keptAs: keptAs)
        }
        var refs = existing.filter { $0.seq != sequence }
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

    /// `ascmhl_chain.xml.unreadable-<UTC stamp>[-N]` next to it: not a `.mhl`, so ASC
    /// tools ignore it, and nothing is overwritten.
    private static func setAside(_ url: URL) throws -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.locale = Locale(identifier: "en_US_POSIX")
        let base = "\(url.lastPathComponent).unreadable-\(f.string(from: Date()))Z"
        let dir = url.deletingLastPathComponent()
        var target = dir.appendingPathComponent(base)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(base)-\(n)"); n += 1
        }
        try FileManager.default.moveItem(at: url, to: target)
        return target
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
