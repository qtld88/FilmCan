import SwiftUI

struct DryRunSheet: View {
    let report: DryRunReport
    let onDismiss: () -> Void
    let onProceed: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Pre-flight Report")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Summary header
                    HStack {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundColor(.accentColor)
                        Text("Source: \(report.sourceName)")
                            .font(.headline)
                    }
                    Text("\(report.totalFiles) files  •  \(ByteCountFormatter.string(fromByteCount: report.totalBytes, countStyle: .file))")
                        .foregroundColor(.secondary)

                    Divider()

                    // Per-destination estimates
                    ForEach(report.destinations) { dest in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(dest.requiresFullFsync ? Color.orange : Color.green)
                                    .frame(width: 8, height: 8)
                                Text(dest.displayName)
                                    .font(.subheadline).bold()
                                Spacer()
                                Text("~\(String(format: "%.0f", dest.estimatedSpeedMBps)) MB/s")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack(spacing: 16) {
                                Label(dest.classLabel, systemImage: "externaldrive")
                                Label("\(String(format: "%.0f", dest.estimatedTotalSec))s", systemImage: "clock")
                                Text("\(dest.chunkSize / 1024) KB chunks")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .font(.caption)

                            if dest.requiresFullFsync {
                                Label("F_FULLFSYNC active — safer but slower",
                                      systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(10)
                        .background(Color(.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(8)
                    }

                    // Speed disparities
                    let disparities = report.speedDisparities
                    if !disparities.isEmpty {
                        Divider()
                        Text("⚠ Speed Disparities").font(.headline)
                        ForEach(disparities) { d in
                            if let warn = d.warning {
                                HStack(alignment: .top) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.yellow)
                                    Text(warn)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()
            HStack(spacing: 16) {
                Button("Cancel") { onDismiss() }
                    .keyboardShortcut(.escape)
                Button("Start Copy") { onProceed() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .frame(width: 500, height: 500)
    }
}
