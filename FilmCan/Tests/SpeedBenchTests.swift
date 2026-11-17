import XCTest
@testable import FilmCan

/// Speed bench, run by `.github/workflows/speed-bench.yml` (and by hand on a Mac).
/// MEASUREMENT ONLY: it calls `FanOutCopier` exactly like the integration tests do and
/// never changes the engine. Skipped unless `FILMCAN_BENCH=1`, so the normal suite is
/// unchanged. With xcodebuild, pass variables as `TEST_RUNNER_FILMCAN_BENCH=1` etc.
///
/// Inputs (environment):
///   FILMCAN_BENCH=1            enable
///   FILMCAN_BENCH_SRC          source folder (the dataset: its files are copied as one roll)
///   FILMCAN_BENCH_DEST         destination volume root (emptied before every run)
///   FILMCAN_BENCH_OUT          JSON file to write
///   FILMCAN_BENCH_LABEL        free label stored in the JSON (e.g. "A", "B", "tools")
///   FILMCAN_BENCH_MODES        comma list: fast,paranoid,off,cp,ditto,floor
///   FILMCAN_BENCH_FSYNC        1 = `requiresFullFsync: true` (what the app sets for exFAT USB)
///   FILMCAN_BENCH_PURGE        1 = try `sudo -n purge` before every run (default 1)
///   FILMCAN_IO_PERF=1          per-step buckets (write, flush, re-read, settle sleep…)
///
/// Every number is only meaningful relative to another run in the same job: the
/// disks are disk images on a shared VM, not real hardware.
final class SpeedBenchTests: XCTestCase {

    private let env = ProcessInfo.processInfo.environment

