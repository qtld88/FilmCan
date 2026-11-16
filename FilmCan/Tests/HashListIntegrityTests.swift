import XCTest
@testable import FilmCan

/// Hash lists are correct, follow ASC MHL v2.0, and survive a damaged or foreign
/// manifest. Real files in temp folders, no mocks.
final class HashListIntegrityTests: XCTestCase {

    private var tmp: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // realpath: the enumerator reports /private/var paths, not the /var symlink.
        let raw = fm.temporaryDirectory.appendingPathComponent("hashlists-\(UUID().uuidString)")
        try fm.createDirectory(at: raw, withIntermediateDirectories: true)
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        tmp = realpath(raw.path, &buffer) != nil ? URL(fileURLWithPath: String(cString: buffer)) : raw
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: tmp)
    }

    // MARK: Helpers

    private func randomData(_ n: Int) -> Data {
        Data((0..<n).map { _ in UInt8.random(in: 0...255) })
    }

    private func dir(_ rel: String) throws -> URL {
        let url = tmp.appendingPathComponent(rel)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ data: Data, _ url: URL) throws -> Data {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return data
    }

    private func config(sources: [URL], dests: [URL]) -> FanOutCopier.Configuration {
        FanOutCopier.Configuration(
            sources: sources.map(\.path),
            destinations: dests.map {
                DestWriter.Config(destPath: $0.path, displayName: $0.lastPathComponent,
                                  verifyMode: .fast, requiresFullFsync: false, chunkSize: 32768)
            },
            verifyMode: .fast, mhlBasePath: nil, dryRun: false, progressHandler: nil)
    }

    private func mhlFiles(_ ascDir: URL) -> [URL] {
        ASCMHLChain.manifestFilesOnDisk(ascmhlDir: ascDir)
            .sorted { $0.seq < $1.seq }.map { $0.url }
    }

    private func latestManifestXML(_ ascDir: URL) throws -> String {
        let name = try XCTUnwrap(ASCMHLChain.latestManifestFileName(ascmhlDir: ascDir))
        return try String(contentsOf: ascDir.appendingPathComponent(name), encoding: .utf8)
    }

    private func manifest(_ hashes: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <hashlist version="2.0" xmlns="urn:ASC:MHL:v2.0">
          <hashes>
        \(hashes)
          </hashes>
        </hashlist>
        """
    }

    // MARK: 1. Simple hash list reads back what it wrote

    func test_simpleHashList_roundTripsNameAndMtime() async throws {
        let w = try SimpleMHLWriter(destRoot: tmp.path, rollName: "R")
        try await w.append(relPath: "A \"1\" & co.mov", size: 5, hash: "abc", mtime: 17)
        try await w.append(relPath: "B.mov", size: 5, hash: "def", mtime: nil)
        try await w.seal()

        let entries = try SimpleMHLReader.read(url: URL(fileURLWithPath: w.manifestPath))
        XCTAssertEqual(entries.map(\.relPath), ["A \"1\" & co.mov", "B.mov"])
        XCTAssertEqual(entries.map(\.hash), ["abc", "def"])
        XCTAssertEqual(entries.map(\.mtime), [17, nil])
    }

    /// The engine always records an mtime, so before the reader fix a second run
    /// found nothing in a simple hash list and copied everything again.
    func test_simpleHashList_secondRunSkipsRecordedClips() async throws {
        let card = try dir("CARD")
        let dest = try dir("dest")
        try write(randomData(4096), card.appendingPathComponent("C0001.MP4"))
        try write(randomData(4096), card.appendingPathComponent("C0002.MP4"))
        var cfg = config(sources: [card], dests: [dest])
        cfg.hashListStyle = .simpleHidden

        let first = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(first.first?.success, true)
        let second = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(second.first?.success, true)
        XCTAssertEqual(second.first?.filesSkipped, 2)
        XCTAssertEqual(second.first?.filesTransferred, 0)
    }

    // MARK: 2. ASC MHL conformance

    func test_ascMHL_lastModificationDate_isWrittenAsISO8601() async throws {
        let asc = tmp.appendingPathComponent("ascmhl")
        let w = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        try await w.append(relPath: "a.bin", size: 1, hash: "aa", mtime: 1_700_000_000)
        try await w.seal()

        let xml = try String(contentsOfFile: w.manifestPath, encoding: .utf8)
        XCTAssertTrue(xml.contains(#"lastmodificationdate="2023-11-14T22:13:20+00:00""#), xml)
        let entries = try ASCMHLReader.read(url: URL(fileURLWithPath: w.manifestPath))
        XCTAssertEqual(entries.first?.mtime, 1_700_000_000)
    }

    /// Manifests written before the fix carry an integer; other tools write dates
    /// with `Z` or fractional seconds. All read back to the same second.
    func test_ascMHLReader_readsEveryLastModificationDateForm() throws {
        let url = tmp.appendingPathComponent("0001_R_x.mhl")
        try manifest("""
            <hash><path size="1" lastmodificationdate="1700000000">int.bin</path><xxh128>01</xxh128></hash>
            <hash><path size="1" lastmodificationdate="2023-11-14T22:13:20+00:00">offset.bin</path><xxh128>02</xxh128></hash>
            <hash><path size="1" lastmodificationdate="2023-11-14T22:13:20Z">zulu.bin</path><xxh128>03</xxh128></hash>
            <hash><path size="1" lastmodificationdate="2023-11-14T23:13:20.250+01:00">frac.bin</path><xxh128>04</xxh128></hash>
            """).write(to: url, atomically: true, encoding: .utf8)
        let entries = try ASCMHLReader.read(url: url)
        XCTAssertEqual(entries.map(\.mtime), Array(repeating: 1_700_000_000, count: 4))
    }

    /// A clip carried over from an earlier generation was not hashed again: it keeps
    /// the hashdate it was hashed on. Only the new clip gets this run's date.
    func test_carriedEntry_keepsItsOriginalHashDate() async throws {
        let card = try dir("CARD")
        let dest = try dir("dest")
        let a = card.appendingPathComponent("A.MOV")
        try write(randomData(4096), a)
        let cfg = config(sources: [card], dests: [dest])
        _ = try await FanOutCopier(config: cfg).run()

        let asc = dest.appendingPathComponent("CARD/ascmhl")
        let gen1 = try XCTUnwrap(mhlFiles(asc).first)
        let old = "2020-01-01T00:00:00+00:00"
        var xml = try String(contentsOf: gen1, encoding: .utf8)
        xml = xml.replacingOccurrences(
            of: #"hashdate="[^"]*""#, with: "hashdate=\"\(old)\"", options: .regularExpression)
        try xml.write(to: gen1, atomically: true, encoding: .utf8)

        try write(randomData(4096), card.appendingPathComponent("B.MOV"))
        let second = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(second.first?.success, true)
        XCTAssertEqual(mhlFiles(asc).count, 2)

        let gen2 = try latestManifestXML(asc)
        let hexA = try XCTUnwrap(Hashing.hash(for: a, algorithm: .xxh128))
        XCTAssertTrue(gen2.lowercased().contains("hashdate=\"\(old)\">\(hexA)<".lowercased()), gen2)
        let dated = gen2.components(separatedBy: "hashdate=\"\(old)\"").count - 1
        XCTAssertEqual(dated, 1, "only the carried clip keeps the old date:\n\(gen2)")
    }

    /// A cancelled run leaves a partial generation outside the chain. The next
    /// complete run takes its number and replaces it: no hole in the chain, and no
    /// stray manifest the reference tool would load as a generation.
    func test_partialThenComplete_leavesNoHoleInTheChain() async throws {
        let asc = tmp.appendingPathComponent("ascmhl")
        let w1 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        try await w1.append(relPath: "a.bin", size: 1, hash: "aa", mtime: nil)
        try await w1.seal()

        let w2 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        await w2.seed([MHLEntry(relPath: "a.bin", size: 1, hash: "aa", mtime: nil)])
        try await w2.append(relPath: "b.bin", size: 1, hash: "bb", mtime: nil)
        try await w2.finalizeAsPartial(reason: "cancelled")
        XCTAssertEqual(w2.sequence, 2)

        let w3 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        XCTAssertEqual(w3.sequence, 2, "the partial generation's number is reused")
        let carried = try ASCMHLReader.read(url: URL(fileURLWithPath: w2.manifestPath))
        await w3.seed(carried.map { MHLEntry(relPath: $0.relPath, size: $0.size ?? 0, hash: $0.hash, mtime: $0.mtime) })
        try await w3.append(relPath: "c.bin", size: 1, hash: "cc", mtime: nil)
        try await w3.seal()

        XCTAssertEqual(ASCMHLChain.read(ascmhlDir: asc).map(\.seq), [1, 2])
        XCTAssertEqual(mhlFiles(asc).map(\.lastPathComponent),
                       ASCMHLChain.read(ascmhlDir: asc).map(\.path),
                       "every manifest on disk is in the chain")
        let names = try ASCMHLReader.read(url: URL(fileURLWithPath: w3.manifestPath)).map(\.relPath)
        XCTAssertEqual(Set(names), ["a.bin", "b.bin", "c.bin"])
    }

    /// A manifest FilmCan did not write as partial is never removed to close a gap.
    func test_foreignUnchainedManifest_isKept() async throws {
        let asc = tmp.appendingPathComponent("ascmhl")
        let w1 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        try await w1.append(relPath: "a.bin", size: 1, hash: "aa", mtime: nil)
        try await w1.seal()
        let foreign = asc.appendingPathComponent("0002_R_2026-01-01_000000Z.mhl")
        try manifest(#"<hash><path size="1">z.bin</path><xxh128>zz</xxh128></hash>"#)
            .write(to: foreign, atomically: true, encoding: .utf8)

        let w2 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        XCTAssertEqual(w2.sequence, 3)
        try await w2.append(relPath: "b.bin", size: 1, hash: "bb", mtime: nil)
        try await w2.seal()
        XCTAssertTrue(fm.fileExists(atPath: foreign.path))
    }

    // MARK: 3. Manifest from another tool

    /// A <hash> block may carry several algorithms: xxh128 is the one FilmCan uses.
    func test_reader_prefersXXH128_whenABlockHasSeveralHashes() throws {
        let url = tmp.appendingPathComponent("0001_R_x.mhl")
        try manifest("""
            <hash><path size="1">a.bin</path>
              <xxh128 action="original">AAAA</xxh128>
              <md5 action="original">MMMM</md5>
            </hash>
            """).write(to: url, atomically: true, encoding: .utf8)
        let entry = try XCTUnwrap(try ASCMHLReader.read(url: url).first)
        XCTAssertEqual(entry.hash, "AAAA")
        XCTAssertEqual(entry.algorithm, "xxh128")
    }

    /// An md5 entry proves nothing to an xxh128 resume: the clip is not skipped on
    /// it, and its value is never written back under an xxh128 tag. An entry carried
    /// forward keeps the algorithm it was recorded with.
    func test_foreignAlgorithmEntries_doNotSkip_andKeepTheirAlgorithm() async throws {
        let card = try dir("CARD")
        let dest = try dir("dest")
        let clip = card.appendingPathComponent("CLIP.MOV")
        try write(randomData(4096), clip)
        let cfg = config(sources: [card], dests: [dest])
        _ = try await FanOutCopier(config: cfg).run()

        let asc = dest.appendingPathComponent("CARD/ascmhl")
        let gen1 = try XCTUnwrap(mhlFiles(asc).first)
        try write(Data("old".utf8), dest.appendingPathComponent("CARD/OLD.MOV"))
        let bogus = String(repeating: "0", count: 32)
        try manifest("""
            <hash><path size="4096">CLIP.MOV</path><md5 action="original" hashdate="2020-01-01T00:00:00+00:00">\(bogus)</md5></hash>
            <hash><path size="3">OLD.MOV</path><md5 action="original" hashdate="2020-01-01T00:00:00+00:00">\(String(repeating: "1", count: 32))</md5></hash>
            """).write(to: gen1, atomically: true, encoding: .utf8)

        let second = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(second.first?.success, true)
        XCTAssertEqual(second.first?.filesSkipped, 0, "an md5 entry is no proof for an xxh128 resume")

        let entries = try ASCMHLReader.read(url: asc.appendingPathComponent(
            try XCTUnwrap(ASCMHLChain.latestManifestFileName(ascmhlDir: asc))))
        let hex = try XCTUnwrap(Hashing.hash(for: clip, algorithm: .xxh128))
        let clipEntry = try XCTUnwrap(entries.first { $0.relPath == "CLIP.MOV" })
        XCTAssertEqual(clipEntry.hash.lowercased(), hex.lowercased())
        XCTAssertEqual(clipEntry.algorithm, "xxh128")
        let oldEntry = try XCTUnwrap(entries.first { $0.relPath == "OLD.MOV" })
        XCTAssertEqual(oldEntry.algorithm, "md5", "a carried entry keeps its algorithm")
        XCTAssertEqual(oldEntry.hash, String(repeating: "1", count: 32))
    }

    // MARK: 4. Unreadable chain or manifest

    /// An unreadable chain is set aside, untouched, and the seal fails (surfaced as a
    /// warning by the engine) instead of starting a fresh chain over the history.
    func test_unreadableChain_isSetAside_andSealFails() async throws {
        let asc = tmp.appendingPathComponent("ascmhl")
        let w1 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        try await w1.append(relPath: "a.bin", size: 1, hash: "aa", mtime: nil)
        try await w1.seal()
        let chain = ASCMHLChain.chainURL(ascmhlDir: asc)
        let damaged = Data("<ascmhldirectory><hashlist sequencenr=\"1\"><path>0001".utf8)
        try damaged.write(to: chain)

        let w2 = try ASCMHLWriter(ascmhlDir: asc, rollName: "R")
        try await w2.append(relPath: "b.bin", size: 1, hash: "bb", mtime: nil)
        do {
            try await w2.seal()
            XCTFail("sealing onto an unreadable chain must fail")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
        let aside = try fm.contentsOfDirectory(atPath: asc.path)
            .filter { $0.hasPrefix("ascmhl_chain.xml.") }
        XCTAssertEqual(aside.count, 1, "the damaged chain is kept aside")
        if let kept = aside.first {
            XCTAssertEqual(try Data(contentsOf: asc.appendingPathComponent(kept)), damaged)
        }
        XCTAssertFalse(fm.fileExists(atPath: chain.path),
                       "no fresh chain pretending the history starts here")
    }

    /// The engine reports the set-aside chain on the destination instead of
    /// staying silent.
    func test_unreadableChain_isReportedOnTheDestination() async throws {
        let card = try dir("CARD")
        let dest = try dir("dest")
        try write(randomData(4096), card.appendingPathComponent("A.MOV"))
        let cfg = config(sources: [card], dests: [dest])
        _ = try await FanOutCopier(config: cfg).run()
        let asc = dest.appendingPathComponent("CARD/ascmhl")
        try Data("garbage".utf8).write(to: ASCMHLChain.chainURL(ascmhlDir: asc))

        try write(randomData(4096), card.appendingPathComponent("B.MOV"))
        let second = try await FanOutCopier(config: cfg).run()
        XCTAssertEqual(second.first?.success, true, "the copy itself verified")
        XCTAssertNotNil(second.first?.manifestUnsealedReason)
    }

    /// A damaged latest generation does not wipe the resume state: the previous
    /// readable generation is used.
    func test_unreadableLatestManifest_fallsBackToThePreviousGeneration() async throws {
        let roll = try dir("dest/CARD")
        let asc = roll.appendingPathComponent("ascmhl")
        let w1 = try ASCMHLWriter(ascmhlDir: asc, rollName: "CARD")
        try await w1.append(relPath: "a.bin", size: 1, hash: "aa", mtime: nil)
        try await w1.seal()
        try Data("<hashlist version=\"2.0\"><hashes><hash><path".utf8)
            .write(to: asc.appendingPathComponent("0002_CARD_2099-01-01_000000Z.mhl"))

        let entries = FanOutCopier.loadExistingMHLEntries(
            destPath: tmp.appendingPathComponent("dest").path, rootName: "CARD", rollFolder: roll.path)
        XCTAssertEqual(entries.map(\.fileName), ["a.bin"])
        XCTAssertEqual(entries.map(\.hash), ["aa"])
    }
}
