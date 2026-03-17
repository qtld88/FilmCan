import Foundation

struct WebhookService {
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
}
