import SwiftUI

struct DestResultRow: View {
    let result: DestResult
    var onRetry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(result.success ? .green : .red)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.displayName)
                    .font(.subheadline).bold()
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: result.bytesTransferred, countStyle: .file))
                    Text("•")
                    Text("\(result.filesTransferred) files")
                    if result.filesSkipped > 0 {
                        Text("•")
                        Text("\(result.filesSkipped) skipped")
                            .foregroundColor(.secondary)
                    }
                    if result.filesFailedAfterCopy > 0 {
                        Text("•")
                        Text("\(result.filesFailedAfterCopy) failed")
                            .foregroundColor(.red)
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)

                if !result.success, let reason = result.failureReason {
                    Text(reason.displayMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                if let mhl = result.mhlPath {
                    Text("MHL: \(mhl)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(result.verifyMode.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.1fs", result.durationSec))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !result.success, let onRetry {
                Button("Retry", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}
