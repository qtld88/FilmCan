import Foundation

actor HashListWriter {
    private let outputPath: String
    private var handle: FileHandle?
    private var writtenCount: Int = 0
    private let algorithm: FilmCanHashAlgorithm
    private var writeError: String? = nil

    init(outputPath: String, algorithm: FilmCanHashAlgorithm = .xxh128) throws {
        self.outputPath = outputPath
        self.algorithm = algorithm
        let outputURL = URL(fileURLWithPath: outputPath)
        let folderURL = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            handle = try FileHandle(forWritingTo: outputURL)
            if let header = "# filmcan-hash: \(algorithm.headerTag)\n".data(using: .utf8) {
                handle?.write(header)
            }
        } catch {
            handle = nil
            throw error
        }
    }

    func append(hash: Data, path: String) {
        append(hashHex: hash.hexString, path: path)
    }

    func append(hashHex: String, path: String) {
        guard writeError == nil, let handle else { return }
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let line = "\(hashHex)  \(standardized)\n"
        if let data = line.data(using: .utf8) {
            do {
                try handle.write(contentsOf: data)
                writtenCount += 1
            } catch {
                writeError = error.localizedDescription
                try? handle.close()
                self.handle = nil
            }
        }
    }

    func count() -> Int {
        writtenCount
    }

    func errorMessage() -> String? {
        writeError
    }

    func close() {
        try? handle?.close()
        handle = nil
    }

    func removeFile() {
        close()
        try? FileManager.default.removeItem(atPath: outputPath)
    }
}
