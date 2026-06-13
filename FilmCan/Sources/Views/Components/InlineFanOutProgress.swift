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

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        return f
    }()

    private func formattedBytes(_ bytes: Int64) -> String {
        Self.byteFormatter.string(fromByteCount: max(bytes, 0))
    }

    private func formattedSpeed(_ bytesPerSec: Double) -> String {
        let mb = bytesPerSec / 1_000_000
        if mb < 1 { return String(format: "%.0f KB/s", bytesPerSec / 1_000) }
        if mb < 1000 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
    }

    private func formattedETA(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 60 { return "\(s)s left" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s left" }
        return "\(s / 3600)h \((s % 3600) / 60)m left"
    }

    var body: some View {
        HStack(spacing: 8) {
            FanOutProgressBar(copyFraction: copyFraction,
                              verifyFraction: verifyFraction,
                              status: progress.status)
                .frame(maxWidth: .infinity)
                .layoutPriority(0)

            statusInfo
                .layoutPriority(1)

            if showPill {
                pillBadge
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder
    private var statusInfo: some View {
        switch progress.status {
        case .active:
            statsRow
        case .complete:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.brandGreen)
                Text("Complete")
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.brandGreen)
            }
        case .pending:
            Text("Waiting…")
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textTertiary)
        case .failed(let reason):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.brandRed)
                Text(reason.displayMessage)
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.brandRed)
                    .lineLimit(1)
            }
        }
    }

    /// Data row styled like the reference: bytes copied/total · speed · ETA.
    private var statsRow: some View {
        HStack(spacing: 12) {
            stat(icon: "externaldrive",
                 text: "\(formattedBytes(progress.bytesCompleted)) / \(formattedBytes(progress.bytesTotal))")
            if progress.speedBytesPerSecond > 0 {
                stat(icon: "speedometer", text: formattedSpeed(progress.speedBytesPerSecond))
            }
            if let eta = progress.estimatedTimeRemaining, eta > 0 {
                stat(icon: "clock", text: formattedETA(eta))
            }
        }
        .fixedSize()
    }

    private func stat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textTertiary)
            Text(text)
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textSecondary)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private var pillBadge: some View {
        EmptyView()
    }
}
