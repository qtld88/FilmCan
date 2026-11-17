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

/// Result of one ntfy publish attempt, in terms the user can act on.
enum NtfyOutcome: Equatable {
    case sent(status: Int)
    case rejectedURL
    case transportFailure(String)
    /// `tokenWasSent` separates "no credentials offered" from "credentials refused",
    /// which is the whole diagnosis for the two codes ntfy uses.
    case httpFailure(status: Int, tokenWasSent: Bool)

    var isSuccess: Bool {
        if case .sent = self { return true }
        return false
    }

    var userMessage: String {
        switch self {
        case .sent(let status):
            return "Push delivered (HTTP \(status))."
        case .rejectedURL:
            return "Topic URL rejected. It must start with https:// (http:// only for localhost)."
        case .transportFailure(let reason):
            return "Could not reach the server: \(reason)"
        case .httpFailure(401, _):
            return "HTTP 401 — the server refused the token. Check that you pasted the "
                 + "access token itself (ntfy tokens start with tk_), not a label or URL."
        case .httpFailure(403, let tokenWasSent):
            return tokenWasSent
                ? "HTTP 403 — the token is valid but not allowed to publish to this topic. "
                  + "Grant it write access, or use a token that has it."
                : "HTTP 403 — this topic requires a token and none is set. Enter the bearer token."
        case .httpFailure(404, _):
            return "HTTP 404 — no such topic at that URL. Check the topic name."
        case .httpFailure(429, _):
            return "HTTP 429 — too many notifications were sent from this network. Wait a while and try again."
        case .httpFailure(let status, _):
            return "HTTP \(status) — the server rejected the push."
        }
    }
}

struct WebhookService {
    /// A well-formed ntfy access token: `tk_` plus alphanumerics, no whitespace.
    /// Used only to warn the user; it never blocks a send, because self-hosted setups
    /// may legitimately use another credential form.
    static func looksLikeNtfyToken(_ raw: String) -> Bool {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return true }   // empty is "unset", not "malformed"
        guard token.hasPrefix("tk_") else { return false }
        let body = token.dropFirst(3)
        return !body.isEmpty && body.allSatisfy { $0.isLetter || $0.isNumber }
    }

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

    /// What a log line may say about a URL: scheme and host, never the path or query
    /// (an ntfy topic is the secret) nor any user:password part.
    static func logSafe(url: String) -> String {
        guard let parts = URLComponents(string: url), let scheme = parts.scheme else {
            return "(unparsable URL)"
        }
        return "\(scheme)://\(parts.host ?? "")"
    }

    /// HTTP header values are ASCII. ntfy decodes RFC 2047 encoded words in any header
    /// (`maybeDecodeHeader` on the server; docs.ntfy.sh "Message title"), so a title with
    /// an emoji or an accent is sent as `=?UTF-8?B?<base64>?=`. Plain ASCII is unchanged.
    static func ntfyHeaderValue(_ value: String) -> String {
        guard !value.allSatisfy({ $0.isASCII && !$0.isNewline }) else { return value }
        let oneLine = value.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard !oneLine.allSatisfy(\.isASCII) else { return oneLine }
        return "=?UTF-8?B?\(Data(oneLine.utf8).base64EncodedString())?="
    }

    /// `completion` is optional so the fire-and-forget notification paths are unchanged.
    /// It is called on a background queue; hop to the main actor before touching UI.
    static func sendNtfy(
        urlString: String, bearerToken: String?, title: String, message: String,
        fields: [String: String], completion: ((NtfyOutcome) -> Void)? = nil
    ) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAllowedURL(trimmed), let url = URL(string: trimmed) else {
            // The URL path is the phone-push topic, i.e. the secret: never log it.
            DebugLog.warn("ntfy URL rejected (must be https or localhost): \(logSafe(url: trimmed))")
            completion?(.rejectedURL)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue(ntfyHeaderValue(title), forHTTPHeaderField: "Title")
        let token = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let tokenWasSent = !token.isEmpty
        if tokenWasSent {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let details = fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let body = details.isEmpty ? message : "\(message)\n\n\(details)"
        request.httpBody = body.data(using: .utf8)
        WebhookHTTP.session.dataTask(with: request) { _, response, error in
            let outcome: NtfyOutcome
            if let error {
                DebugLog.warn("ntfy send failed: \(error.localizedDescription)")
                outcome = .transportFailure(error.localizedDescription)
            } else if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
                // Logged with the token-presence bit, because HTTP 403 means
                // "no credentials offered" or "credentials lack rights" depending on it.
                DebugLog.warn("ntfy send HTTP \(code) (token sent: \(tokenWasSent))")
                outcome = .httpFailure(status: code, tokenWasSent: tokenWasSent)
            } else {
                outcome = .sent(status: (response as? HTTPURLResponse)?.statusCode ?? 200)
            }
            completion?(outcome)
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
}
