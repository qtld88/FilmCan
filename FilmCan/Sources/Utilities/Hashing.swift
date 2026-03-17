import Foundation

enum Hashing {
    static func hash(for url: URL, algorithm: FilmCanHashAlgorithm) -> String? {
        guard let data = hashData(for: url, algorithm: algorithm) else { return nil }
        return data.hexString
    }

    static func hashData(for url: URL, algorithm: FilmCanHashAlgorithm) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bufferSize = DriveUtilities.isExFAT(path: url.path) ? (4 * 1024 * 1024) : (1024 * 1024)

        guard let hasher = makeHasher(algorithm: algorithm) else { return nil }
        while autoreleasepool(invoking: {
            let data = handle.readData(ofLength: bufferSize)
            if data.isEmpty { return false }
            hasher.update(data: data)
            return true
        }) {}

        return hasher.finalize()
    }

    private static func makeHasher(algorithm: FilmCanHashAlgorithm) -> StreamingHasher? {
        switch algorithm {
        case .xxh128:
            return XXH128StreamingHasher()
        }
    }

    
}
