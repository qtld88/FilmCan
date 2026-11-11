import Foundation
import Security

/// Phone notifications without an account: FilmCan invents a long random ntfy
/// topic, the phone subscribes to it by scanning a QR code. The topic is a weak
/// secret kept in the preferences (not the keychain), so it survives app updates.
///
/// Pure logic only; the settings view and `TransferViewModel` read it.
enum PhonePush {
    static let server = "https://ntfy.sh"
    /// Static help page. The topic travels in the URL fragment, which browsers never
    /// send to the server, so the site never sees it.
    static let setupPage = "https://www.filmcan.eu/phone/"
    static let topicPrefix = "filmcan-"

    enum DefaultsKey {
        /// The generated topic (simple mode).
        static let topic = "phonePushTopic"
        /// `true` = the user's own topic URL and access token (the pre-existing form).
        /// Absent = decided by `mode(storedUseCustom:customURL:)`.
        static let useCustomServer = "ntfyUseCustomServer"
    }

    enum Mode: Equatable {
        /// Generated topic on the public server, no token.
        case simple
        /// The user's own topic URL, optional access token.
        case custom
    }

    /// Where a push goes, and whether the keychain token goes with it.
    struct Target: Equatable {
        let url: String
        let sendsToken: Bool
    }

    // MARK: - Topic

    /// `filmcan-` + 32 lowercase hex characters = 128 random bits.
    static func generateTopic(randomBytes: (Int) -> [UInt8] = secureRandomBytes) -> String {
        let bytes = randomBytes(16)
        return topicPrefix + bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func secureRandomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return bytes
    }

    /// ntfy topic names: letters, digits, `-` and `_`, 1 to 64 characters.
    static func isValidTopic(_ topic: String) -> Bool {
        guard (1...64).contains(topic.utf8.count) else { return false }
        return topic.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122) || byte == 45 || byte == 95
        }
    }

    static func topicURL(_ topic: String) -> String { "\(server)/\(topic)" }

    /// What the QR code encodes.
    static func setupURL(_ topic: String) -> String { "\(setupPage)#\(topic)" }

    // MARK: - Mode

    /// An explicit choice wins. Without one, someone who already filled a topic URL
    /// keeps the form they configured; everyone else gets the QR code.
    static func mode(storedUseCustom: Bool?, customURL: String) -> Mode {
        if let storedUseCustom { return storedUseCustom ? .custom : .simple }
        return customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .simple : .custom
    }

    static func mode(defaults: UserDefaults = .standard) -> Mode {
        mode(
            storedUseCustom: defaults.object(forKey: DefaultsKey.useCustomServer) as? Bool,
            customURL: defaults.string(forKey: "ntfyURL") ?? "")
    }

    /// `nil` when there is nowhere to send (simple mode before a topic exists, or an
    /// empty custom URL). The token never accompanies a generated topic.
    static func target(mode: Mode, topic: String, customURL: String) -> Target? {
        switch mode {
        case .simple:
            guard isValidTopic(topic) else { return nil }
            return Target(url: topicURL(topic), sendsToken: false)
        case .custom:
            let trimmed = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Target(url: trimmed, sendsToken: true)
        }
    }

    static func target(defaults: UserDefaults = .standard) -> Target? {
        target(
            mode: mode(defaults: defaults),
            topic: defaults.string(forKey: DefaultsKey.topic) ?? "",
            customURL: defaults.string(forKey: "ntfyURL") ?? "")
    }

    /// Returns the stored topic, creating and storing one first when missing or malformed.
    @discardableResult
    static func ensureTopic(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: DefaultsKey.topic), isValidTopic(existing) {
            return existing
        }
        return renewTopic(defaults: defaults)
    }

    /// Replaces the topic. Phones subscribed to the old one stop receiving.
    @discardableResult
    static func renewTopic(defaults: UserDefaults = .standard) -> String {
        let topic = generateTopic()
        defaults.set(topic, forKey: DefaultsKey.topic)
        return topic
    }
}
