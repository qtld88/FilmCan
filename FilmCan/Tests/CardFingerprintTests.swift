import XCTest
@testable import FilmCan

/// Field report: one card copied in two runs, as "Untitled" on one drive and
/// "Untitled_01" on the other, showed as two rolls each copied once.
final class CardFingerprintTests: XCTestCase {

    private var root: URL!
    private let mb: Int64 = 1 << 20

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fingerprint-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ rel: String, bytes: Int, modified: Date) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }

    private func clipKey(_ name: String, _ size: Int64, _ t: TimeInterval) -> String {
        CardFingerprint.key(name: name, size: size, modified: Date(timeIntervalSince1970: t))
    }

    private func roll(_ name: String, drive: String, clipKeys: [String]? = nil,
                      files: [CatalogFile] = [], configId: UUID? = nil,
                      project: String = "TLF", date: TimeInterval = 1_000) -> CatalogRoll {
        CatalogRoll(configId: configId, projectName: project, shootDay: "DAY06", rollName: name,
                    mediaKind: .camera, sourceVolumeUUID: "CARD-\(drive)", sourcePath: "/Volumes/Untitled",
                    firstBackedUp: Date(timeIntervalSince1970: date), files: files,
                    copies: [CatalogCopy(destVolumeUUID: drive, destVolumeName: drive,
                                         rollFolderPath: "/Volumes/\(drive)/\(name)",
                                         verified: true, date: Date(timeIntervalSince1970: date))],
                    clipKeys: clipKeys)
    }

    // MARK: - Keys on disk

    func test_keys_skipSmallAndHiddenFiles_ignoreFolders() throws {
        let t = Date(timeIntervalSince1970: 1_731_400_000)
        try write("PRIVATE/M4ROOT/CLIP/C0001.MP4", bytes: 2 * Int(mb), modified: t)
        try write("PRIVATE/M4ROOT/CLIP/C0001M01.XML", bytes: 2_000, modified: t)
        try write(".filmcan/seal.json", bytes: 2 * Int(mb), modified: t)
        let keys = CardFingerprint.keys(forSource: root.path)
        XCTAssertEqual(keys, [clipKey("C0001.MP4", 2 * mb, 1_731_400_000)])

        // The card folder or only its content: same keys.
        XCTAssertEqual(CardFingerprint.keys(forSource: root.appendingPathComponent("PRIVATE").path), keys)
        // A single-file source.
        XCTAssertEqual(CardFingerprint.keys(forSource:
            root.appendingPathComponent("PRIVATE/M4ROOT/CLIP/C0001.MP4").path), keys)
    }

    /// Quick format, then new clips with the same names: no match.
    func test_keys_reformattedCardWithSameClipNames_differs() throws {
        try write("C0001.MP4", bytes: 2 * Int(mb), modified: Date(timeIntervalSince1970: 1_731_400_000))
        let before = CardFingerprint.keys(forSource: root.path)
        try FileManager.default.removeItem(at: root.appendingPathComponent("C0001.MP4"))
        try write("C0001.MP4", bytes: 2 * Int(mb), modified: Date(timeIntervalSince1970: 1_731_500_000))
        XCTAssertNotEqual(CardFingerprint.keys(forSource: root.path), before)
    }

    // MARK: - Catalog

    func test_merge_sameClipsUnderAnotherRollName_countsTwoDrives() {
        let keys = [clipKey("C0001.MP4", 5 * mb, 1), clipKey("C0002.MP4", 7 * mb, 2)]
        var rolls = MediaCatalog.merge(roll("Untitled", drive: "NAV_A", clipKeys: keys), into: [])
        rolls = MediaCatalog.merge(roll("Untitled_01", drive: "NAV_B", clipKeys: keys, date: 2_000), into: rolls)
        XCTAssertEqual(rolls.count, 1)
        XCTAssertEqual(rolls[0].rollName, "Untitled")
        XCTAssertEqual(rolls[0].coverage, .safe(drives: 2))
    }

    func test_merge_reformattedCard_staysSeparate() {
        let old = [clipKey("C0001.MP4", 5 * mb, 1)]
        let new = [clipKey("C0001.MP4", 5 * mb, 99)]
        var rolls = MediaCatalog.merge(roll("Untitled", drive: "NAV_A", clipKeys: old), into: [])
        rolls = MediaCatalog.merge(roll("Untitled_01", drive: "NAV_B", clipKeys: new), into: rolls)
        XCTAssertEqual(rolls.count, 2)
    }

    func test_merge_sameClipsInAnotherProject_staysSeparate() {
        let keys = [clipKey("C0001.MP4", 5 * mb, 1)]
        var rolls = MediaCatalog.merge(roll("Untitled", drive: "NAV_A", clipKeys: keys, project: "TLF"), into: [])
        rolls = MediaCatalog.merge(roll("Untitled", drive: "NAV_B", clipKeys: keys, project: "DCM"), into: rolls)
        XCTAssertEqual(rolls.count, 2)
    }

    /// Rolls saved before clip keys: two large files with the same names and sizes.
    func test_mergingSameCards_foldsLegacySplitRolls_onLoad() {
        let files = [CatalogFile(relPath: "PRIVATE/M4ROOT/CLIP/C0001.MP4", size: 5 * mb),
                     CatalogFile(relPath: "PRIVATE/M4ROOT/CLIP/C0002.MP4", size: 7 * mb),
                     CatalogFile(relPath: "PRIVATE/M4ROOT/CLIP/C0001M01.XML", size: 900)]
        let a = roll("Untitled", drive: "NAV_A", files: files, date: 1_000)
        let b = roll("Untitled_01", drive: "NAV_B", files: files, date: 2_000)
        let other = roll("A002", drive: "NAV_A",
                         files: [CatalogFile(relPath: "C0001.MP4", size: 3 * mb),
                                 CatalogFile(relPath: "C0002.MP4", size: 4 * mb)])
        let folded = MediaCatalog.mergingSameCards([b, other, a])
        XCTAssertEqual(folded.map(\.rollName).sorted(), ["A002", "Untitled"])
        XCTAssertEqual(folded.first { $0.rollName == "Untitled" }?.verifiedDriveCount, 2)
        // A single matching file is not enough for a legacy match.
        let one = [CatalogFile(relPath: "C0001.MP4", size: 5 * mb)]
        XCTAssertEqual(MediaCatalog.mergingSameCards(
            [roll("X", drive: "A", files: one), roll("Y", drive: "B", files: one, date: 2_000)]).count, 2)
    }

    func test_earlierCopies_partialOverlap_andWarningText() {
        let earlier = roll("Untitled", drive: "NAV_A",
                           clipKeys: [clipKey("C0001.MP4", 5 * mb, 1), clipKey("C0002.MP4", 7 * mb, 2)])
        let card = [clipKey("C0001.MP4", 5 * mb, 1), clipKey("C0002.MP4", 7 * mb, 2),
                    clipKey("C0003.MP4", 9 * mb, 3)]
        let hits = MediaCatalog.earlierCopies(ofClipKeys: card, mediaKind: .camera, in: [earlier])
        XCTAssertEqual(hits.map(\.matchingClips), [2])
        XCTAssertEqual(MediaCatalog.earlierCopies(ofClipKeys: card, mediaKind: .sound, in: [earlier]), [])

        let text = EarlierCopyWarning.message(
            for: [.init(plannedName: "Untitled_01", earlier: hits)], formatDate: { _ in "12 Nov 2026" })
        XCTAssertEqual(text, "2 of 3 clips of “Untitled_01” already copied as “Untitled” on NAV_A (12 Nov 2026)."
                       + "\n\nThe folders on your drives will have different names for the same card.")

        // Same name: the normal second-drive run, no warning.
        XCTAssertNil(EarlierCopyWarning.message(
            for: [.init(plannedName: "Untitled", earlier: hits)], formatDate: { _ in "" }))
    }

    func test_catalogJSON_withoutClipKeys_stillDecodes() throws {
        let legacy = """
        [{"configId":null,"copies":[],"files":[],"firstBackedUp":"2026-11-12T10:00:00Z",
          "id":"\(UUID().uuidString)","mediaKind":"camera","projectName":"TLF","rollName":"A001",
          "shootDay":"DAY06","sourcePath":"/Volumes/Untitled","sourceVolumeUUID":null}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rolls = try decoder.decode([CatalogRoll].self, from: Data(legacy.utf8))
        XCTAssertEqual(rolls.count, 1)
        XCTAssertNil(rolls[0].clipKeys)
    }
}
