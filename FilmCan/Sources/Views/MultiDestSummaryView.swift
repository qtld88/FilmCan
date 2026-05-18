// Deprecated: use per-row inline fan-out progress via InlineFanOutProgress
import SwiftUI

struct MultiDestSummaryView: View {
    let progresses: [DestProgress]

    private let columns = [GridItem(.adaptive(minimum: 200))]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(progresses) { prog in
                DestProgressTile(progress: prog)
            }
        }
    }
}

struct DestProgressTile: View {
    let progress: DestProgress

    private static let etaFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    var statusColor: Color {
        switch progress.status {
        case .pending: return .gray
        case .active: return .blue
        case .complete: return .green
        case .failed: return .red
        }
    }

    var verifyProgress: Double {
        guard progress.verifyBytesTotal > 0 else { return 0 }
        return min(Double(progress.verifyBytesCompleted) / Double(progress.verifyBytesTotal), 1.0)
    }

    var isVerifying: Bool { progress.verifyBytesTotal > 0 && progress.verifyBytesCompleted < progress.verifyBytesTotal }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row: status dot, name, checkmark
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(progress.displayName).font(.caption).bold()
                Spacer()
                if progress.isComplete {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else if progress.isActive {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }

            // Copy progress bar
            ProgressView(value: progress.progressFraction)
                .tint(statusColor)

            // Verify progress bar (only when verify is active)
            if isVerifying {
                ProgressView(value: verifyProgress)
                    .tint(.purple)
            }

            // Stats row: speed + bytes + files
            HStack {
                Text(progress.speedFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progress.filesCompleted)/\(progress.filesTotal)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Bytes display
            if progress.bytesTotal > 0, !progress.isComplete {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesCompleted, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.bytesTotal, countStyle: .file))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if progress.bytesTotal > 0 {
                Text("\(ByteCountFormatter.string(fromByteCount: progress.bytesCompleted, countStyle: .file))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // ETA
            if let eta = progress.estimatedTimeRemaining, eta > 0 {
                    Text("ETA: \(Self.etaFormatter.string(from: eta) ?? "")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Current file / status
            if !progress.currentFile.isEmpty {
                Text(progress.currentFile)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
            }

            // Full fsync badge
            if progress.requiresFullFsync {
                HStack(spacing: 2) {
                    Image(systemName: "lock.shield").font(.caption2)
                    Text("DO NOT UNPLUG").font(.caption2).bold()
                }
                .foregroundColor(.orange)
            }
        }
        .padding(10)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
    }
}