    func test_bench() async throws {
        try XCTSkipUnless(env["FILMCAN_BENCH"] == "1", "set FILMCAN_BENCH=1 to run the speed bench")
        guard let src = env["FILMCAN_BENCH_SRC"], let dest = env["FILMCAN_BENCH_DEST"],
              let outPath = env["FILMCAN_BENCH_OUT"] else {
            XCTFail("FILMCAN_BENCH_SRC / _DEST / _OUT are required"); return
        }
        let modes = (env["FILMCAN_BENCH_MODES"] ?? "fast,paranoid,off")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let fsync = env["FILMCAN_BENCH_FSYNC"] == "1"
        let purgeWanted = env["FILMCAN_BENCH_PURGE"] != "0"

        let (srcFiles, srcBytes) = Self.tally(src)
        XCTAssertGreaterThan(srcFiles, 0, "empty dataset at \(src)")

        let destInfo = DriveSpeedClassifier.info(for: dest)
        let destClass = DriveSpeedClassifier.slowestDestClass([destInfo])

        var runs: [[String: Any]] = []
        for mode in modes {
            Self.emptyDirectory(dest)
            let purged = purgeWanted ? Self.purge() : false

            var perf: [String: Any] = [:]
            var failure: String?
            var wall = 0.0
            do {
                switch mode {
                case "fast", "paranoid", "off":
                    let vm: VerifyMode = mode == "fast" ? .fast : (mode == "paranoid" ? .paranoid : .off)
                    let r = try await runEngine(src: src, dest: dest, verify: vm, fsync: fsync)
                    wall = r.wall; perf = r.perf; failure = r.failure
                case "cp":
                    wall = try Self.timeProcess("/bin/cp", ["-R", src + "/.", dest + "/roll/"], prepare: dest + "/roll")
                case "ditto":
                    wall = try Self.timeProcess("/usr/bin/ditto", [src, dest + "/roll"], prepare: nil)
                case "floor":
                    wall = try Self.floor(src: src, dest: dest + "/roll", fsync: fsync)
                default:
                    failure = "unknown mode \(mode)"
                }
            } catch {
                failure = "\(error)"
            }

            // A run only counts if every byte landed (engine writes extra manifest files,
            // so compare the dataset's files by size, not the whole tree).
            let landed = Self.landedBytes(dest: dest, srcRoot: src)
            if failure == nil && landed != srcBytes {
                failure = "dest holds \(landed) of \(srcBytes) source bytes"
            }
            var row: [String: Any] = [
                "mode": mode, "wall_s": wall, "valid": failure == nil,
                "purged": purged, "perf": perf,
            ]
            if let failure { row["failure"] = failure }
            runs.append(row)
        }
        Self.emptyDirectory(dest)

        let doc: [String: Any] = [
            "label": env["FILMCAN_BENCH_LABEL"] ?? "",
            "files": srcFiles, "bytes": srcBytes,
            "requiresFullFsync": fsync,
            "dest": [
                "path": dest, "isExFAT": destInfo.isExFAT, "isSSD": destInfo.isSSD,
                "isInternal": destInfo.isInternal, "bus": "\(destInfo.bus)",
                "filesystem": "\(destInfo.filesystem)", "engineClass": "\(destClass)",
                "verifyRunAheadFiles": Constants.verifyRunAheadFiles(forSlowestDest: destClass),
                "chunkBytes": Constants.chunkBytes(forSlowestDest: destClass),
            ],
            "ioPerfEnabled": IOPerfProbe.shared.isEnabled,
            "runs": runs,
        ]
        let data = try JSONSerialization.data(withJSONObject: doc, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outPath))
        for r in runs where (r["valid"] as? Bool) == false {
            XCTFail("invalid run: \(r["mode"] ?? "?") \(r["failure"] ?? "")")
        }
    }

    // MARK: - engine

    private struct EngineRun { var wall: Double; var perf: [String: Any]; var failure: String? }

    private func runEngine(src: String, dest: String, verify: VerifyMode, fsync: Bool) async throws -> EngineRun {
        // Same shape as TransferViewModel: one DestWriter.Config, chunkSize nil, mode
        // copied onto both the destination and the run.
        let config = FanOutCopier.Configuration(
            sources: [src],
            destinations: [DestWriter.Config(destPath: dest, displayName: "bench",
                                             verifyMode: verify, requiresFullFsync: fsync,
                                             chunkSize: nil)],
            verifyMode: verify,
            mhlBasePath: nil,
            dryRun: false,
            progressHandler: nil
        )
        let copier = FanOutCopier(config: config)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let results = try await copier.run()   // returns after the verify tail
        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9

        var failure: String?
        if results.count != 1 || !(results.first?.success ?? false) { failure = "engine reported failure" }

        var perf: [String: Any] = [:]
        if IOPerfProbe.shared.isEnabled {
            for (key, buckets) in IOPerfProbe.shared.snapshot() {
                var k: [String: Any] = [:]
                for (b, s) in buckets {
                    k[b.rawValue] = ["seconds": Double(s.nanos) / 1e9, "calls": s.calls,
                                     "bytes": s.bytes, "max_ms": Double(s.maxNanos) / 1e6]
                }
                perf[key] = k
            }
        }
        return EngineRun(wall: wall, perf: perf, failure: failure)
    }

    // MARK: - references

    /// cp / ditto, the "Finder" reference: buffered write, no verification.
    private static func timeProcess(_ exe: String, _ args: [String], prepare: String?) throws -> Double {
        if let prepare { try FileManager.default.createDirectory(atPath: prepare, withIntermediateDirectories: true) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let t0 = DispatchTime.now().uptimeNanoseconds
        try p.run()
        p.waitUntilExit()
        let wall = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
        if p.terminationStatus != 0 { throw NSError(domain: "bench", code: Int(p.terminationStatus),
                                                    userInfo: [NSLocalizedDescriptionKey: "\(exe) exited \(p.terminationStatus)"]) }
        return wall
    }

    /// Theoretical floor: copy every file once (4 MB blocks, one writer, flushed like the
    /// engine does for the destination class) + one uncached re-read of the copies.
    /// No hashing, no manifest, no overlap: the least a verified copy can cost here.
    private static func floor(src: String, dest: String, fsync: Bool) throws -> Double {
        let fm = FileManager.default
        try fm.createDirectory(atPath: dest, withIntermediateDirectories: true)
        let t0 = DispatchTime.now().uptimeNanoseconds
        let block = 4 * 1024 * 1024
        var buf = [UInt8](repeating: 0, count: block)
        var copied: [String] = []
        for rel in subs(src) {
            let s = src + "/" + rel
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: s, isDirectory: &isDir) else { continue }
            let d = dest + "/" + rel
            if isDir.boolValue { try fm.createDirectory(atPath: d, withIntermediateDirectories: true); continue }
            let fin = open(s, O_RDONLY); guard fin >= 0 else { throw posix("open src", s) }
            let fout = open(d, O_WRONLY | O_CREAT | O_TRUNC, 0o644); guard fout >= 0 else { close(fin); throw posix("open dest", d) }
            while true {
                let n = read(fin, &buf, block)
                if n < 0 { close(fin); close(fout); throw posix("read", s) }
                if n == 0 { break }
                var off = 0
                while off < n {
                    let w = buf.withUnsafeBytes { write(fout, $0.baseAddress! + off, n - off) }
                    if w < 0 { close(fin); close(fout); throw posix("write", d) }
                    off += w
                }
            }
            if fsync { _ = fcntl(fout, F_FULLFSYNC) } else { _ = Darwin.fsync(fout) }
            close(fin); close(fout)
            copied.append(d)
        }
        for d in copied {
            let f = open(d, O_RDONLY); guard f >= 0 else { throw posix("open reread", d) }
            _ = fcntl(f, F_NOCACHE, 1)
            while read(f, &buf, block) > 0 {}
            close(f)
        }
        return Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9
    }

    private static func posix(_ what: String, _ path: String) -> NSError {
        NSError(domain: "bench", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "\(what) \(path): \(String(cString: strerror(errno)))"])
    }

    // MARK: - helpers

    private static func subs(_ p: String) -> [String] {
        (try? FileManager.default.subpathsOfDirectory(atPath: p)) ?? []
    }

    private static func tally(_ root: String) -> (Int, Int64) {
        var n = 0; var bytes: Int64 = 0
        let fm = FileManager.default
        for rel in subs(root) {
            let attrs = try? fm.attributesOfItem(atPath: root + "/" + rel)
            if (attrs?[.type] as? FileAttributeType) == .typeRegular {
                n += 1; bytes += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return (n, bytes)
    }

    /// Sum of the sizes at the destination of every dataset file (by relative path under
    /// the roll folder), whichever of the engine / cp / ditto layouts was used.
    private static func landedBytes(dest: String, srcRoot: String) -> Int64 {
        let fm = FileManager.default
        let rollName = (srcRoot as NSString).lastPathComponent
        let candidates = [dest + "/" + rollName, dest + "/roll", dest]
        var best: Int64 = 0
        for base in candidates {
            var total: Int64 = 0
            for rel in subs(srcRoot) {
                let a = try? fm.attributesOfItem(atPath: srcRoot + "/" + rel)
                guard (a?[.type] as? FileAttributeType) == .typeRegular else { continue }
                if let d = try? fm.attributesOfItem(atPath: base + "/" + rel),
                   (d[.size] as? NSNumber)?.int64Value == (a?[.size] as? NSNumber)?.int64Value {
                    total += (a?[.size] as? NSNumber)?.int64Value ?? 0
                }
            }
            best = max(best, total)
        }
        return best
    }

    private static func emptyDirectory(_ path: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: path)) ?? [] {
            // Keep the volume's own system folders (Spotlight, fseventsd, Trashes).
            if name.hasPrefix(".") { continue }
            try? fm.removeItem(atPath: path + "/" + name)
        }
    }

    /// Drop the OS file cache so a run does not read the previous run's cached data.
    /// Needs root; the GitHub runner allows passwordless sudo. False when it did not work.
    private static func purge() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", "/usr/sbin/purge"]
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit() } catch { return false }
        return p.terminationStatus == 0
    }
}
