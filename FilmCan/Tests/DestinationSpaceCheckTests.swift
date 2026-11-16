import XCTest
@testable import FilmCan

final class DestinationSpaceCheckTests: XCTestCase {

    private let gb: Int64 = 1_000_000_000

    private func probe(_ table: [String: DestinationSpaceCheck.Probe]) -> (String) -> DestinationSpaceCheck.Probe? {
        { table[$0] }
    }

    /// Field report: "Insufficient Space … NAV_B, TLF" with NAV_B unplugged and TLF
    /// roomy. An unplugged drive is not a shortfall; a roomy one is not either.
    func test_unpluggedDrive_andRoomyDrive_noWarning() {
        let result = DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/NAV_B", "/Volumes/TLF"],
            requiredBytes: 72 * gb,
            probe: probe(["/Volumes/TLF": .init(volumeKey: "/Volumes/TLF",
                                                available: 1_290 * gb, writableNow: 1_290 * gb)]))
        XCTAssertEqual(result, [])
    }

    func test_fullDrive_isReported() {
        let result = DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/SMALL"],
            requiredBytes: 72 * gb,
            probe: probe(["/Volumes/SMALL": .init(volumeKey: "/Volumes/SMALL",
                                                  available: 50 * gb, writableNow: 40 * gb)]))
        XCTAssertEqual(result.map(\.destination), ["/Volumes/SMALL"])
        XCTAssertEqual(result.first?.writableNow, 40 * gb)
    }

    /// Two destinations on one drive each get the full backup: their needs add up.
    func test_twoPlacesOnOneDrive_needsAddUp() {
        let drive = DestinationSpaceCheck.Probe(volumeKey: "/Volumes/NAV_B",
                                                available: 100 * gb, writableNow: 100 * gb)
        let result = DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/NAV_B", "/Volumes/NAV_B/TLF"],
            requiredBytes: 72 * gb,
            probe: probe(["/Volumes/NAV_B": drive, "/Volumes/NAV_B/TLF": drive]))
        XCTAssertEqual(result.map(\.destination), ["/Volumes/NAV_B", "/Volumes/NAV_B/TLF"])
        XCTAssertEqual(result.first?.needed, 144 * gb)

        let roomy = DestinationSpaceCheck.Probe(volumeKey: "/Volumes/NAV_B",
                                                available: 1_290 * gb, writableNow: 1_290 * gb)
        XCTAssertEqual(DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/NAV_B", "/Volumes/NAV_B/TLF"],
            requiredBytes: 72 * gb,
            probe: probe(["/Volumes/NAV_B": roomy, "/Volumes/NAV_B/TLF": roomy])), [])
    }

    func test_unknownFreeSpace_orNothingToCopy_noWarning() {
        let unknown = DestinationSpaceCheck.Probe(volumeKey: "/Volumes/X", available: nil, writableNow: nil)
        XCTAssertEqual(DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/X"], requiredBytes: 72 * gb,
            probe: probe(["/Volumes/X": unknown])), [])
        let full = DestinationSpaceCheck.Probe(volumeKey: "/Volumes/X", available: 1, writableNow: 1)
        XCTAssertEqual(DestinationSpaceCheck.shortfalls(
            destinations: ["/Volumes/X"], requiredBytes: 0,
            probe: probe(["/Volumes/X": full])), [])
    }

    func test_existingFolder_climbsWithinDrive_neverToStartupDisk() {
        let existing: Set<String> = ["/", "/Volumes", "/Volumes/NAV_B", "/Users/me"]
        let exists: (String) -> Bool = { existing.contains($0) }
        XCTAssertEqual(DestinationSpaceCheck.existingFolder(for: "/Volumes/NAV_B/TLF", fileExists: exists),
                       "/Volumes/NAV_B")
        XCTAssertEqual(DestinationSpaceCheck.existingFolder(for: "/Volumes/NAV_B", fileExists: exists),
                       "/Volumes/NAV_B")
        XCTAssertNil(DestinationSpaceCheck.existingFolder(for: "/Volumes/GONE/TLF", fileExists: exists))
        XCTAssertNil(DestinationSpaceCheck.existingFolder(for: "/Volumes/GONE", fileExists: exists))
        XCTAssertEqual(DestinationSpaceCheck.existingFolder(for: "/Users/me/Backups/New", fileExists: exists),
                       "/Users/me")
    }

    func test_liveProbe_realTempFolder_andMissingVolume() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spacecheck-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let here = try XCTUnwrap(DestinationSpaceCheck.liveProbe(dir.path))
        let notYetCreated = try XCTUnwrap(DestinationSpaceCheck.liveProbe(dir.appendingPathComponent("TLF").path))
        XCTAssertEqual(here.volumeKey, notYetCreated.volumeKey)
        XCTAssertNotNil(here.available ?? here.writableNow)

        XCTAssertNil(DestinationSpaceCheck.liveProbe("/Volumes/FilmCanNoSuchDrive-\(UUID().uuidString)/TLF"))
    }

    func test_placesOnDriveText() {
        XCTAssertEqual(DestinationListView.placesOnDriveText(included: 2, total: 2),
                       "Copies to 2 places on this drive — each gets the full backup")
        XCTAssertEqual(DestinationListView.placesOnDriveText(included: 1, total: 2),
                       "Copies to 1 of 2 places on this drive")
        XCTAssertEqual(DestinationListView.placesOnDriveText(included: 0, total: 2),
                       "2 places on this drive, none checked")
    }
}
