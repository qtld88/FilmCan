import Foundation

/// Moves secrets written by builds before `5856ad4` out of `UserDefaults` and into the
/// Keychain, then deletes the plaintext copy.
///
/// That commit switched the secret fields from `@AppStorage` to Keychain-backed state
/// but shipped no migration, on the assumption that no install had secrets yet. The
/// assumption was wrong. On an upgraded install the effect is silent and twofold: the
/// app reads only the Keychain, finds nothing, and sends unauthenticated requests that
/// the server rejects — while the old value stays readable in the preferences plist.
enum SecretsMigration {
    /// Keychain account names that older builds also wrote to `UserDefaults`.
    static let accounts = ["ntfyBearerToken", "webhookHeaders", "webhookSecret"]

    /// Idempotent: after the first successful pass the legacy keys are gone, so later
    /// launches do nothing. Returns the accounts actually moved (for tests/logging).
    @discardableResult
    static func run(
        defaults: UserDefaults = .standard,
        store: KeychainStore = KeychainStore()
    ) -> [String] {
        var migrated: [String] = []
        for account in accounts {
            guard let legacy = defaults.string(forKey: account) else { continue }
            let value = legacy.trimmingCharacters(in: .whitespacesAndNewlines)

            // Only fill an empty Keychain slot — never clobber a value the user has
            // since re-entered, which is necessarily newer than the legacy copy.
            if !value.isEmpty, store.get(account) == nil {
                guard store.set(value, for: account) else {
                    // Dropping the plaintext now would lose the secret outright, which
                    // is worse than the exposure. Leave it and retry next launch.
                    DebugLog.warn("Secret migration failed for \(account); plaintext left in place")
                    continue
                }
                migrated.append(account)
            }
            defaults.removeObject(forKey: account)
        }
        if !migrated.isEmpty {
            DebugLog.info("Migrated secrets to Keychain: \(migrated.joined(separator: ", "))")
        }
        return migrated
    }
}
