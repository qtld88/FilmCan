import Foundation

enum NotificationDispatcher {

    static func sendSource(
        source: String,
        config: BackupConfiguration,
        results: [TransferResult],
        settings: NotificationSettings,
        summaryFor: (TransferResult) async -> NotificationSummaryBuilder.DestinationNotificationSummary
    ) async {
        if config.webhookTemplateFormatVersion >= 2 {
            sendAggregated(source: source, config: config, results: results, settings: settings)
            return
        }
        for result in results {
            let summary = await summaryFor(result)
            guard !summary.wasPaused else { continue }

            if summary.allSuccess && settings.notifyOnComplete {
                NotificationService.shared.notify(
                    title: summary.title,
                    body: summary.body
                )
            } else if !summary.allSuccess && settings.notifyOnError {
                NotificationService.shared.notify(
                    title: summary.title,
                    body: summary.body
                )
            }

            if settings.ntfyEnabled, !settings.ntfyURL.isEmpty {
                sendNtfy(summary, settings)
            }
            if settings.webhookEnabled, !settings.webhookURL.isEmpty {
                sendWebhook(summary, settings)
            }
        }
    }

    /// v2: one aggregated event per backup-run covering ALL destinations.
    static func sendAggregated(
        source: String,
        config: BackupConfiguration,
        results: [TransferResult],
        settings: NotificationSettings
    ) {
        guard !results.isEmpty else { return }
        let wasPaused = results.contains { $0.wasPaused }
        if wasPaused { return }

        let anyFailed = results.contains { !$0.success }
        let allSuccess = !anyFailed
        let sourceName = (source as NSString).lastPathComponent
        let totalBytes = results.reduce(Int64(0)) { $0 + $1.bytesTransferred }
        let bytesText = FilmCanFormatters.bytes(totalBytes, style: .decimal)
        let destSummary = results.map { r in
            let mark = r.success ? "✓" : "✗"
            let name = (r.destination as NSString).lastPathComponent
            return "\(name) \(mark)"
        }.joined(separator: ", ")
        let status = anyFailed ? "Done with failures" : "Done"
        let title = "\(sourceName) → \(config.name): \(status)"
        let body = "\(destSummary) — \(bytesText)"

        if allSuccess && settings.notifyOnComplete {
            NotificationService.shared.notify(title: title, body: body)
        } else if !allSuccess && settings.notifyOnError {
            NotificationService.shared.notify(title: title, body: body)
        }
        if settings.ntfyEnabled, !settings.ntfyURL.isEmpty {
            let ntfyToken = KeychainStore().get("ntfyBearerToken")
            WebhookService.sendNtfy(
                urlString: settings.ntfyURL,
                bearerToken: ntfyToken,
                title: title,
                message: body,
                fields: [
                    "Source": sourceName,
                    "Config": config.name,
                    "DestinationsSummary": destSummary,
                    "AnyFailed": anyFailed ? "true" : "false",
                    "AllSucceeded": allSuccess ? "true" : "false",
                    "TotalBytes": bytesText,
                    "DestinationCount": "\(results.count)"
                ]
            )
        }
        if settings.webhookEnabled, !settings.webhookURL.isEmpty {
            let webhookHeadersText = KeychainStore().get("webhookHeaders") ?? ""
            WebhookService.sendJSON(
                urlString: settings.webhookURL,
                headers: WebhookService.parseHeaders(from: webhookHeadersText),
                payload: [
                    "title": title,
                    "message": body,
                    "templateFormatVersion": 2,
                    "source": sourceName,
                    "config": config.name,
                    "destinationCount": results.count,
                    "anyFailed": anyFailed,
                    "allSucceeded": allSuccess,
                    "totalBytes": totalBytes,
                    "destinations": results.map { r in
                        [
                            "name": (r.destination as NSString).lastPathComponent,
                            "path": WebhookService.maskedField(path: r.destination, includeFull: settings.webhookIncludeFullPaths),
                            "success": r.success,
                            "bytesTransferred": r.bytesTransferred,
                            "filesTransferred": r.filesTransferred,
                            "errorMessage": r.errorMessage ?? "",
                            "wasVerified": r.wasVerified
                        ] as [String: Any]
                    }
                ]
            )
        }
    }

    static func sendNtfy(
        _ summary: NotificationSummaryBuilder.DestinationNotificationSummary,
        _ settings: NotificationSettings
    ) {
        let ntfyToken = KeychainStore().get("ntfyBearerToken")
        WebhookService.sendNtfy(
            urlString: settings.ntfyURL,
            bearerToken: ntfyToken,
            title: summary.messageTitle,
            message: summary.messageBody,
            fields: [:]
        )
    }

    static func sendWebhook(
        _ summary: NotificationSummaryBuilder.DestinationNotificationSummary,
        _ settings: NotificationSettings
    ) {
        let webhookHeadersText = KeychainStore().get("webhookHeaders") ?? ""
        WebhookService.sendJSON(
            urlString: settings.webhookURL,
            headers: WebhookService.parseHeaders(from: webhookHeadersText),
            payload: [
                "title": summary.messageTitle,
                "message": summary.messageBody,
                "fields": summary.fields
            ]
        )
    }
}
