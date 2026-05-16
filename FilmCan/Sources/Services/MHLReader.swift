import Foundation

enum MHLReader {
    struct Entry: Equatable {
        let hash: String
        let fileName: String
    }

    static func read(url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        let parser = MHLParser()
        try parser.parse(data: data)
        return parser.entries
    }
}

// MARK: - SAX-style parser

private final class MHLParser: NSObject, XMLParserDelegate {
    var entries: [MHLReader.Entry] = []
    private var currentFileName: String = ""
    private var currentHash: String = ""
    private var inHash = false
    private var inFile = false
    private var charBuf = ""

    func parse(data: Data) throws {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? MHLParseError.unknown
        }
    }

    enum MHLParseError: Error {
        case unknown
    }

    // MARK: - Delegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        charBuf = ""
        if elementName == "file" {
            inFile = true
            currentFileName = attributeDict["name"] ?? ""
        } else if elementName == "hash" {
            inHash = true
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        charBuf += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "file" {
            inFile = false
            entries.append(MHLReader.Entry(hash: currentHash.trimmingCharacters(in: .whitespacesAndNewlines),
                                           fileName: currentFileName))
            currentHash = ""
        } else if elementName == "hash" {
            inHash = false
            currentHash = charBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
