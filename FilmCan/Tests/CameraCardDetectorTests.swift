import XCTest
@testable import FilmCan

final class CameraCardDetectorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("CardDet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    private func make(_ rels: [String], in root: URL? = nil) throws -> URL {
        let base = root ?? tmp!
        for rel in rels {
            let url = base.appendingPathComponent(rel)
            if rel.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
        }
        return base
    }

    private func detect(_ rels: [String]) throws -> CardSignature? {
        CameraCardDetector.detect(rootPath: try make(rels).path)
    }

    func test_arri_ariFile() throws {
        XCTAssertEqual(try detect(["A001C002_220101_R1AB.ari"])?.brand, .arri)
    }

    func test_arri_mxf() throws {
        XCTAssertEqual(try detect(["CLIPS/A002C001_220101_R1AB.mxf"])?.brand, .arri)
    }

    func test_arri_reelFromVolumeName() throws {
        let root = tmp.appendingPathComponent("A007R1AB")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try make(["A001C002_220101_R1AB.ari"], in: root)
        let sig = CameraCardDetector.detect(rootPath: root.path)
        XCTAssertEqual(sig, CardSignature(brand: .arri, reelName: "A007R1AB"))
    }

    func test_arri_reelFromClipName() throws {
        let sig = try detect(["A012C002_220101_R1AB.ari"])
        XCTAssertEqual(sig?.reelName, "A012")
    }

    func test_red_reelFromRDM() throws {
        let sig = try detect(["A003_R1AB.RDM/A003_C001.RDC/clip.R3D"])
        XCTAssertEqual(sig, CardSignature(brand: .red, reelName: "A003_R1AB"))
    }

    func test_sony_m4root() throws {
        XCTAssertEqual(try detect(["PRIVATE/M4ROOT/CLIP/C0001.MP4"])?.brand, .sony)
    }

    func test_sony_xdroot() throws {
        XCTAssertEqual(try detect(["XDROOT/Clip/x.MXF"])?.brand, .sony)
    }

    func test_canon_contentsClips() throws {
        XCTAssertEqual(try detect(["CONTENTS/CLIPS001/A.MXF"])?.brand, .canon)
    }

    func test_canon_dcim() throws {
        XCTAssertEqual(try detect(["DCIM/100CANON/IMG.MOV"])?.brand, .canon)
    }

    func test_panasonic_group() throws {
        XCTAssertEqual(try detect(["PRIVATE/PANA_GRP/x"])?.brand, .panasonic)
    }

    func test_panasonic_dcim() throws {
        XCTAssertEqual(try detect(["DCIM/100_PANA/P1.MOV"])?.brand, .panasonic)
    }

    func test_blackmagic_braw() throws {
        XCTAssertEqual(try detect(["Clip0001.braw"])?.brand, .blackmagic)
    }

    func test_gopro() throws {
        XCTAssertEqual(try detect(["DCIM/100GOPRO/GOPR0001.MP4"])?.brand, .gopro)
    }

    func test_dji_folder() throws {
        XCTAssertEqual(try detect(["DCIM/DJI_001/DJI_0001.MP4"])?.brand, .dji)
    }

    func test_dji_100media() throws {
        XCTAssertEqual(try detect(["DCIM/100MEDIA/DJI_0001.MP4"])?.brand, .dji)
    }

    // MARK: - Panasonic P2

    func test_panasonic_p2() throws {
        XCTAssertEqual(try detect(["CONTENTS/CLIP/0001AB.XML", "CONTENTS/VIDEO/0001AB.MXF", "CONTENTS/AUDIO/0001AB00.MXF", "LASTCLIP.TXT"])?.brand, .panasonic)
    }

    func test_canonXF_isStillCanon_notP2() throws {
        XCTAssertEqual(try detect(["CONTENTS/CLIPS001/AA0001/AA000101.MXF"])?.brand, .canon)
    }

    // MARK: - Insta360

    func test_insta360_insvClip() throws {
        XCTAssertEqual(try detect(["DCIM/Camera01/VID_20260101_120000_00_001.insv"])?.brand, .insta360)
    }

    func test_insta360_cameraFolderWithMP4() throws {
        XCTAssertEqual(try detect(["DCIM/Camera01/VID_20260101_120000_001.mp4"])?.brand, .insta360)
    }

    // MARK: - AVCHD

    func test_avchd_privateFolder() throws {
        XCTAssertEqual(try detect(["PRIVATE/AVCHD/BDMV/STREAM/00000.MTS"])?.brand, .avchd)
    }

    func test_avchd_rootFolder() throws {
        XCTAssertEqual(try detect(["AVCHD/BDMV/STREAM/00000.MTS"])?.brand, .avchd)
    }

    func test_avchd_withPanasonicGroup_isPanasonic() throws {
        XCTAssertEqual(try detect(["PRIVATE/AVCHD/BDMV/STREAM/00000.MTS", "PRIVATE/PANA_GRP/001YAAAA/x"])?.brand, .panasonic)
    }

    func test_avchd_withSonyRoot_isSony() throws {
        XCTAssertEqual(try detect(["PRIVATE/AVCHD/BDMV/STREAM/00000.MTS", "PRIVATE/M4ROOT/CLIP/C0001.MP4"])?.brand, .sony)
    }

    // MARK: - Generic DCIM

    func test_genericDCIM_withVideo() throws {
        XCTAssertEqual(try detect(["DCIM/100MSDCF/DSC00001.JPG", "DCIM/100MSDCF/C0001.MP4"])?.brand, .genericDCIM)
    }

    func test_genericDCIM_videoDirectlyInDCIM() throws {
        XCTAssertEqual(try detect(["DCIM/MOVIE001.MOV"])?.brand, .genericDCIM)
    }

    func test_genericDCIM_photosOnly_isNotACard() throws {
        XCTAssertNil(try detect(["DCIM/100NIKON/DSC_0001.JPG", "DCIM/100NIKON/DSC_0002.NEF"]))
    }

    func test_genericDCIM_emptyFolder_isNotACard() throws {
        XCTAssertNil(try detect(["DCIM/"]))
    }

    func test_genericDCIM_hiddenVideoIgnored() throws {
        XCTAssertNil(try detect(["DCIM/100ABCDE/._C0001.MP4", "DCIM/100ABCDE/IMG_0001.JPG"]))
    }

    /// A clip behind thousands of photos is still found (the general scan stops at 2 000 entries).
    func test_genericDCIM_videoBeyondTheScanCap() throws {
        var rels = (0..<2100).map { String(format: "DCIM/100ABCDE/IMG_%04d.JPG", $0) }
        rels.append("DCIM/101ABCDE/ZZZ_0001.MP4")
        XCTAssertEqual(try detect(rels)?.brand, .genericDCIM)
    }

    /// A named family always wins over generic DCIM.
    func test_namedFamiliesWinOverGenericDCIM() throws {
        XCTAssertEqual(try detect(["DCIM/100CANON/MVI_0001.MOV"])?.brand, .canon)
    }

    func test_goproWinsOverGenericDCIM() throws {
        XCTAssertEqual(try detect(["DCIM/100GOPRO/GX010001.MP4"])?.brand, .gopro)
    }

    func test_djiWinsOverGenericDCIM() throws {
        XCTAssertEqual(try detect(["DCIM/100MEDIA/DJI_0001.MP4"])?.brand, .dji)
    }

    func test_genericDCIM_withSeparateWav_isCamera_notSound() throws {
        let signature = try detect(["DCIM/100ABCDE/C0001.MP4", "DCIM/100ABCDE/C0001.WAV"])
        XCTAssertEqual(signature?.brand, .genericDCIM)
        XCTAssertEqual(signature?.brand.isSound, false)
    }

    func test_newFamiliesCarryNoReelName() throws {
        XCTAssertNil(try detect(["DCIM/100ABCDE/C0001.MP4"])?.reelName)
    }

    // MARK: - Every family is described

    func test_everyBrandHasANameAndAReason() {
        for brand in CameraBrand.allCases {
            XCTAssertFalse(brand.displayName.isEmpty, "\(brand)")
            XCTAssertFalse(brand.recognisedBy.isEmpty, "\(brand)")
        }
        XCTAssertEqual(CameraBrand.allCases.filter(\.isSound), [.soundRecorder])
    }

    func test_sound_wavOnly() throws {
        let sig = try detect(["REC/TR001.WAV", "REC/TR002.wav"])
        XCTAssertEqual(sig?.brand, .soundRecorder)
        XCTAssertEqual(sig?.brand.isSound, true)
    }

    func test_wavPlusMov_isNotSound() throws {
        XCTAssertNil(try detect(["a.wav", "b.mov"]))
    }

    func test_plainFolder_isNil() throws {
        XCTAssertNil(try detect(["Documents/readme.txt", "photo.jpg"]))
    }

    func test_hiddenNamesIgnored() throws {
        XCTAssertNil(try detect([".hidden/clip.braw"]))
    }

    func test_depthAndEntryCapsDoNotHang() throws {
        var rels: [String] = []
        for i in 0..<5000 { rels.append("f\(i).txt") }
        let root = try make(rels)
        let start = Date()
        _ = CameraCardDetector.detect(rootPath: root.path)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
