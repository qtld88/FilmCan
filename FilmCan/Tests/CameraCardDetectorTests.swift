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
