import Foundation

/// A non-blocking hint shown before a copy when what is plugged in will slow it down,
/// with what to do about it.
struct SpeedAdvice: Identifiable, Equatable {
    enum Kind: String { case mixedSpeeds, usb2, nearlyFull }
    enum Action: Equatable {
        /// Copy to one drive after the other, fastest first (paths in the new order).
        case copyFastFirst(order: [String], fastName: String)
    }

    let kind: Kind
    /// Stable for the same hint about the same drives: a closed hint does not come back.
    let id: String
    let title: String
    let detail: String
    let action: Action?
    /// Rough time this costs on the planned copy, to show the costliest first.
    let costSeconds: Double

    var actionTitle: String? {
        guard case .copyFastFirst(_, let fastName) = action else { return nil }
        return "Copy to \(fastName) first"
    }
}

enum SpeedAdvisor {
    static let maxShown = 3
    /// A drive is "much slower" below this share of the fastest destination.
    static let slowShare = 0.5
    /// SSDs slow down markedly when nearly full.
    static let nearlyFullShare = 0.9
    static let dismissedDefaultsKey = "speedAdviceDismissed"

    struct Drive: Equatable {
        var path: String
        var name: String
        var info: DriveInfo
        var totalBytes: Int64?
        var availableBytes: Int64?

        /// The drive's id when known, else its path: what a closed hint is remembered by.
        var key: String { info.volumeUUID ?? path }
        var expectedMBps: Double { DriveSpeedClassifier.expectedSpeedMBps(info) }
    }

    /// What the "Automatic" mode already does by itself (mirrors
    /// `TransferViewModel.shouldCopyDestinationsSequentially`): no hint for a problem
    /// the engine already avoids.
    static func copiesOneAfterTheOther(mode: DestinationCopyMode, destinations: [Drive]) -> Bool {
        guard destinations.count > 1 else { return false }
        switch mode {
        case .parallel: return false
        case .sequential: return true
        case .automatic:
            if destinations.contains(where: { $0.info.isNetwork }) { return true }
            let uuids = destinations.compactMap { $0.info.volumeUUID }
            return Set(uuids).count < uuids.count
        }
    }

    private static func seconds(_ bytes: Int64, atMBps speed: Double) -> Double {
        guard speed > 0 else { return 0 }
        return Double(bytes) / 1_000_000 / speed
    }

    private static func id(_ kind: SpeedAdvice.Kind, _ drives: [Drive]) -> String {
        kind.rawValue + ":" + drives.map(\.key).sorted().joined(separator: "+")
    }

