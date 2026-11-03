import SwiftUI

struct LogsOptionsView: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        LogSettingsView(
            logEnabled: Binding(
                get: { viewModel.logEnabled },
                set: { viewModel.logEnabled = $0 }
            ),
            logLocation: Binding(
                get: { viewModel.logLocation },
                set: { viewModel.logLocation = $0 }
            ),
            customLogPath: Binding(
                get: { viewModel.customLogPath },
                set: { viewModel.customLogPath = $0 }
            ),
            logFileNameTemplate: Binding(
                get: { viewModel.logFileNameTemplate },
                set: { viewModel.logFileNameTemplate = $0 }
            ),
            configName: viewModel.name,
            sampleDestination: viewModel.destinations.first ?? "Destination",
            showHeader: false
        )
        reportRow
        }
    }

    private var reportInfo: InfoPopoverContent {
        InfoPopoverContent(
            title: "PDF report",
            description: "Writes a PDF next to each log with one thumbnail per clip, sizes, durations and checksums.",
            cons: ["Takes extra time after the copy (runs in the background)"],
            notes: ["ARRI, RED and BRAW clips show an icon unless a QuickLook plugin is installed."]
        )
    }

    private var reportRow: some View {
        HStack(spacing: 20) {
            Image(systemName: "doc.richtext")
                .font(.title3)
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 32)
            HStack(spacing: 6) {
                Text("PDF report with thumbnails")
                    .font(FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                InfoPopoverButton(content: reportInfo)
            }
            .frame(width: 268, alignment: .leading)
            Toggle("", isOn: Binding(
                get: { viewModel.config.reportEnabled },
                set: { viewModel.config.reportEnabled = $0; viewModel.save() }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .scaleEffect(0.8)
            .tint(FilmCanTheme.toggleTint)
        }
        .disabled(!viewModel.logEnabled)
        .help(viewModel.logEnabled ? "" : "Turn on “Create log file” first")
    }
}
