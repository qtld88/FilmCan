import Foundation

// Speed advice before and after a copy. Everything here is pure: the drive facts come
// in as values (probed elsewhere), so the rules are testable without hardware.

// MARK: - One destination at a time?

enum DestinationCopyPlan {
    /// Whether a run copies its destinations one after the other. The same rule the
    /// run has always used: "automatic" goes one at a time only for a network drive or
    /// two destinations on the same volume.
    static func isSequential(mode: DestinationCopyMode, destinations: [DriveInfo]) -> Bool {
        guard destinations.count > 1 else { return false }
        switch mode {
        case .parallel:   return false
        case .sequential: return true
        case .automatic:
            if destinations.contains(where: { $0.isNetwork }) { return true }
            let uuids = destinations.compactMap { $0.volumeUUID }
            return Set(uuids).count < uuids.count
        }
    }
}

// MARK: - Drive facts

struct SpeedDrive: Equatable {
    enum Role: Equatable { case source, destination }

    var path: String
    var name: String
    var role: Role
    var info: DriveInfo
    /// Registry id of the nearest external USB hub above the drive, if any.
    var hubID: UInt64? = nil
    var capacityBytes: Int64? = nil
    var availableBytes: Int64? = nil

    /// The drive's own report of its medium ("Rotational" / "Solid State"), when the
    /// enclosure passes it on. nil = not reported.
    var isRotational: Bool? = nil

    /// Same volume ⇒ same key; used to count a volume once and to remember dismissals.
    var volumeKey: String { info.volumeUUID ?? path }

    /// Typical speed from facts we trust, or nil when we cannot say. macOS often reports
    /// an external SSD as "not solid state", so "not solid state" alone never makes a
    /// drive slow: only a drive that says it spins, or a USB 2 link, is called slow.
    var typicalMBps: Double? {
        if info.isNetwork { return nil }
        if info.bus == .usb2 { return 35 }
        if isRotational == true {
            switch info.bus {
            case .thunderbolt, .usb3plus: return 120
            case .internal_: return 100
            default: return nil
            }
        }
        if info.isSSD && isRotational != true {
            switch info.bus {
            case .thunderbolt, .usb3plus, .internal_: return 400
            default: return nil
            }
        }
        return nil
    }

    var kindKnown: Bool { typicalMBps != nil }

    /// Plain words for the drive kind, for sentences.
    var kindLabel: String {
        if info.isNetwork { return "network drive" }
        if info.bus == .usb2 { return "USB 2" }
        if isRotational == true { return "hard drive" }
        if role == .source { return "card or card reader" }
        return info.isSSD ? "SSD" : "drive"
    }
}

// MARK: - Before the copy

struct SpeedAdvice: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case slowAndFastAtOnce
        case slowDriveFirst
        case usb2
        case sharedHub
        case nearlyFullSSD
    }

    enum Action: Equatable {
        /// Copy one destination at a time, these paths first (in this order).
        case copyFirst(paths: [String], name: String)
    }

    var kind: Kind
    var volumeKeys: [String]
    var title: String
    var detail: String
    var action: Action?
    /// Rough seconds this costs; only used to sort.
    var costSeconds: Double

    var id: String { dismissKey }

    /// Kind + the drives involved. A dismissed advice does not come back for the same drives.
    var dismissKey: String {
        kind.rawValue + "|" + volumeKeys.sorted().joined(separator: ",")
    }
}

enum SpeedAdvisor {
    static let maxShown = 3
    static let fastRatio = Constants.speedDisparityWarnRatio
    static let nearlyFullFraction = 0.10