    /// At most three hints, the costliest first; closed ones left out.
    static func advice(sources: [Drive], destinations: [Drive], mode: DestinationCopyMode,
                       bytesToCopy: Int64, dismissed: Set<String> = []) -> [SpeedAdvice] {
        var out: [SpeedAdvice] = []

        // A slow and a fast drive written at the same time: the pair goes at the slow one's pace.
        if destinations.count > 1, !copiesOneAfterTheOther(mode: mode, destinations: destinations),
           let fast = destinations.max(by: { $0.expectedMBps < $1.expectedMBps }),
           let slow = destinations.min(by: { $0.expectedMBps < $1.expectedMBps }),
           slow.expectedMBps <= fast.expectedMBps * slowShare {
            let order = destinations.enumerated()
                .sorted { $0.element.expectedMBps != $1.element.expectedMBps
                    ? $0.element.expectedMBps > $1.element.expectedMBps : $0.offset < $1.offset }
                .map(\.element.path)
            out.append(SpeedAdvice(
                kind: .mixedSpeeds, id: id(.mixedSpeeds, [fast, slow]),
                title: "\(slow.name) is much slower than \(fast.name)",
                detail: "Copying to both at once goes at the pace of \(slow.name). Copying to \(fast.name) first gives you one checked copy sooner.",
                action: .copyFastFirst(order: order, fastName: fast.name),
                costSeconds: seconds(bytesToCopy, atMBps: slow.expectedMBps) - seconds(bytesToCopy, atMBps: fast.expectedMBps)))
        }

        // Anything on a USB 2 link.
        var seen = Set<String>()
        for drive in sources + destinations where drive.info.bus == .usb2 && seen.insert(drive.key).inserted {
            var faster = drive.info
            faster.bus = .usb3plus
            out.append(SpeedAdvice(
                kind: .usb2, id: id(.usb2, [drive]),
                title: "\(drive.name) is connected at USB 2 speed",
                detail: "That is about 35 MB/s at best. Try a blue or USB-C port, another cable, or plug it straight into the Mac instead of a hub or keyboard.",
                action: nil,
                costSeconds: seconds(bytesToCopy, atMBps: drive.expectedMBps)
                    - seconds(bytesToCopy, atMBps: DriveSpeedClassifier.expectedSpeedMBps(faster))))
        }

        // An SSD that the copy will leave nearly full.
        for drive in destinations where drive.info.isSSD {
            guard let total = drive.totalBytes, total > 0, let available = drive.availableBytes else { continue }
            let usedAfter = Double(total - available + bytesToCopy) / Double(total)
            guard usedAfter >= nearlyFullShare, usedAfter <= 1 else { continue }
            out.append(SpeedAdvice(
                kind: .nearlyFull, id: id(.nearlyFull, [drive]),
                title: "\(drive.name) will be more than 90 % full",
                detail: "An SSD slows down when it is nearly full. Expect the end of the copy to be slower on this drive.",
                action: nil,
                // No measured figure: counted as a fifth of the copy time on that drive.
                costSeconds: seconds(bytesToCopy, atMBps: drive.expectedMBps) * 0.2))
        }

        return Array(out.filter { !dismissed.contains($0.id) }
            .sorted { $0.costSeconds != $1.costSeconds ? $0.costSeconds > $1.costSeconds : $0.id < $1.id }
            .prefix(maxShown))
    }

    // MARK: - After the copy

    /// One sentence naming the slow link, from the speed the copy really ran at.
    /// Nil when the copy was too small to tell, or when nothing stands out.
    static func slowLink(bytesCopied: Int64, seconds elapsed: Double,
                         sources: [Drive], destinations: [Drive]) -> String? {
        guard bytesCopied >= 500_000_000, elapsed >= 10 else { return nil }
        let measured = Double(bytesCopied) / 1_000_000 / elapsed
        let all = sources + destinations
        guard all.count > 1,
              let slowest = all.min(by: { $0.expectedMBps < $1.expectedMBps }),
              let fastest = all.max(by: { $0.expectedMBps < $1.expectedMBps }) else { return nil }
        // The copy ran at about what the slowest link can do, and another link could do much more.
        guard measured <= slowest.expectedMBps * 1.3, fastest.expectedMBps >= measured * 2 else { return nil }
        let why: String
        if slowest.info.bus == .usb2 { why = "connected at USB 2 speed" }
        else if slowest.info.isNetwork { why = "a network drive" }
        else if !slowest.info.isSSD { why = "a hard disk" }
        else if slowest.info.isExFAT { why = "an exFAT drive" }
        else { why = "the slowest drive here" }
        return "This copy ran at \(Int(measured.rounded())) MB/s. The slow link was probably \(slowest.name) (\(why))."
    }

    // MARK: - Closed hints

    static func dismissed(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedDefaultsKey) ?? [])
    }

    static func dismiss(_ id: String, defaults: UserDefaults = .standard) {
        var all = dismissed(defaults: defaults)
        all.insert(id)
        defaults.set(all.sorted(), forKey: dismissedDefaultsKey)
    }

    // MARK: - Live drives

    static func drive(at path: String) -> Drive {
        let capacity = DriveUtilities.capacity(for: path)
        return Drive(path: path, name: FanOutCopier.sourceVolumeName(path),
                     info: DriveSpeedClassifier.info(for: path),
                     totalBytes: capacity.total, availableBytes: capacity.available)
    }
}
