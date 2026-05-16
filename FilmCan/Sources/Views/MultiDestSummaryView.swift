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

    var statusColor: Color {
        switch progress.status {
        case .pending: return .gray
        case .active: return .blue
        case .complete: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(progress.displayName).font(.caption).bold()
                Spacer()
                if progress.isActive {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 12, height: 12)
                }
            }
            ProgressView(value: progress.progressFraction)
                .tint(statusColor)
            HStack {
                Text(progress.speedFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(progress.filesCompleted)/\(progress.filesTotal)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            if !progress.currentFile.isEmpty {
                Text(progress.currentFile)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.secondary)
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
