import SwiftUI

struct LogSettingsView: View {
    @Binding var logEnabled: Bool
    @Binding var logLocation: BackupConfiguration.LogLocation
    @Binding var customLogPath: String
    @Binding var logFileNameTemplate: String
    let configName: String
    let sampleDestination: String
    let showHeader: Bool
    private let rowSpacing: CGFloat = 20
    private let iconWidth: CGFloat = 32
    private let textWidth: CGFloat = 268
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let logEnabledInfo = InfoPopoverContent(
                title: "Create log file",
                description: "Writes a log file for each transfer with copy and verification details.",
                pros: [
                    "Useful for audit trails and handoff notes",
                    "Helps troubleshoot copy issues"
                ],
                cons: [
                    "Creates extra files"
                ]
            )

            let logDetailsInfo = InfoPopoverContent(
                title: "Log settings",
                description: "Configure where logs are saved and how they are named.",
                notes: [
                    "Location: same as destination keeps logs with the media.",
                    "Custom folder lets you centralize logs.",
                    "Use \"/\" to create subfolders.",
                    "Example folder: `Logs/{date}/{destinationDriveName}`.",
                    "Example file: `logs/transfer_{datetime}`."
                ]
            )

            if showHeader {
                Text("Logs")
                    .font(.headline)
            }

            HStack(spacing: rowSpacing) {
                Image(systemName: "doc.text")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: iconWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Create log file")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: logEnabledInfo)
                    }
                }
                .frame(width: textWidth, alignment: .leading)
                Toggle("", isOn: $logEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .scaleEffect(0.8)
                    .tint(FilmCanTheme.toggleTint)
            }

            if logEnabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        Text("Location")
                            .font(.caption)
                            .foregroundColor(FilmCanTheme.textSecondary)
                        .frame(width: 140, alignment: .leading)
                        Menu {
                            Button("Same as destination") { logLocation = .sameAsDestination }
                            Button("Custom folder") { logLocation = .custom }
                        } label: {
                            HStack(spacing: 6) {
                                Text(logLocation == .sameAsDestination ? "Same as destination" : "Custom folder")
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(FilmCanTheme.card)
                            .cornerRadius(6)
                            .frame(width: 220, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                if logLocation == .custom {
                    HStack(spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        Text("Custom log folder")
                            .font(.caption)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: 140, alignment: .leading)
                    }
                    HStack(spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        Color.clear
                            .frame(width: 140, height: 1)
                        TextField("Select log folder...", text: $customLogPath)
                            .textFieldStyle(.roundedBorder)
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                handleTokenDrop(providers: providers, into: $customLogPath)
                            }
                        Button("Browse...") {
                            selectLogFolder()
                        }
                    }

                    HStack(alignment: .top, spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        Color.clear
                            .frame(width: 140, height: 1)
                        TokenFlowLayout(spacing: 4) {
                            ForEach(folderTokenList, id: \.token) { entry in
                                LogTokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        HStack(spacing: 6) {
                            Text("Log file path and name")
                                .font(.caption)
                                .foregroundColor(FilmCanTheme.textSecondary)
                            InfoPopoverButton(content: logDetailsInfo)
                        }
                        .frame(width: 140, alignment: .leading)
                        TextField("logs/transfer_{datetime}", text: $logFileNameTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 220, alignment: .leading)
                    }

                    HStack(alignment: .top, spacing: rowSpacing) {
                        Color.clear
                            .frame(width: iconWidth + 12, height: 1)
                        Color.clear
                            .frame(width: 140, height: 1)
                        TokenFlowLayout(spacing: 4) {
                            ForEach(folderTokenList, id: \.token) { entry in
                                LogTokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    
    private func selectLogFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            customLogPath = url.path
        }
    }

    private func handleTokenDrop(
        providers: [NSItemProvider],
        into binding: Binding<String>
    ) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let token = object as? String else { return }
                    DispatchQueue.main.async {
                        binding.wrappedValue += token
                    }
                }
                return true
            }
        }
        return false
    }
    
    private var folderTokenList: [(token: String, description: String)] {
        [
            ("{source}", "Original source name (file or folder)."),
            ("{sourceParent}", "Parent folder name of the source."),
            ("{sourceDriveName}", "Name of the drive containing the source."),
            ("{destinationDriveName}", "Name of the drive containing the destination."),
            ("{destination}", "Destination folder name."),
            ("{date}", "Today’s date (YYYYMMDD)."),
            ("{time}", "Current time (HHmmss)."),
            ("{datetime}", "Date and time (YYYYMMDD-HHmmss)."),
            ("{counter}", "Incrementing counter (001, 002, 003…)."),
            ("{filename}", "Source filename without extension."),
            ("{ext}", "File extension (includes the dot)."),
            ("{filecreationdate}", "File creation date (YYYYMMDD)."),
            ("{filemodifieddate}", "File modified date (YYYYMMDD).")
        ]
    }
}

private struct LogTokenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .textSelection(.disabled)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
            .onDrag {
                NSItemProvider(object: text as NSString)
            }
    }
}
