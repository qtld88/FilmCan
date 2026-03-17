import Foundation

struct TransferResult: Identifiable {
    let id: UUID = UUID()
    var configurationName: String
    let destination: String
    let startTime: Date
    var endTime: Date?
    var success: Bool = true
    var errorMessage: String?
    var warningMessage: String?
    var filesTransferred: Int = 0
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64 = 0
    var filesSkipped: Int = 0
    var errors: [String] = []
    var organizationRoots: [String: String] = [:]
    var logFilePath: String? = nil
    var hashListPath: String? = nil
    var hashRoots: [String] = []
    var transferredPaths: [String] = []
    var usedItemizedOutput: Bool = false
    var visibleFilesTransferred: Int? = nil
    var visibleFilesSkipped: Int? = nil
    var sourceHashes: [String: String] = [:]
    var wasPaused: Bool = false
    var wasVerified: Bool = false
    var organizationPresetName: String? = nil
    var duplicatePolicy: OrganizationPreset.DuplicatePolicy? = nil
    var duplicateHits: Int = 0

    var isAlreadyAtDestination: Bool {
        if filesTransferred > 0 {
            return false
        }
        if filesSkipped > 0 {
            return true
        }
        if duplicateHits > 0, duplicatePolicy == .skip {
            return true
        }
        return false
    }

    var isAlreadyAtDestinationAndVerified: Bool {
        success && wasVerified && isAlreadyAtDestination
    }
    
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    var formattedDuration: String {
        guard let dur = duration else { return "N/A" }
        return FilmCanFormatters.durationCompact(dur)
    }
    
    var summary: String {
        if success {
            let noun = filesTransferred == 1 ? "file" : "files"
            return "Transferred \(filesTransferred) \(noun)"
        } else {
            return "Failed: \(errorMessage ?? "Unknown error")"
        }
    }
}
