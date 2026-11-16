import SwiftUI
import AppKit

/// Settings › History: where the Mac keeps a copy of every backup report.
struct ReportArchiveSettingsSection: View {
    @AppStorage(ReportArchive.DefaultsKey.enabled) private var enabled: Bool = true
    @AppStorage(ReportArchive.DefaultsKey.folder) private var folder: String = ""

    private var baseURL: URL { ReportArchive.baseURL() }

    var body: some View {
        Section("Reports") {
            Toggle("Keep a copy of every report on this Mac", isOn: $enabled)
                .tint(FilmCanTheme.toggleTint)
            HStack {
                Text(baseURL.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(baseURL.path)
                Spacer()
                Button("Choose…") { chooseFolder() }
                if !folder.isEmpty {
                    Button("Reset") { folder = "" }
                }
                Button("Show in Finder") { showInFinder() }
            }
            .disabled(!enabled)
            Text("After a backup that writes a PDF report, the PDF and the checksum lists are also copied here, sorted by movie, then day, then drive. You can read them with the drives unplugged. Nothing is sent anywhere.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = baseURL.deletingLastPathComponent()
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            folder = url.path
        }
    }

    private func showInFinder() {
        let url = baseURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}
