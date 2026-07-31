import XCTest
@testable import FilmCan

final class SecretsNetworkTests: XCTestCase {
    private let testService = "com.filmcan.app.tests"

    func test_keychain_roundTrip() {
        let store = KeychainStore(service: testService)
        store.delete("k1")
        XCTAssertNil(store.get("k1"))
        store.set("secret-value", for: "k1")
        XCTAssertEqual(store.get("k1"), "secret-value")
        store.set("updated", for: "k1")
        XCTAssertEqual(store.get("k1"), "updated")
        store.delete("k1")
        XCTAssertNil(store.get("k1"))
    }

    func testKeychainSetReturnsSuccessAndRoundTrips() {
        let store = KeychainStore(service: "com.filmcan.test.\(UUID().uuidString)")
        let account = "webhookToken"
        defer { store.delete(account) }
        XCTAssertTrue(store.set("s3cr3t", for: account))
        XCTAssertEqual(store.get(account), "s3cr3t")
        XCTAssertTrue(store.set("rotated", for: account))   // overwrite path
        XCTAssertEqual(store.get(account), "rotated")
    }

    func test_webhook_validatesHttpsOnly() {
        XCTAssertTrue(WebhookService.isAllowedURL("https://example.com/hook"))
        XCTAssertFalse(WebhookService.isAllowedURL("http://example.com/hook"))
        XCTAssertFalse(WebhookService.isAllowedURL("ftp://example.com"))
        XCTAssertFalse(WebhookService.isAllowedURL(""))
        XCTAssertTrue(WebhookService.isAllowedURL("http://localhost:8080/hook"))
        XCTAssertTrue(WebhookService.isAllowedURL("http://127.0.0.1:8080/hook"))
    }

    func test_webhook_redirectPolicy_blocksCrossHostAndDowngrade() {
        // Same host, still https → follow (token stays with the approved host).
        XCTAssertTrue(WebhookService.shouldFollowRedirect(
            originalHost: "ntfy.example.com", to: "https://ntfy.example.com/topic"))
        // Different host → block (would leak the bearer token).
        XCTAssertFalse(WebhookService.shouldFollowRedirect(
            originalHost: "ntfy.example.com", to: "https://evil.example.net/topic"))
        // Same host but https→http downgrade → block (cleartext token).
        XCTAssertFalse(WebhookService.shouldFollowRedirect(
            originalHost: "ntfy.example.com", to: "http://ntfy.example.com/topic"))
        // Localhost http stays allowed on the same host.
        XCTAssertTrue(WebhookService.shouldFollowRedirect(
            originalHost: "localhost", to: "http://localhost:8080/topic"))
        // Missing original host → block.
        XCTAssertFalse(WebhookService.shouldFollowRedirect(
            originalHost: nil, to: "https://ntfy.example.com/topic"))
    }

    func test_webhook_masksPathsByDefault() {
        let full = "/Volumes/CARD/A001/clip.mov"
        XCTAssertEqual(WebhookService.maskedField(path: full, includeFull: false), "clip.mov")
        XCTAssertEqual(WebhookService.maskedField(path: full, includeFull: true), full)
    }

    // MARK: - SecretsMigration

    /// Fresh, isolated defaults + keychain namespace so a test never touches real secrets.
    private func migrationFixture() -> (UserDefaults, KeychainStore, String) {
        let suite = "com.filmcan.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = KeychainStore(service: suite)
        return (defaults, store, suite)
    }

    private func cleanUp(_ defaults: UserDefaults, _ store: KeychainStore, _ suite: String) {
        for a in SecretsMigration.accounts { store.delete(a) }
        defaults.removePersistentDomain(forName: suite)
    }

    func test_secretsMigration_movesLegacyValueThenErasesPlaintext() {
        let (defaults, store, suite) = migrationFixture()
        defer { cleanUp(defaults, store, suite) }

        defaults.set("tk_legacyvalue", forKey: "ntfyBearerToken")
        let moved = SecretsMigration.run(defaults: defaults, store: store)

        XCTAssertEqual(moved, ["ntfyBearerToken"])
        XCTAssertEqual(store.get("ntfyBearerToken"), "tk_legacyvalue")
        // The whole point: the plaintext copy must be gone afterwards.
        XCTAssertNil(defaults.string(forKey: "ntfyBearerToken"))
    }

