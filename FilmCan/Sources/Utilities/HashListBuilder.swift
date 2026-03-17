import Foundation

enum HashListBuilder {
    struct Result {
        let fileCount: Int
        let outputPath: String
    }

    static func generateHashList(
        files: [String],
        outputPath: String,
        useAbsolutePaths: Bool = true,
        algorithm: FilmCanHashAlgorithm = .xxh128
    ) -> Result? {
        let uniqueFiles = Array(Set(files)).sorted()
        guard !uniqueFiles.isEmpty else { return nil }
        let outputURL = URL(fileURLWithPath: outputPath)
        let folderURL = outputURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }

            var count = 0
            if let header = "# filmcan-hash: \(algorithm.headerTag)\n".data(using: .utf8) {
                handle.write(header)
            }
            for file in uniqueFiles {
                let fileURL = URL(fileURLWithPath: file)
                let standardized = fileURL.standardizedFileURL.path
                if isHiddenPath(standardized) { continue }
                if FilmCanPaths.isHidden(standardized) { continue }
                if fileURL.lastPathComponent == ".DS_Store" { continue }
                if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                   values.isDirectory == true {
                    continue
                }
                guard let hash = Hashing.hash(for: fileURL, algorithm: algorithm) else { continue }
                let pathComponent = useAbsolutePaths ? standardized : fileURL.lastPathComponent
                let line = "\(hash)  \(pathComponent)\n"
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                    count += 1
                }
            }

            return Result(fileCount: count, outputPath: outputURL.path)
        } catch {
            return nil
        }
    }

    private static func isHiddenPath(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        return components.contains { $0.hasPrefix(".") }
    }

    static func generateHashList(
        roots: [String],
        outputPath: String,
        useAbsolutePaths: Bool = false,
        algorithm: FilmCanHashAlgorithm = .xxh128
    ) -> Result? {
        guard !roots.isEmpty else { return nil }
        let outputURL = URL(fileURLWithPath: outputPath)
        let folderURL = outputURL.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            defer { try? handle.close() }

            var count = 0
            if let header = "# filmcan-hash: \(algorithm.headerTag)\n".data(using: .utf8) {
                handle.write(header)
            }
            for root in roots {
                let rootURL = URL(fileURLWithPath: root)
                let rootPath = rootURL.standardizedFileURL.path
                let rootLabel = rootURL.lastPathComponent
                let usePrefix = roots.count > 1 && !useAbsolutePaths
                let enumerator = FileManager.default.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )

                while let fileURL = enumerator?.nextObject() as? URL {
                    let standardized = fileURL.standardizedFileURL.path
                    if FilmCanPaths.isHidden(standardized) { continue }
                    if fileURL.lastPathComponent == ".DS_Store" { continue }
                    if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                       values.isDirectory == true {
                        continue
                    }
                    guard let hash = Hashing.hash(for: fileURL, algorithm: algorithm) else { continue }
                    let pathComponent: String
                    if useAbsolutePaths {
                        pathComponent = standardized
                    } else {
                        var relative = standardized
                        if standardized.hasPrefix(rootPath) {
                            relative = String(standardized.dropFirst(rootPath.count))
                            if relative.hasPrefix("/") {
                                relative.removeFirst()
                            }
                        }
                        pathComponent = usePrefix ? "\(rootLabel)/\(relative)" : relative
                    }
                    let line = "\(hash)  \(pathComponent)\n"
                    if let data = line.data(using: .utf8) {
                        handle.write(data)
                        count += 1
                    }
                }
            }

            return Result(fileCount: count, outputPath: outputURL.path)
        } catch {
            return nil
        }
    }

}
