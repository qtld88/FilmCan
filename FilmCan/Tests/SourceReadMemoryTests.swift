import XCTest
import Darwin
@testable import FilmCan

/// Field report: FilmCan passed 40 GB of memory a few minutes into a card copy to one
/// fast SSD. `FileHandle.read` returns autoreleased Data, and the async source loop
/// never drains its pool while the destination keeps up. `FanOutCopier.readChunk`
/// drains per chunk; this reads the same 32 MB file 40 times (1.28 GB) in one
/// synchronous stretch with no pool of its own, so a leak would show in full.
final class SourceReadMemoryTests: XCTestCase {

    private func footprintBytes() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    private func makeFile(megabytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readmem-\(UUID().uuidString).bin")
        let mb = Data((0..<(1024 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let h = try FileHandle(forWritingTo: url)
        for _ in 0..<megabytes { try h.write(contentsOf: mb) }
        try h.close()
        return url
    }

    /// Reads the file `passes` times with `read`, keeping nothing; returns growth.
    private func growth(url: URL, passes: Int, read: (FileHandle) throws -> Data?) throws -> Int64 {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let before = footprintBytes()
        var total = 0
        for _ in 0..<passes {
            try handle.seek(toOffset: 0)
            while let chunk = try read(handle) { total += chunk.count }
        }
        let after = footprintBytes()
        XCTAssertEqual(total, passes * 32 * 1024 * 1024)
        return after - before
    }

    func test_readChunk_doesNotKeepChunksAlive() throws {
        let url = try makeFile(megabytes: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        let grown = try growth(url: url, passes: 40) {
            try FanOutCopier.readChunk($0, upTo: 4 * 1024 * 1024)
        }
        print("SourceReadMemoryTests readChunk growth MB:", grown / 1_000_000)
        XCTAssertLessThan(grown, 256 * 1_000_000,
                          "reading 1.28 GB in chunks must not keep the chunks in memory")
    }

    /// Control, reported only: the same reads without a pool, to show in the log
    /// whether this macOS still autoreleases the Data that `read(upToCount:)` returns.
    func test_control_plainRead_growthIsLogged() throws {
        let url = try makeFile(megabytes: 32)
        defer { try? FileManager.default.removeItem(at: url) }
        try autoreleasepool {
            let grown = try growth(url: url, passes: 40) {
                guard let d = try $0.read(upToCount: 4 * 1024 * 1024), !d.isEmpty else { return nil }
                return d
            }
            print("SourceReadMemoryTests control plain read growth MB:", grown / 1_000_000)
        }
    }
}
