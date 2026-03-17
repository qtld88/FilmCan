import Foundation

struct TransferResultSummary {
    let destination: String
    let success: Bool
    let errorMessage: String?
    let warningMessage: String?
    let filesTransferred: Int
    let filesSkipped: Int
    let bytesTransferred: Int64
    let logCreated: Bool
    let duration: TimeInterval?

    init(result: TransferResult, counts: (transferred: Int, skipped: Int)? = nil) {
        destination = result.destination
        success = result.success
        errorMessage = result.errorMessage
        warningMessage = result.warningMessage
        let transferred = counts?.transferred ?? (result.visibleFilesTransferred ?? result.filesTransferred)
        let skipped = counts?.skipped ?? (result.visibleFilesSkipped ?? result.filesSkipped)
        filesTransferred = transferred
        filesSkipped = skipped
        bytesTransferred = result.bytesTransferred
        logCreated = (result.logFilePath?.isEmpty == false)
        duration = result.duration
    }

    init(record: TransferResultRecord, counts: (transferred: Int, skipped: Int)? = nil) {
        destination = record.destination
        success = record.success
        errorMessage = record.errorMessage
        warningMessage = record.warningMessage
        let transferred = counts?.transferred ?? (record.visibleFilesTransferred ?? record.filesTransferred)
        let skipped = counts?.skipped ?? (record.visibleFilesSkipped ?? record.filesSkipped)
        filesTransferred = transferred
        filesSkipped = skipped
        bytesTransferred = record.bytesTransferred
        logCreated = (record.logFilePath?.isEmpty == false)
        if let end = record.endTime {
            duration = end.timeIntervalSince(record.startTime)
        } else {
            duration = nil
        }
    }

    var bytesText: String {
        FilmCanFormatters.bytes(bytesTransferred, style: .decimal)
    }

    var durationText: String {
        guard let duration else { return "N/A" }
        return FilmCanFormatters.durationCompact(duration)
    }

    var historySummaryLine: String {
        var parts: [String] = []
        let fileLabel = filesTransferred == 1 ? "file" : "files"
        parts.append("\(filesTransferred) \(fileLabel) copied")
        if logCreated {
            parts.append("1 log created")
        }
        if filesSkipped > 0 {
            parts.append("\(filesSkipped) already there")
        }
        parts.append(bytesText)
        return parts.joined(separator: " · ")
    }
}