    func test_secretsMigration_doesNotClobberValueUserAlreadyReEntered() {
        let (defaults, store, suite) = migrationFixture()
        defer { cleanUp(defaults, store, suite) }

        XCTAssertTrue(store.set("tk_current", for: "ntfyBearerToken"))
        defaults.set("tk_stale", forKey: "ntfyBearerToken")

        XCTAssertEqual(SecretsMigration.run(defaults: defaults, store: store), [])
        XCTAssertEqual(store.get("ntfyBearerToken"), "tk_current")
        // Stale plaintext is still cleared even though nothing was migrated.
        XCTAssertNil(defaults.string(forKey: "ntfyBearerToken"))
    }

    func test_secretsMigration_isIdempotentAndCoversEveryAccount() {
        let (defaults, store, suite) = migrationFixture()
        defer { cleanUp(defaults, store, suite) }

        for account in SecretsMigration.accounts {
            defaults.set("legacy-\(account)", forKey: account)
        }
        XCTAssertEqual(Set(SecretsMigration.run(defaults: defaults, store: store)),
                       Set(SecretsMigration.accounts))
        // Second pass has nothing left to do.
        XCTAssertEqual(SecretsMigration.run(defaults: defaults, store: store), [])
        for account in SecretsMigration.accounts {
            XCTAssertEqual(store.get(account), "legacy-\(account)")
        }
    }

    func test_secretsMigration_ignoresBlankLegacyValueButStillClearsIt() {
        let (defaults, store, suite) = migrationFixture()
        defer { cleanUp(defaults, store, suite) }

        defaults.set("   ", forKey: "webhookSecret")
        XCTAssertEqual(SecretsMigration.run(defaults: defaults, store: store), [])
        XCTAssertNil(store.get("webhookSecret"))
        XCTAssertNil(defaults.string(forKey: "webhookSecret"))
    }

    // MARK: - ntfy token shape + outcome messages

    func test_ntfyTokenShape_flagsPastedProse() {
        XCTAssertTrue(WebhookService.looksLikeNtfyToken("tk_qx2uq0hdk2txprezzmqbhdaaf79ej"))
        XCTAssertTrue(WebhookService.looksLikeNtfyToken("  tk_abc123  "))   // trimmed
        XCTAssertTrue(WebhookService.looksLikeNtfyToken(""))                // unset, not malformed
        // The real-world failure: a sentence containing a domain pasted into the field.
        XCTAssertFalse(WebhookService.looksLikeNtfyToken("generate access www.example.com someTokenHere"))
        XCTAssertFalse(WebhookService.looksLikeNtfyToken("tk_has space"))
        XCTAssertFalse(WebhookService.looksLikeNtfyToken("nottk_prefixed"))
        XCTAssertFalse(WebhookService.looksLikeNtfyToken("tk_"))
    }

    func test_ntfyOutcome_401And403CarryDifferentAdvice() {
        XCTAssertTrue(NtfyOutcome.sent(status: 200).isSuccess)
        XCTAssertFalse(NtfyOutcome.httpFailure(status: 401, tokenWasSent: true).isSuccess)

        XCTAssertTrue(NtfyOutcome.httpFailure(status: 401, tokenWasSent: true)
            .userMessage.contains("tk_"))
        // 403 splits on whether credentials were offered at all.
        XCTAssertTrue(NtfyOutcome.httpFailure(status: 403, tokenWasSent: false)
            .userMessage.contains("none is set"))
        XCTAssertTrue(NtfyOutcome.httpFailure(status: 403, tokenWasSent: true)
            .userMessage.contains("not allowed to publish"))
        XCTAssertNotEqual(
            NtfyOutcome.httpFailure(status: 403, tokenWasSent: true).userMessage,
            NtfyOutcome.httpFailure(status: 403, tokenWasSent: false).userMessage)
    }
}
