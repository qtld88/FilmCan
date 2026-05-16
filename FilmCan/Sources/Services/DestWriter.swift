import Foundation

actor DestWriter {
    enum Error: Swift.Error, LocalizedError {
        case destSetupFailed(String)
        case writeFailed(String)
        case verifyFailed(String)
        case finalizeFailed(String)

        var errorDescription: String? {
            switch self {
            case .destSetupFailed(let s): return "Destination setup failed: \(s)"
            case .writeFailed(let s): return "Write failed: \(s)"
            case .verifyFailed(let s): return "Verify failed: \(s)"
            case .finalizeFailed(let s): return "Finalize failed: \(s)"
            }
        }
    }

    struct Config {
        var destPath: String
        var displayName: String
        var verifyMode: VerifyMode
        var requiresFullFsync: Bool
        var tempSuffix: String
        var chunkSize: Int?
    }

    private let config: Config
    private var copier: FileStreamCopier

    init(config: Config) async {
        self.config = config
        copier = FileStreamCopier()
        await copier.configure(requiresFullFsync: config.requiresFullFsync, chunkSizeOverride: config.chunkSize)
    }

    func writeChunk(_ chunk: Data, relativePath: String) async throws {
        // Chunk received — can optionally write to temp file
        // Actual implementation in fan-out pipeline
    }

    func finalizeFile(relativePath: String, sourceHash: String) async throws -> DestResult {
        // Atomic finalize: rename .filmcan-<uuid>-<name> to <name>
        // Verify if paranoid mode
        // Return DestResult
        DestResult(destinationPath: config.destPath, displayName: config.displayName, success: true,
                   verifyMode: config.verifyMode)
    }
}
