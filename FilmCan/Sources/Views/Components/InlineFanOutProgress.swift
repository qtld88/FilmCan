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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                FanOutProgressBar(copyFraction: copyFraction,
                                  verifyFraction: verifyFraction,
                                  status: progress.status)
                    .frame(maxWidth: .infinity)
                Text("\(Int((copyFraction * 100).rounded(.towardZero)))%")
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
            badge(icon: "checkmark.circle.fill", text: "Complete", color: FilmCanTheme.brandGreen)
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
