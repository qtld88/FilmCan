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

    private func formattedSpeed(_ bytesPerSec: Double) -> String {
        let mb = bytesPerSec / 1_000_000
        if mb < 1 { return String(format: "%.0f KB/s", bytesPerSec / 1_000) }
        if mb < 1000 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.2f GB/s", bytesPerSec / 1_000_000_000)
    }

    private var displayFile: String {
        progress.currentFile.isEmpty ? "Copying…" : progress.currentFile.fileName
    }

    var body: some View {
        HStack(spacing: 8) {
            FanOutProgressBar(copyFraction: copyFraction,
                              verifyFraction: verifyFraction,
                              status: progress.status)
                .frame(maxWidth: .infinity)
                .layoutPriority(0)

            statusInfo
                .frame(width: 120, alignment: .trailing)
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
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill")
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.brandYellow)
                Text(displayFile)
                    .font(FilmCanFont.label(10))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

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

    @ViewBuilder
    private var pillBadge: some View {
        switch progress.status {
        case .active:
            Text(formattedSpeed(progress.speedBytesPerSecond))
                .font(FilmCanFont.label(10))
                .foregroundColor(FilmCanTheme.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(FilmCanTheme.panel)
                .cornerRadius(4)
        case .complete, .failed, .pending:
            EmptyView()
        }
    }
}

private extension String {
    var fileName: String {
        split(separator: "/").last.map(String.init) ?? self
    }
}
