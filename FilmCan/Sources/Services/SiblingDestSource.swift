import Foundation
import Darwin

actor SiblingDestSource {
    enum Error: Swift.Error, LocalizedError {
        case noSiblingFound(String)
        case siblingVerifyFailed(String)
        case readFailed(String)
        case hashMismatch(String, String, String)

        var errorDescription: String? {
            switch self {
            case .noSiblingFound(let s): return "No verified sibling found for: \(s)"
            case .siblingVerifyFailed(let s): return "Sibling verification failed: \(s)"
            case .readFailed(let s): return "Read from sibling failed: \(s)"
            case .hashMismatch(let f, let e, let a):
                return "Hash mismatch on \(f): expected \(e), actual \(a)"
            }
        }
    }

    func findVerifiedSibling(fileName: String, in destResults: [DestResult], expectedHash: String) async throws -> String? {
        let verified = destResults.filter { $0.success }
        for result in verified {
            let candidate = (result.destinationPath as NSString).appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: candidate) else { continue }

            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: candidate))
            defer { try? handle.close() }
            fcntl(handle.fileDescriptor, F_NOCACHE, 1)

            guard let hasher = XXH128StreamingHasher() else {
                throw Error.readFailed("XXH128 unavailable")
            }
            while true {
                guard let data = try handle.read(upToCount: 4 * 1024 * 1024) else { break }
                hasher.update(data: data)
            }
            let hash = hasher.finalize().hexString
            if hash == expectedHash {
                return candidate
            }
        }
        return nil
    }

    func copyFromSibling(fileName: String, from sourcePath: String, to destPath: String, expectedHash: String, chunkSize: Int = 4 * 1024 * 1024) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else {
            throw Error.noSiblingFound(fileName)
        }

        let srcURL = URL(fileURLWithPath: sourcePath)
        let destURL = URL(fileURLWithPath: destPath)
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let srcHandle = try FileHandle(forReadingFrom: srcURL)
        defer { try? srcHandle.close() }
        fcntl(srcHandle.fileDescriptor, F_NOCACHE, 1)

        let uuid = UUID().uuidString
        let tempName = ".filmcan-\(uuid)-\(destURL.lastPathComponent)"
        let tempURL = destURL.deletingLastPathComponent().appendingPathComponent(tempName)
        fm.createFile(atPath: tempURL.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: tempURL)
        defer { try? destHandle.close() }
        fcntl(destHandle.fileDescriptor, F_NOCACHE, 1)

        guard let hasher = XXH128StreamingHasher() else {
            try? fm.removeItem(at: tempURL)
            throw Error.readFailed("XXH128 unavailable")
        }
        while true {
            guard let data = try srcHandle.read(upToCount: chunkSize) else { break }
            try destHandle.write(contentsOf: data)
            hasher.update(data: data)
        }
        try destHandle.synchronize()

        let actualHash = hasher.finalize().hexString
        guard actualHash == expectedHash else {
            try? fm.removeItem(at: tempURL)
            throw Error.hashMismatch(fileName, expectedHash, actualHash)
        }

        let renamed = tempURL.withUnsafeFileSystemRepresentation { tempPath -> Int32 in
            destURL.withUnsafeFileSystemRepresentation { destPathRep in
                guard let t = tempPath, let d = destPathRep else { return -1 }
                return Darwin.rename(t, d)
            }
        }
        guard renamed == 0 else {
            try? fm.removeItem(at: tempURL)
            throw Error.readFailed("rename(2) failed for \(destURL.path) (errno=\(errno))")
        }
    }
}
