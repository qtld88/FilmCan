import Foundation

/// Refuses to follow a redirect to a different host (or to a no-longer-allowed
/// URL). `URLSession` otherwise re-sends the request — including the
/// `Authorization: Bearer` header and any user-supplied auth headers — to the
/// redirect target, which an attacker-controlled 30x could use to exfiltrate the
/// token. Same-host redirects that remain https/localhost are allowed.
private final class WebhookRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if WebhookService.shouldFollowRedirect(
            originalHost: task.originalRequest?.url?.host, to: request.url?.absoluteString) {
            completionHandler(request)
        } else {
            completionHandler(nil)   // stop here; never forward credentials cross-host
        }
    }
}

enum WebhookHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config, delegate: WebhookRedirectGuard(), delegateQueue: nil)
    }()
}

struct WebhookService {
    static func isAllowedURL(_ urlString: String) -> Bool {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host,
              let scheme = url.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        if scheme == "http", host == "localhost" || host == "127.0.0.1" { return true }
        return false
    }

    /// Redirect policy for credentialed notification requests: follow only when the
    /// target stays on the same host AND remains an allowed (https / localhost) URL.
    /// Anything else could leak the bearer token / auth headers to another host.
    static func shouldFollowRedirect(originalHost: String?, to target: String?) -> Bool {
        guard let target, isAllowedURL(target),
              let originalHost = originalHost?.lowercased(),
              let newHost = URL(string: target.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased(),
              originalHost == newHost else { return false }
        return true
    }

    static func maskedField(path: String, includeFull: Bool) -> String {
        includeFull ? path : (path as NSString).lastPathComponent
    }

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
        guard isAllowedURL(trimmed), let url = URL(string: trimmed) else {
            DebugLog.warn("ntfy URL rejected (must be https or localhost): \(trimmed)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(title, forHTTPHeaderField: "Title")
        if let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let details = fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let body = details.isEmpty ? message : "\(message)\n\n\(details)"
        request.httpBody = body.data(using: .utf8)
        WebhookHTTP.session.dataTask(with: request) { _, response, error in
            if let error { DebugLog.warn("ntfy send failed: \(error.localizedDescription)") }
            else if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
                DebugLog.warn("ntfy send HTTP \(code)")
            }
        }.resume()
    }

    static func sendJSON(urlString: String, headers: [String: String], payload: [String: Any]) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAllowedURL(trimmed), let url = URL(string: trimmed) else {
            DebugLog.warn("webhook URL rejected (must be https or localhost): \(trimmed)")
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        guard JSONSerialization.isValidJSONObject(payload),
              let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        request.httpBody = body
        WebhookHTTP.session.dataTask(with: request) { _, response, error in
            if let error { DebugLog.warn("webhook send failed: \(error.localizedDescription)") }
            else if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
                DebugLog.warn("webhook send HTTP \(code)")
            }
        }.resume()
    }

    /// Send a per-destination result notification
    static func sendDestNotification(
        urlString: String,
        bearerToken: String?,
        result: DestResult,
        sourceName: String,
        includeFullPaths: Bool = false
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
                "Path": maskedField(path: result.destinationPath, includeFull: includeFullPaths),
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
        configName: String,
        includeFullPaths: Bool = false
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
