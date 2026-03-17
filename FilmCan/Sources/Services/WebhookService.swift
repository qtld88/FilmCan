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
}
