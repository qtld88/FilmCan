import SwiftUI

struct DestinationsOptionsView: View {
    @ObservedObject var model: OrganizationEditorModel
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat

    @State private var showRenameOnlyPatterns = false
    @State private var isFolderDropTargeted = false
    @State private var isRenameDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            netflixMetadataSection
            autoDetectSection
            organizationOptionsContent
        }
    }

    // MARK: - Netflix Metadata

    @ViewBuilder
    private var netflixMetadataSection: some View {
        if model.selectedOrganizationPresetName == OrganizationPreset.netflixIngestName {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shoot metadata")
                    .font(FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                netflixMetaField("Episode / Block", placeholder: "EP103 / B01",
                                 text: model.binding(\.episode))
                netflixMetaField("Day", placeholder: "Day05 / D05",
                                 text: model.binding(\.day))
                netflixMetaField("Unit", placeholder: "MU / 2U",
                                 text: model.binding(\.unit))
                netflixMetaField("Camera format", placeholder: "ARRI / RED (optional)",
                                 text: model.binding(\.cameraFormat))

                folderTemplatesSection
                netflixReadinessHint
            }
            .padding(.bottom, 8)
        }
    }

    private func netflixMetaField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: OptionsLayout.spacing) {
            Text(label)
                .font(FilmCanFont.body(12))
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 130, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
        }
    }

    /// Editable Camera and Sound destination sub-paths for the Netflix preset. The
    /// roll folder is appended automatically; tokens {date} {episode} {day} {unit}
    /// {cameraFormat} are supported.
    private var folderTemplatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Folder templates")
                    .font(FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                InfoPopoverButton(content: InfoPopoverContent(
                    title: "Folder templates",
                    description: "Where each source lands at the destination, by media type. The roll folder is appended automatically.",
                    notes: ["Camera sources use the Camera folder; Sound-tagged sources use the Sound folder.",
                            "Tokens: {date} {episode} {day} {unit} {cameraFormat}.",
                            "Netflix defaults: Camera_Media/{cameraFormat} and Sound_Media."]
                ))
            }
            .padding(.top, 4)
            netflixMetaField("Camera folder", placeholder: "{date}_{episode}_{day}_{unit}/Camera_Media/{cameraFormat}",
                             text: model.binding(\.cameraFolderTemplate))
            netflixMetaField("Sound folder", placeholder: "{date}_{episode}_{day}_{unit}/Sound_Media",
                             text: model.binding(\.soundFolderTemplate))
        }
    }

    @ViewBuilder
    private var netflixReadinessHint: some View {
        let count = viewModel.destinations.count
        HStack(spacing: 6) {
            Image(systemName: count < 3 ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundColor(count < 3 ? .orange : FilmCanTheme.textTertiary)
            Text("Netflix recommends ≥3 copies on ≥2 media types, with ≥1 off-site. You have \(count) destination\(count == 1 ? "" : "s").")
                .font(FilmCanFont.body(11))
                .foregroundColor(FilmCanTheme.textSecondary)
        }
        .padding(.top, 2)
    }

    // MARK: - Auto-detect destinations

    private var autoDetectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            let destinationAutoDetectInfo = InfoPopoverContent(
                title: "Auto-detect destinations",
                description: "Scans connected drives and automatically adds destinations whose names or subfolders match your patterns.",
                pros: [
                    "Hands-free destination selection",
                    "Avoids missing a backup drive"
                ],
                cons: [
                    "Broad patterns can add the wrong drive",
                    "May select a drive with low space"
                ]
            )

            optionsRow(
                icon: "externaldrive",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect destinations",
                subtitle: "",
                isOn: $viewModel.destinationAutoDetectEnabled,
                textWidth: OptionsLayout.basicTextWidth,
                info: destinationAutoDetectInfo,
                availableWidth: availableWidth
            )

            if viewModel.destinationAutoDetectEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Drive and folder names to detect")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Drive and folder names to detect",
                                description: "Enter a drive name or a drive/folder path (Drive/Folder). Files are ignored. Wildcards (*) are supported.",
                                notes: [
                                    "ARRI card example for backup drives: `ARRI_BACKUP*`.",
                                    "Drive folder path example: `MEDIA/ARRI` matches MEDIA/ARRI.",
                                    "File names like `A001C001_240101_0010.MOV` are matched in file patterns, not here."
                                ]
                            )
                        )
                    }
                    PatternEditor(
                        title: "",
                        placeholder: "BACKUP\nRAID*\nMEDIA*/Projects",
                        patterns: Binding(
                            get: { viewModel.destinationAutoDetectPatterns },
                            set: { viewModel.destinationAutoDetectPatterns = $0 }
                        ),
                        showsTitle: false
                    )
                }
                .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Organization options

    private var organizationOptionsContent: some View {
        Group {
            if let presetBinding = model.editingOrganizationPresetBinding {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: OptionsLayout.spacing) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: OptionsLayout.iconWidth)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Folder template")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                InfoPopoverButton(
                                    content: InfoPopoverContent(
                                        title: "Folder template",
                                        description: "Creates the folder structure inside the destination.",
                                        notes: [
                                            "Use \"/\" for subfolders.",
                                            "Example: `ARRI/{sourceDriveName}/DAY_{date}/CARD_{source}`."
                                        ]
                                    )
                                )
                            }
                        }
                        .frame(width: optionsResolvedTextWidth(OptionsLayout.textWidth, availableWidth: availableWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useFolderTemplate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: OptionsLayout.toggleWidth, alignment: .leading)
                    }

                    if presetBinding.useFolderTemplate.wrappedValue {
                        TextField("RUSHES/DAY_{counter}_{date}/CARD_{source}", text: presetBinding.folderTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onDrop(of: [.text], isTargeted: $isFolderDropTargeted) { providers in
                                model.handleTokenDrop(providers: providers, into: presetBinding.folderTemplate)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isFolderDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                            .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                        TokenFlowLayout(spacing: 10) {
                            ForEach(model.tokenList, id: \.token) { entry in
                                TokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)

                        DisclosureGroup(isExpanded: $showRenameOnlyPatterns) {
                            PatternEditor(
                                title: "",
                                placeholder: "*.mp4",
                                patterns: presetBinding.renameOnlyPatterns,
                                showsTitle: false
                            )
                        } label: {
                            HStack {
                                Text("Rename only patterns (optional)")
                                InfoPopoverButton(
                                    content: InfoPopoverContent(
                                        title: "Rename only patterns",
                                        description: "Only rename files that match these patterns.",
                                        notes: [
                                            "Example: `*.mp4` to rename only proxies.",
                                            "ARRI filename example: `A001C001_240101_0010.MOV`."
                                        ]
                                    )
                                )
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showRenameOnlyPatterns.toggle() }
                        }
                        .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                    }

                    HStack(spacing: OptionsLayout.spacing) {
                        Image(systemName: "doc.text")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: OptionsLayout.iconWidth)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("File name template")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                InfoPopoverButton(
                                    content: InfoPopoverContent(
                                        title: "File name template",
                                        description: "Renames each copied item before it is placed in the destination.",
                                        notes: [
                                            "Use tokens like `{filename}` and `{counter}`.",
                                            "Combine with Rename only patterns to target specific files."
                                        ]
                                    )
                                )
                            }
                        }
                        .frame(width: optionsResolvedTextWidth(OptionsLayout.textWidth, availableWidth: availableWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useRenameTemplate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: OptionsLayout.toggleWidth, alignment: .leading)
                    }

                    if presetBinding.useRenameTemplate.wrappedValue {
                        TextField("{filename}{ext}", text: presetBinding.renameTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onDrop(of: [.text], isTargeted: $isRenameDropTargeted) { providers in
                                model.handleTokenDrop(providers: providers, into: presetBinding.renameTemplate)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRenameDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                            .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                        TokenFlowLayout(spacing: 10) {
                            ForEach(model.tokenList, id: \.token) { entry in
                                TokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                    }

                    HStack(spacing: OptionsLayout.spacing) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: OptionsLayout.iconWidth)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Custom date for tokens")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                InfoPopoverButton(
                                    content: InfoPopoverContent(
                                        title: "Custom date for tokens",
                                        description: "Use a specific date for {date}, {time}, and {datetime}.",
                                        pros: [
                                            "Keeps folder names aligned with shoot day",
                                            "Helps re-ingests match previous structure"
                                        ],
                                        cons: [
                                            "Easy to forget to turn off"
                                        ]
                                    )
                                )
                            }
                        }
                        .frame(width: optionsResolvedTextWidth(OptionsLayout.textWidth, availableWidth: availableWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useCustomDate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: OptionsLayout.toggleWidth, alignment: .leading)
                    }

            if presetBinding.useCustomDate.wrappedValue {
                DatePicker(
                    "Date",
                    selection: presetBinding.customDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
                .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
            }

                }
                .padding(.bottom, 16)
            } else {
                Text("Select a preset to edit destination organization settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
