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

    func test_webhook_masksPathsByDefault() {
        let full = "/Volumes/CARD/A001/clip.mov"
        XCTAssertEqual(WebhookService.maskedField(path: full, includeFull: false), "clip.mov")
        XCTAssertEqual(WebhookService.maskedField(path: full, includeFull: true), full)
    }
}
