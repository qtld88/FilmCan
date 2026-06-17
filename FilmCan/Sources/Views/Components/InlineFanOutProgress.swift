import SwiftUI

struct InlineFanOutProgress: View {
    let progress: DestProgress
    let showPill: Bool

    private var copyFraction: Double {
        guard progress.bytesTotal > 0 else { return 0 }
        return Double(progress.bytesCompleted) / Double(progress.bytesTotal)
    }

    private var verifyFraction: Double {
        guard progress.verifyBytesTotal > 0 else { return 0 }
        return Double(progress.verifyBytesCompleted) / Double(progress.verifyBytesTotal)
    }

    /// Headline percent. Tracks the COPY bytes — the same basis as the "X / Y GB"
    /// pill — so the number always matches the bytes shown (two destinations at the
    /// same GB read the same %). Verification progress is shown by the green bar
    /// overlay, not folded into this number. Caps at 99% until the destination is
    /// fully done (copied AND, in paranoid, verified) to avoid showing 100% early.
    private var combinedPercent: Int {
        if case .complete = progress.status { return 100 }
        guard progress.bytesTotal > 0 else { return 0 }
        let pct = Double(progress.bytesCompleted) / Double(progress.bytesTotal) * 100
        return min(99, Int(pct.rounded(.towardZero)))
    }

    /// Copy for this dest is done but verification is still running (no copy to
    /// show alongside — e.g. the final file's verify pass).
    private var isVerifyOnly: Bool {
        progress.bytesTotal > 0
            && progress.bytesCompleted >= progress.bytesTotal
            && progress.verifyBytesTotal > 0
            && progress.verifyBytesCompleted < progress.verifyBytesTotal
    }

    // MARK: Formatting (stable: integer units, fixed-width pills)

    /// Whole GB only (decimal GB, matching Finder). No sub-GB churn.
    private func wholeGB(_ bytes: Int64) -> Int {
        Int((Double(max(bytes, 0)) / 1_000_000_000).rounded(.towardZero))
    }

    private var bytesText: String {
        "\(wholeGB(progress.bytesCompleted)) / \(wholeGB(progress.bytesTotal)) GB"
    }

    private var speedText: String {
        let s = progress.speedBytesPerSecond
        guard s > 0 else { return "—" }
        let mb = s / 1_000_000
        if mb < 1 { return String(format: "%.0f KB/s", s / 1_000) }
        if mb < 1000 { return String(format: "%.0f MB/s", mb) }
        return String(format: "%.1f GB/s", s / 1_000_000_000)
    }

    /// ETA straight from the engine, which already smooths it (sustained-rate
    /// EMA) and only changes the value every ~5s. No per-second countdown — a
    /// ticking clock would change the digits every second, which the engine
    /// throttle is specifically there to avoid.
    private var etaText: String {
        guard let eta = progress.estimatedTimeRemaining, eta > 0 else { return "—" }
        let secs = Int(eta.rounded())
        if secs < 60 { return "\(secs)s left" }
        if secs < 3600 { return String(format: "%dm left", (secs + 30) / 60) }
        return String(format: "%dh %02dm left", secs / 3600, (secs % 3600) / 60)
    }

    /// This destination already has every file (nothing to copy this run).
    private var isFullyUpToDate: Bool {
        progress.filesSkipped > 0 && progress.filesTotal > 0
            && progress.filesSkipped >= progress.filesTotal
    }

    /// Resume indication. A fully-up-to-date destination has nothing to copy;
    /// otherwise some files are skipped and the rest are copying.
    private var skipText: String {
        let n = progress.filesSkipped
        let unit = n == 1 ? "file" : "files"
        if isFullyUpToDate {
            return "Already backed up — \(n) \(unit) here, nothing to copy"
        }
        return "Resuming — \(n) \(unit) already here, copying the rest"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FanOutProgressBar(copyFraction: copyFraction,
                                  verifyFraction: verifyFraction,
                                  status: progress.status)
                    .frame(maxWidth: .infinity)
                Text("\(combinedPercent)%")
                    .font(FilmCanFont.label(15))
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                trailingBadge
            }
            if case .active = progress.status {
                pillsRow
                if isVerifyOnly {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield")
                            .font(FilmCanFont.label(9))
                            .foregroundColor(FilmCanTheme.brandGreen)
                        Text("Verifying…")
                            .font(FilmCanFont.label(9))
                            .foregroundColor(FilmCanTheme.textTertiary)
                    }
                }
            }
            if progress.filesSkipped > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(FilmCanFont.label(9))
                        .foregroundColor(FilmCanTheme.textTertiary)
                    Text(skipText)
                        .font(FilmCanFont.label(9))
                        .foregroundColor(FilmCanTheme.textTertiary)
                }
            }
        }
    }

    /// Three fixed-width data pills below the bar. Widths are fixed so the row
    /// never reflows as digits change. Values come straight from the engine,
    /// which throttles speed/ETA changes to ~once every 5s.
    private var pillsRow: some View {
        HStack(spacing: 8) {
            pill(icon: "externaldrive", text: bytesText, width: 104)
            pill(icon: "speedometer", text: speedText, width: 84)
            pill(icon: "clock", text: etaText, width: 96)
        }
    }

    private func pill(icon: String, text: String, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textTertiary)
            Text(text)
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private var trailingBadge: some View {
        switch progress.status {
        case .complete:
            if isFullyUpToDate {
                badge(icon: "checkmark.circle", text: "Up to date", color: FilmCanTheme.brandGreen)
            } else {
                badge(icon: "checkmark.circle.fill", text: "Complete", color: FilmCanTheme.brandGreen)
            }
        case .pending:
            Text("Waiting…")
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textTertiary)
        case .failed(let reason):
            badge(icon: "exclamationmark.triangle.fill", text: reason.displayMessage, color: FilmCanTheme.brandRed)
        case .active:
            EmptyView()
        }
    }

    private func badge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(FilmCanFont.label(10)).foregroundColor(color)
            Text(text).font(FilmCanFont.label(10)).foregroundColor(color).lineLimit(1)
        }
    }
}
