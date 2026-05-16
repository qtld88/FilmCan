import Foundation

actor SiblingDestSource {
    enum Error: Swift.Error, LocalizedError {
        case noSiblingFound(String)
        case siblingVerifyFailed(String)
        case readFailed(String)

        var errorDescription: String? {
            switch self {
            case .noSiblingFound(let s): return "No verified sibling found for: \(s)"
            case .siblingVerifyFailed(let s): return "Sibling verification failed: \(s)"
            case .readFailed(let s): return "Read from sibling failed: \(s)"
            }
        }
    }

    func findVerifiedSibling(fileName: String, in destResults: [DestResult]) -> String? {
        let verified = destResults.filter { $0.success }
        for result in verified {
            let candidate = (result.destinationPath as NSString).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    func copyFromSibling(fileName: String, from sourcePath: String, to destPath: String, chunkSize: Int = 4 * 1024 * 1024) async throws {
        guard FileManager.default.fileExists(atPath: sourcePath) else {
            throw Error.noSiblingFound(fileName)
        }
        let srcHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: sourcePath))
        defer { try? srcHandle.close() }
        fcntl(srcHandle.fileDescriptor, F_NOCACHE, 1)

        let destURL = URL(fileURLWithPath: destPath)
        let fm = FileManager.default
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let uuid = UUID().uuidString
        let tempName = ".filmcan-\(uuid)-\(destURL.lastPathComponent)"
        let tempURL = destURL.deletingLastPathComponent().appendingPathComponent(tempName)
        fm.createFile(atPath: tempURL.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? destHandle.close() }
        fcntl(destHandle.fileDescriptor, F_NOCACHE, 1)

        while true {
            guard let data = try srcHandle.read(upToCount: chunkSize) else { break }
            try destHandle.write(contentsOf: data)
        }
        try destHandle.synchronize()
        _ = try fm.replaceItemAt(destURL, withItemAt: tempURL)
    }
}
