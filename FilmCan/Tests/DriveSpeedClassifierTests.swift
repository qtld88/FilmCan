import XCTest
@testable import FilmCan

final class DriveSpeedClassifierTests: XCTestCase {
    func test_classify_ssdThunderbolt_returns400() {
        let info = DriveInfo(
            isSSD: true,
            bus: .thunderbolt,
            filesystem: .apfs,
            isInternal: false,
            isExFAT: false,
            isNetwork: false,
            volumeUUID: "test"
        )
        let speed = DriveSpeedClassifier.expectedSpeedMBps(info)
        XCTAssertEqual(speed, 400)
    }

    func test_classify_hddUsb3_returns120() {
        let info = DriveInfo(
            isSSD: false, bus: .usb3plus, filesystem: .hfsplus,
            isInternal: false, isExFAT: false, isNetwork: false, volumeUUID: "test"
        )
        XCTAssertEqual(DriveSpeedClassifier.expectedSpeedMBps(info), 120)
    }

    func test_classify_exfatModifierIsPoint6() {
        let info = DriveInfo(
            isSSD: true, bus: .usb3plus, filesystem: .exfat,
            isInternal: false, isExFAT: true, isNetwork: false, volumeUUID: "test"
        )
        XCTAssertEqual(DriveSpeedClassifier.expectedSpeedMBps(info), 400 * 0.6, accuracy: 0.01)
    }

    func test_classify_usb2_returns35() {
        let info = DriveInfo(
            isSSD: true, bus: .usb2, filesystem: .apfs,
            isInternal: false, isExFAT: false, isNetwork: false, volumeUUID: "test"
        )
        XCTAssertEqual(DriveSpeedClassifier.expectedSpeedMBps(info), 35)
    }

    func test_classify_unknownDefault100() {
        let info = DriveInfo(
            isSSD: false, bus: .unknown, filesystem: .unknown,
            isInternal: false, isExFAT: false, isNetwork: false, volumeUUID: "test"
        )
        XCTAssertEqual(DriveSpeedClassifier.expectedSpeedMBps(info), 100)
    }

    func test_requiresFullFsync_internalApfs_false() {
        let info = DriveInfo(
            isSSD: true, bus: .internal_, filesystem: .apfs,
            isInternal: true, isExFAT: false, isNetwork: false, volumeUUID: "x"
        )
        XCTAssertFalse(DriveSpeedClassifier.requiresFullFsync(info))
    }

    func test_requiresFullFsync_externalApfs_true() {
        let info = DriveInfo(
            isSSD: true, bus: .usb3plus, filesystem: .apfs,
            isInternal: false, isExFAT: false, isNetwork: false, volumeUUID: "x"
        )
        XCTAssertTrue(DriveSpeedClassifier.requiresFullFsync(info))
    }

    func test_requiresFullFsync_anyExFAT_true() {
        let info = DriveInfo(
            isSSD: true, bus: .usb3plus, filesystem: .exfat,
            isInternal: false, isExFAT: true, isNetwork: false, volumeUUID: "x"
        )
        XCTAssertTrue(DriveSpeedClassifier.requiresFullFsync(info))
    }

    func test_slowestDestClass_allNvme_returnsNvmeLocal() {
        let infos = [
            DriveInfo(isSSD: true, bus: .thunderbolt, filesystem: .apfs,
                      isInternal: true, isExFAT: false, isNetwork: false, volumeUUID: "a"),
            DriveInfo(isSSD: true, bus: .thunderbolt, filesystem: .apfs,
                      isInternal: false, isExFAT: false, isNetwork: false, volumeUUID: "b")
        ]
        XCTAssertEqual(DriveSpeedClassifier.slowestDestClass(infos), .nvmeLocal)
    }

    func test_slowestDestClass_oneExFAT_returnsExfat() {
        let infos = [
            DriveInfo(isSSD: true, bus: .thunderbolt, filesystem: .apfs,
                      isInternal: true, isExFAT: false, isNetwork: false, volumeUUID: "a"),
            DriveInfo(isSSD: false, bus: .usb3plus, filesystem: .exfat,
                      isInternal: false, isExFAT: true, isNetwork: false, volumeUUID: "b")
        ]
        XCTAssertEqual(DriveSpeedClassifier.slowestDestClass(infos), .exfat)
    }

    func test_info_forRootVolume_returnsInternal() {
        let info = DriveSpeedClassifier.info(for: "/")
        XCTAssertTrue(info.isInternal)
        XCTAssertEqual(info.filesystem, .apfs)
        XCTAssertNotNil(info.volumeUUID)
    }
}
