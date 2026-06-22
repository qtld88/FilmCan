import Foundation

/// Plain snapshot of the user's notification preferences, built from the
/// VM's @AppStorage at call time so notification logic is testable without
/// the property wrapper.
struct NotificationSettings {
    var notifyOnComplete: Bool
    var notifyOnError: Bool
    var ntfyEnabled: Bool
    var ntfyURL: String
    var ntfyTitleTemplate: String
    var ntfyMessageTemplate: String
    var webhookEnabled: Bool
    var webhookURL: String
    var webhookIncludeFullPaths: Bool
}
