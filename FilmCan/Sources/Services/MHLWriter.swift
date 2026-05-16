import Foundation

actor MHLWriter {
    private let url: URL
    private let sourceName: String
    private var entries: [(hash: String, fileName: String)] = []
    private var finalized = false
    private var fileHandle: FileHandle?
    private var flushedUpTo = 0
    private let flushEveryFiles = Constants.mhlFlushEveryFiles

    init(url: URL, sourceName: String) throws {
        self.url = url
        self.sourceName = sourceName
        try createEmptyFile()
    }

    private func createEmptyFile() throws {
        var xml = header()
        xml += trailer()
        try xml.write(to: url, atomically: false, encoding: .utf8)
        fileHandle = try FileHandle(forUpdating: url)
        if #available(macOS 13.4, *) {
            try fileHandle?.seekToEnd()
        } else {
            fileHandle?.seekToEndOfFile()
        }
    }

    func append(hash: String, fileName: String) async throws {
        guard !finalized else { return }
        entries.append((hash, fileName))
        if (entries.count - flushedUpTo) >= flushEveryFiles {
            try await flush()
        }
    }

    func flush() async throws {
        guard !finalized else { return }
        let newEntries = entries[flushedUpTo...]
        guard !newEntries.isEmpty else { return }
        guard let handle = fileHandle else { return }
        var chunk = ""
        for entry in newEntries {
            chunk += entryXml(hash: entry.hash, fileName: entry.fileName)
        }
        guard let data = chunk.data(using: .utf8) else { return }
        /* remove old trailer, append new entries, rewrite trailer */
        try overwriteTrailer(appending: data)
        flushedUpTo = entries.count
    }

    func cancel() {
        finalized = true
        fileHandle?.closeAndNull()
        try? FileManager.default.removeItem(at: url)
    }

    deinit {
        fileHandle?.closeAndNull()
    }

    // MARK: - Private XML helpers

    private func header() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="1.0" source="\(sourceName)">
        """
    }

    private func trailer() -> String {
        "\n</hashlist>"
    }

    private func entryXml(hash: String, fileName: String) -> String {
        "\n  <file name=\"\(fileName)\"><hash>\(hash)</hash></file>"
    }

    private func overwriteTrailer(appending data: Data) throws {
        guard let handle = fileHandle else { return }
        let trailerLen = trailer().lengthOfBytes(using: .utf8)
        if #available(macOS 13.4, *) {
            try handle.seek(toOffset: UInt64(max(0, Int(handle.offsetInFile) - trailerLen)))
        } else {
            handle.seek(toFileOffset: UInt64(max(0, Int(handle.offsetInFile) - trailerLen)))
        }
        handle.write(data)
        guard let trailerData = trailer().data(using: .utf8) else { return }
        handle.write(trailerData)
    }
}

// MARK: - FileHandle cleanup helper

private extension FileHandle {
    func closeAndNull() {
        try? self.close()
    }
}
