import Foundation

struct DestProgress: Identifiable, Equatable {
    let id: String
    let displayName: String
    var status: DestStatus = .pending
    var bytesCompleted: Int64 = 0
    var bytesTotal: Int64 = 0
    var filesCompleted: Int = 0
    var filesTotal: Int = 0
    var currentFile: String = ""
    var speedBytesPerSecond: Double = 0
    var estimatedTimeRemaining: TimeInterval?
    var verifyMode: VerifyMode = .paranoid
    var verifyBytesCompleted: Int64 = 0
    var verifyBytesTotal: Int64 = 0
    var failureReason: String?
    var requiresFullFsync: Bool = false
    /// Files already backed up and skipped this run (resume skip).
    var filesSkipped: Int = 0
}

extension DestProgress {
    /// Share of this destination's work done, copy AND verify, 0...1. Same rule
    /// as the card's headline percent, so the tab bar and the card agree.
    var workFraction: Double {
        if case .complete = status { return 1 }
        let total = bytesTotal + verifyBytesTotal
        guard total > 0 else { return 0 }
        let done = min(bytesCompleted, bytesTotal) + min(verifyBytesCompleted, verifyBytesTotal)
        return Swift.min(1, Swift.max(0, Double(done) / Double(total)))
    }

    var isVerifyOnly: Bool {
        bytesTotal > 0
            && bytesCompleted >= bytesTotal
            && verifyBytesTotal > 0
            && verifyBytesCompleted < verifyBytesTotal
    }
}

extension Array where Element == DestProgress {
    /// Destinations fed by one fan-out copy move together: the source is read
    /// once and every drive waits for the slowest, so the job ends when the
    /// slowest destination ends. Each card used to show its own measured speed
    /// and ETA (an SSD next to an HDD read "83 MB/s, 14m left" vs
    /// "44 MB/s, 28m left"), which contradicted that. Every active destination
    /// now shows the job's pace: the slowest speed and the longest time left.
    /// Bars and percentages stay per destination.
    func sharingJobTiming() -> [DestProgress] {
        let active = filter { $0.status == .active }
        guard active.count > 1 else { return self }
        let eta = active.compactMap(\.estimatedTimeRemaining).filter { $0 > 0 }.max()
        let speed = active.map(\.speedBytesPerSecond).filter { $0 > 0 }.min()
        return map { row in
            guard row.status == .active else { return row }
            var shared = row
            if let eta { shared.estimatedTimeRemaining = eta }
            if let speed { shared.speedBytesPerSecond = speed }
            return shared
        }
    }

    /// The row for one destination, with the job's shared speed and ETA.
    func sharedTimingRow(for id: String) -> DestProgress? {
        sharingJobTiming().first { $0.id == id }
    }
}