    static func advices(sources: [SpeedDrive],
                        destinations: [SpeedDrive],
                        bytesToCopy: Int64,
                        mode: DestinationCopyMode,
                        dismissed: Set<String> = []) -> [SpeedAdvice] {
        guard bytesToCopy > 0, !destinations.isEmpty else { return [] }
        let dests = uniqueByVolume(destinations)
        let srcs = uniqueByVolume(sources)
        let mb = Double(bytesToCopy) / 1_000_000
        var out: [SpeedAdvice] = []

        // Slow and fast destinations.
        let sequential = DestinationCopyPlan.isSequential(mode: mode, destinations: destinations.map(\.info))
        if let advice = orderAdvice(dests: dests, sequential: sequential, mb: mb) {
            out.append(advice)
        }

        // USB 2.
        for drive in srcs + dests where drive.info.bus == .usb2 && !drive.info.isNetwork {
            // What the same drive would give on USB 3: a hard drive's own pace, else an SSD's.
            let onUSB3: Double = drive.isRotational == true ? 120 : 400
            let cost = mb / 35 - mb / onUSB3
            out.append(SpeedAdvice(
                kind: .usb2, volumeKeys: [drive.volumeKey],
                title: "\u{2018}\(drive.name)\u{2019} is connected over USB 2",
                detail: "USB 2 copies at about 35 MB/s at most. A USB 3 or Thunderbolt port and cable would be much faster.",
                action: nil, costSeconds: max(cost, 0)))
        }

        // Shared USB hub.
        var byHub: [UInt64: [SpeedDrive]] = [:]
        for drive in srcs + dests where !drive.info.isNetwork {
            if let hub = drive.hubID { byHub[hub, default: []].append(drive) }
        }
        for (_, group) in byHub.sorted(by: { $0.key < $1.key }) {
            let drives = uniqueByVolume(group)
            guard drives.count >= 2 else { continue }
            let slowest = drives.compactMap(\.typicalMBps).min() ?? 100
            out.append(SpeedAdvice(
                kind: .sharedHub, volumeKeys: drives.map(\.volumeKey),
                title: "\(listNames(drives.map(\.name))) share one USB hub",
                detail: "A hub splits its speed between the drives plugged into it. Plug one of them straight into the Mac.",
                action: nil, costSeconds: mb / slowest * 0.5))
        }

        // SSD nearly full after the copy.
        for drive in dests where drive.info.isSSD && !drive.info.isNetwork {
            guard let capacity = drive.capacityBytes, capacity > 0,
                  let available = drive.availableBytes, available >= bytesToCopy else { continue }
            let freeAfter = Double(available - bytesToCopy) / Double(capacity)
            guard freeAfter < nearlyFullFraction else { continue }
            out.append(SpeedAdvice(
                kind: .nearlyFullSSD, volumeKeys: [drive.volumeKey],
                title: "\u{2018}\(drive.name)\u{2019} will be over 90\u{2009}% full after this copy",
                detail: "Many SSDs write more slowly when they are nearly full.",
                action: nil, costSeconds: mb / (drive.typicalMBps ?? 400) * 0.25))
        }

        return Array(out
            .filter { !dismissed.contains($0.dismissKey) }
            .sorted { $0.costSeconds > $1.costSeconds }
            .prefix(maxShown))
    }

    private static func orderAdvice(dests: [SpeedDrive], sequential: Bool, mb: Double) -> SpeedAdvice? {
        let known: [(drive: SpeedDrive, mbps: Double)] = dests.compactMap { d in
            d.typicalMBps.map { (drive: d, mbps: $0) }
        }
        guard known.count >= 2,
              let fastest = known.max(by: { $0.mbps < $1.mbps }),
              let slowest = known.min(by: { $0.mbps < $1.mbps }),
              fastest.mbps >= slowest.mbps * fastRatio else { return nil }

        let fastKeys = Set(known.filter { $0.mbps >= slowest.mbps * fastRatio }.map { $0.drive.volumeKey })
        let isFast: (SpeedDrive) -> Bool = { fastKeys.contains($0.volumeKey) }
        let isSlow: (SpeedDrive) -> Bool = { $0.kindKnown && !fastKeys.contains($0.volumeKey) }
        let fastDrives = dests.filter(isFast)
        let fastNames = listNames(fastDrives.map(\.name))
        let fastPaths = fastDrives.map(\.path)

        if sequential {
            // Already fast first? Then nothing to say.
            guard let firstSlowIndex = dests.firstIndex(where: isSlow),
                  let lastFastIndex = dests.lastIndex(where: isFast),
                  firstSlowIndex < lastFastIndex else { return nil }
            let slowBefore = dests[..<lastFastIndex].filter(isSlow)
            let waited = slowBefore.reduce(0.0) { $0 + mb / ($1.typicalMBps ?? 100) }
            let verb = fastDrives.count == 1 ? "waits" : "wait"
            return SpeedAdvice(
                kind: .slowDriveFirst, volumeKeys: dests.map(\.volumeKey),
                title: "\(fastNames) \(verb) behind \(listNames(slowBefore.map(\.name)))",
                detail: "Drives are copied one at a time, in the Save To order. Copying to \(fastNames) first gives you a first checked copy \(sooner(by: waited)).",
                action: .copyFirst(paths: fastPaths, name: fastNames),
                costSeconds: waited)
        }

        let atSlowPace = mb / slowest.mbps
        let alone = mb / fastest.mbps
        return SpeedAdvice(
            kind: .slowAndFastAtOnce, volumeKeys: dests.map(\.volumeKey),
            title: "\u{2018}\(slowest.drive.name)\u{2019} sets the pace for every drive",
            detail: "All drives are written at the same time, so the copy goes at the speed of the slowest (\(slowest.drive.kindLabel)). Copying to \(fastNames) first gives you a first checked copy in about \(duration(alone)) instead of \(duration(atSlowPace)). The card is then read once per drive, so the whole copy takes longer.",
            action: .copyFirst(paths: fastPaths, name: fastNames),
            costSeconds: max(atSlowPace - alone, 0))
    }

