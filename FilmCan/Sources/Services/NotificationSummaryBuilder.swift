import Foundation

enum NotificationSummaryBuilder {

    struct DestinationNotificationSummary {
        let title: String
        let body: String
        let messageTitle: String
        let messageBody: String
        let fields: [String: String]
        let allSuccess: Bool
        let wasPaused: Bool
    }

    static func formatQuotedList(_ paths: [String]) -> String {
        let names = paths.map { "\"\(($0 as NSString).lastPathComponent)\"" }
        if names.isEmpty { return "No items" }
        if names.count == 1 { return names[0] }
        if names.count == 2 { return "\(names[0]) and \(names[1])" }
        let head = names.prefix(3).joined(separator: ", ")
        let remaining = names.count - 3
        if remaining > 0 {
            return "\(head), and \(remaining) others"
        }
        return head
    }

    static func durationString(durations: [TimeInterval]) -> String? {
        guard !durations.isEmpty else { return nil }
        let total = durations.reduce(0, +)
        let hours = Int(total) / 3600
        let minutes = (Int(total) % 3600) / 60
        let seconds = Int(total) % 60
        if hours > 0 { return String(format: "%dh %dm %ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }

    static func applyTemplate(_ template: String, replacements: [String: String]) -> String {
        OrganizationTemplate.substituteTokens(template, values: replacements)
    }

    /// Build the per-destination summary from already-resolved totals.
    static func destinationSummary(
        source: String,
        config: BackupConfiguration,
        result: TransferResult,
        totalFiles: Int,
        totalBytes: Int64,
        settings: NotificationSettings
    ) -> DestinationNotificationSummary {
        let wasPaused = result.wasPaused
        let isCancelled = (result.errorMessage ?? "").lowercased().contains("cancelled")
        let allSuccess = result.success && !isCancelled
        let sourceName = (source as NSString).lastPathComponent
        let destinationName = (result.destination as NSString).lastPathComponent
        let bytesText = FilmCanFormatters.bytes(totalBytes, style: .decimal)
        let durationText = Self.durationString(durations: result.duration.map { [$0] } ?? []) ?? "0s"

        let backupAction: String
        if !result.success || isCancelled {
            backupAction = "failed to back up"
        } else if result.isAlreadyAtDestination {
            backupAction = "already in place"
        } else {
            backupAction = "backed up"
        }

        let backupStatus: String
        let backupDetails: String
        if result.success && !isCancelled {
            backupStatus = "Done."
            backupDetails = "No backup failed."
        } else if isCancelled {
            backupStatus = "Cancelled by user."
            backupDetails = "1 destination(s) failed. 1 cancelled by user."
        } else {
            backupStatus = "Failed."
            backupDetails = result.errorMessage ?? "Backup failed."
        }

        let title = "\(sourceName)'s backup for \(config.name): \(backupStatus)"
        let body = "\(bytesText) (\(totalFiles) files) from \(sourceName) has been \(backupAction) to \(destinationName) in \(durationText)."

        let sourcesText = Self.formatQuotedList([source])
        let destinationsText = Self.formatQuotedList(config.destinationPaths)
        let template = settings.ntfyMessageTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleTemplate = settings.ntfyTitleTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [String: String] = [
            "{movie}": config.name,
            "{source}": sourceName,
            "{destination}": destinationName,
            "{sources}": sourcesText,
            "{destinations}": destinationsText,
            "{backupAction}": backupAction,
            "{bytes}": bytesText,
            "{files}": "\(totalFiles)",
            "{duration}": durationText,
            "{backupStatus}": backupStatus,
            "{backupDetails}": backupDetails
        ]

        let messageTitle = titleTemplate.isEmpty
            ? title
            : Self.applyTemplate(titleTemplate, replacements: replacements)

        let messageBody = template.isEmpty
            ? body
            : Self.applyTemplate(template, replacements: replacements)

        return DestinationNotificationSummary(
            title: title,
            body: body,
            messageTitle: messageTitle,
            messageBody: messageBody,
            fields: replacements,
            allSuccess: allSuccess,
            wasPaused: wasPaused
        )
    }
}
