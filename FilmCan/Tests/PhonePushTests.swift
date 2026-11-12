import XCTest
@testable import FilmCan

final class PhonePushTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PhonePushTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Topic

    func testGeneratedTopicCarries128RandomBits() {
        let topic = PhonePush.generateTopic()
        XCTAssertTrue(topic.hasPrefix("filmcan-"))
        let random = topic.dropFirst("filmcan-".count)
        XCTAssertEqual(random.count, 32, "32 hex characters = 128 bits")
        XCTAssertTrue(random.allSatisfy { "0123456789abcdef".contains($0) })
        XCTAssertTrue(PhonePush.isValidTopic(topic))
    }

    func testGeneratedTopicUsesEveryRandomByte() {
        var asked = 0
        let topic = PhonePush.generateTopic { count in
            asked = count
            return (0..<count).map { UInt8($0 * 16 + 1) }
        }
        XCTAssertEqual(asked, 16)
        XCTAssertEqual(topic, "filmcan-01112131415161718191a1b1c1d1e1f1")
    }

    func testTwoGeneratedTopicsDiffer() {
        XCTAssertNotEqual(PhonePush.generateTopic(), PhonePush.generateTopic())
    }

    func testTopicValidation() {
        XCTAssertTrue(PhonePush.isValidTopic("filmcan-abc_DEF-123"))
        XCTAssertFalse(PhonePush.isValidTopic(""))
        XCTAssertFalse(PhonePush.isValidTopic("has space"))
        XCTAssertFalse(PhonePush.isValidTopic("a/b"))
        XCTAssertFalse(PhonePush.isValidTopic("a#b"))
        XCTAssertFalse(PhonePush.isValidTopic("é"))
        XCTAssertFalse(PhonePush.isValidTopic(String(repeating: "a", count: 65)))
        XCTAssertTrue(PhonePush.isValidTopic(String(repeating: "a", count: 64)))
    }

    /// The topic must reach the help page in the fragment only: browsers never send it.
    func testSetupURLKeepsTopicInFragmentOnly() throws {
        let topic = PhonePush.generateTopic()
        let url = try XCTUnwrap(URL(string: PhonePush.setupURL(topic)))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "www.filmcan.eu")
        XCTAssertEqual(url.fragment, topic)
        XCTAssertNil(url.query)
        XCTAssertFalse(url.path.contains(topic))
    }

    func testTopicURLIsOnThePublicServer() {
        XCTAssertEqual(PhonePush.topicURL("filmcan-abc"), "https://ntfy.sh/filmcan-abc")
        XCTAssertTrue(WebhookService.isAllowedURL(PhonePush.topicURL(PhonePush.generateTopic())))
    }

    // MARK: - Mode

    func testNothingConfiguredMeansSimple() {
        XCTAssertEqual(PhonePush.mode(storedUseCustom: nil, customURL: ""), .simple)
        XCTAssertEqual(PhonePush.mode(storedUseCustom: nil, customURL: "  \n"), .simple)
    }

    /// Someone who filled a topic URL before this feature keeps using it, untouched.
    func testExistingTopicURLMeansCustom() {
        XCTAssertEqual(PhonePush.mode(storedUseCustom: nil, customURL: "https://ntfy.example.org/rushes"), .custom)
    }

    func testExplicitChoiceWins() {
        XCTAssertEqual(PhonePush.mode(storedUseCustom: false, customURL: "https://ntfy.example.org/rushes"), .simple)
        XCTAssertEqual(PhonePush.mode(storedUseCustom: true, customURL: ""), .custom)
    }

    // MARK: - Target

    func testSimpleTargetNeverSendsTheToken() {
        let target = PhonePush.target(mode: .simple, topic: "filmcan-abc", customURL: "https://ntfy.example.org/x")
        XCTAssertEqual(target, PhonePush.Target(url: "https://ntfy.sh/filmcan-abc", sendsToken: false))
    }

    func testSimpleTargetWithoutTopicIsNil() {
        XCTAssertNil(PhonePush.target(mode: .simple, topic: "", customURL: "https://ntfy.example.org/x"))
        XCTAssertNil(PhonePush.target(mode: .simple, topic: "bad topic", customURL: ""))
    }

    func testCustomTargetIsTheUsersURLWithToken() {
        let target = PhonePush.target(mode: .custom, topic: "filmcan-abc", customURL: " https://ntfy.example.org/x ")
        XCTAssertEqual(target, PhonePush.Target(url: "https://ntfy.example.org/x", sendsToken: true))
        XCTAssertNil(PhonePush.target(mode: .custom, topic: "filmcan-abc", customURL: ""))
    }

    // MARK: - Stored preferences

    /// Preferences written by a version without this feature: only `ntfyURL`.
    func testOldPreferencesKeepTheirTarget() {
        defaults.set(true, forKey: "ntfyEnabled")
        defaults.set("https://ntfy.example.org/rushes", forKey: "ntfyURL")
        XCTAssertEqual(PhonePush.mode(defaults: defaults), .custom)
        XCTAssertEqual(
            PhonePush.target(defaults: defaults),
            PhonePush.Target(url: "https://ntfy.example.org/rushes", sendsToken: true))
        XCTAssertNil(defaults.string(forKey: PhonePush.DefaultsKey.topic), "reading must not create a topic")
    }

    func testFreshPreferencesHaveNoTargetUntilATopicExists() {
        XCTAssertEqual(PhonePush.mode(defaults: defaults), .simple)
        XCTAssertNil(PhonePush.target(defaults: defaults))
        let topic = PhonePush.ensureTopic(defaults: defaults)
        XCTAssertEqual(PhonePush.target(defaults: defaults)?.url, "https://ntfy.sh/\(topic)")
        XCTAssertEqual(PhonePush.target(defaults: defaults)?.sendsToken, false)
    }

    func testEnsureTopicIsStableAndRenewChangesIt() {
        let first = PhonePush.ensureTopic(defaults: defaults)
        XCTAssertEqual(PhonePush.ensureTopic(defaults: defaults), first)
        let second = PhonePush.renewTopic(defaults: defaults)
        XCTAssertNotEqual(second, first)
        XCTAssertEqual(defaults.string(forKey: PhonePush.DefaultsKey.topic), second)
    }

    func testEnsureTopicReplacesAMalformedStoredValue() {
        defaults.set("not a topic!", forKey: PhonePush.DefaultsKey.topic)
        XCTAssertTrue(PhonePush.isValidTopic(PhonePush.ensureTopic(defaults: defaults)))
    }

    // MARK: - Settings snapshot and QR

    func testNotificationSettingsSendTokenByDefault() {
        let settings = NotificationSettings(
            notifyOnComplete: true, notifyOnError: true,
            ntfyEnabled: true, ntfyURL: "https://ntfy.example.org/x",
            ntfyTitleTemplate: "", ntfyMessageTemplate: "",
            webhookEnabled: false, webhookURL: "", webhookIncludeFullPaths: false)
        XCTAssertTrue(settings.ntfySendsToken)
    }

    func testQRCodeIsRenderedSquareAndLargeEnough() throws {
        let image = try XCTUnwrap(QRCodeImage.image(for: PhonePush.setupURL(PhonePush.generateTopic()), side: 320))
        XCTAssertEqual(image.size.width, image.size.height)
        XCTAssertGreaterThan(image.size.width, 100)
        XCTAssertLessThanOrEqual(image.size.width, 320)
    }

    func testQRCodeForEmptyTextIsNil() {
        XCTAssertNil(QRCodeImage.image(for: ""))
    }

    func testRateLimitAnswerIsExplained() {
        XCTAssertTrue(NtfyOutcome.httpFailure(status: 429, tokenWasSent: false).userMessage.contains("429"))
        XCTAssertTrue(NtfyOutcome.httpFailure(status: 429, tokenWasSent: false).userMessage.contains("Wait"))
    }
}