    /// The destination order after "Copy to … first": those paths first, the rest after,
    /// each group in its current order.
    static func reordered(_ destinations: [String], first: [String]) -> [String] {
        let firstSet = Set(first)
        return destinations.filter { firstSet.contains($0) } + destinations.filter { !firstSet.contains($0) }
    }

    // MARK: Words

    static func listNames(_ names: [String]) -> String {
        let quoted = names.map { "\u{2018}\($0)\u{2019}" }
        switch quoted.count {
        case 0: return ""
        case 1: return quoted[0]
        default: return quoted.dropLast().joined(separator: ", ") + " and " + quoted.last!
        }
    }

    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 1 { return "a minute" }
        if minutes < 60 { return minutes == 1 ? "1 min" : "\(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    private static func sooner(by seconds: Double) -> String {
        seconds < 60 ? "sooner" : "about \(duration(seconds)) sooner"
    }

    private static func uniqueByVolume(_ drives: [SpeedDrive]) -> [SpeedDrive] {
        var seen = Set<String>()
        return drives.filter { seen.insert($0.volumeKey).inserted }
    }
}

// MARK: - After the copy

struct SpeedRunMeasure: Equatable {
    struct Dest: Equatable {
        var drive: SpeedDrive
        /// Bytes actually written this run (not the job total).
        var bytes: Int64
        /// Wall-clock time of this destination's own pass (one-at-a-time runs only;
        /// 0 when it shared a pass with other drives).
        var seconds: TimeInterval
        var success: Bool
    }

    var sources: [SpeedDrive]
    var destinations: [Dest]
    var sequential: Bool
    /// Wall-clock time of the whole run, check included.
    var wallSeconds: TimeInterval
    /// Full check: every file read back from both sides (roughly halves the pace).
    var rereads: Bool
    var cancelled: Bool
}

enum SpeedNote {
    static let minBytes: Int64 = 1_000_000_000
    static let minSeconds: TimeInterval = 30

    /// One sentence naming the slow link, or nil when the run tells us nothing useful.
    static func sentence(for run: SpeedRunMeasure) -> String? {
        guard !run.cancelled, !run.destinations.isEmpty,
              run.destinations.allSatisfy({ $0.success }) else { return nil }
        let copied = run.destinations.map(\.bytes).max() ?? 0
        guard copied >= minBytes else { return nil }
        let check = run.rereads ? ", read-back check included" : ""

        if run.sequential {
            let measured = run.destinations.filter { $0.bytes >= minBytes && $0.seconds >= minSeconds }
            guard measured.count >= 2 else { return nil }
            let speeds = measured.map { (name: $0.drive.name, mbps: Double($0.bytes) / 1_000_000 / $0.seconds) }
            guard let slow = speeds.min(by: { $0.mbps < $1.mbps }),
                  let fast = speeds.max(by: { $0.mbps < $1.mbps }),
                  fast.mbps >= slow.mbps * 1.5 else { return nil }
            return "\u{2018}\(slow.name)\u{2019} was the slowest drive: \(mbps(slow.mbps)), against \(mbps(fast.mbps)) for \u{2018}\(fast.name)\u{2019}."
        }

        guard run.wallSeconds >= minSeconds else { return nil }
        let overall = Double(copied) / 1_000_000 / run.wallSeconds
        let links: [(drive: SpeedDrive, mbps: Double)] = (run.sources + run.destinations.map(\.drive))
            .compactMap { d in d.typicalMBps.map { (drive: d, mbps: $0) } }
        guard let slowest = links.min(by: { $0.mbps < $1.mbps }) else { return nil }
        // Writing then re-reading roughly halves what a drive gives to the copy.
        let allowed = slowest.mbps * (run.rereads ? 0.5 : 1.0)
        if overall >= allowed * 0.6 {
            return "This copy ran at \(mbps(overall))\(check). The slowest link was \u{2018}\(slowest.drive.name)\u{2019} (\(slowest.drive.kindLabel))."
        }
        // Only claim "slower than the drives allow" when every drive's speed is known.
        let all = run.sources + run.destinations.map(\.drive)
        if all.allSatisfy(\.kindKnown), overall < allowed * 0.3 {
            return "This copy ran at \(mbps(overall))\(check), slower than these drives allow. A shared hub, a long cable or a busy Mac may have held it back."
        }
        return nil
    }

    static func mbps(_ value: Double) -> String {
        "\(Int(value.rounded())) MB/s"
    }
}
