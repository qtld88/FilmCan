import Foundation

struct WebhookService {
    static func parseHeaders(from text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }
            headers[name] = value
        }
        return headers
    }

    static func sendNtfy(urlString: String, bearerToken: String?, title: String, message: String, fields: [String: String]) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(title, forHTTPHeaderField: "Title")
        if let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let details = fields
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        let body = details.isEmpty ? message : "\(message)\n\n\(details)"
        request.httpBody = body.data(using: .utf8)

        URLSession.shared.dataTask(with: request).resume()
    }

    static func sendJSON(urlString: String, headers: [String: String], payload: [String: Any]) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        request.httpBody = body

        URLSession.shared.dataTask(with: request).resume()
    }

    /// Send a per-destination result notification
    static func sendDestNotification(
        urlString: String,
        bearerToken: String?,
        result: DestResult,
        sourceName: String
    ) {
        let icon = result.success ? "✅" : "❌"
        let title = "\(icon) Copy \(result.success ? "complete" : "failed"): \(sourceName)"
        let byteStr = ByteCountFormatter.string(fromByteCount: result.bytesTransferred, countStyle: .file)
        let message = "\(result.filesTransferred) files (\(byteStr)) → \(result.displayName)"
        sendNtfy(
            urlString: urlString,
            bearerToken: bearerToken,
            title: title,
            message: message,
            fields: [
                "Destination": result.displayName,
                "Path": result.destinationPath,
                "Status": result.success ? "OK" : "FAILED",
                "Bytes": byteStr,
                "Verify": result.verifyMode.rawValue
            ]
        )
    }

    /// Send a single aggregated webhook for a whole multi-destination job (v2 template).
    static func sendAggregatedNotification(
        urlString: String,
        bearerToken: String?,
        results: [DestResult],
        sourceName: String,
        configName: String
    ) {
        let anyFailed = results.contains { !$0.success }
        let allSucceeded = results.allSatisfy { $0.success }
        let icon = anyFailed ? "⚠️" : "✅"
        let summary = results.map { r in
            let mark = r.success ? "✓" : "✗"
            return "\(r.displayName) \(mark)"
        }.joined(separator: ", ")
        let totalBytes = results.reduce(Int64(0)) { $0 + $1.bytesTransferred }
        let byteStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let title = "\(icon) \(configName): \(sourceName)"
        let message = "\(summary) — \(byteStr)"
        sendNtfy(
            urlString: urlString,
            bearerToken: bearerToken,
            title: title,
            message: message,
            fields: [
                "Source": sourceName,
                "Config": configName,
                "DestinationsSummary": summary,
                "AnyFailed": anyFailed ? "true" : "false",
                "AllSucceeded": allSucceeded ? "true" : "false",
                "TotalBytes": byteStr,
                "DestinationCount": "\(results.count)"
            ]
        )
    }
}
