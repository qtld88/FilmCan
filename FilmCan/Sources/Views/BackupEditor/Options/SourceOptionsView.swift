import SwiftUI

struct SourceOptionsView: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat

    @State var showCopyOnlyPatterns = false
    @State var showIncludePatterns = false
    @State var showExcludePatterns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sourceAutoDetectInfo = InfoPopoverContent(
                title: "Auto-detect camera sources",
                description: "Scans connected drives and automatically adds sources whose names or subfolders match your patterns.",
                pros: [
                    "Hands-free source selection",
                    "Faster ingest when multiple cards are connected"
                ],
                cons: [
                    "Broad patterns can pick up unintended drives",
                    "May add partial sources if a card is still writing"
                ]
            )

            optionsRow(
                icon: "externaldrive",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect camera sources",
                subtitle: "",
                isOn: $viewModel.sourceAutoDetectEnabled,
                textWidth: OptionsLayout.basicTextWidth,
                info: sourceAutoDetectInfo,
                availableWidth: availableWidth
            )

            if viewModel.sourceAutoDetectEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Camera drive and folder names to detect")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Camera drive and folder names to detect",
                                description: "Enter a drive name or a drive/folder path (Drive/Folder). Files are ignored. Wildcards (*) are supported.",
                                notes: [
                                    "ARRI cards named A001, A002: use `A*`.",
                                    "ARRI folder example: `A*/CLIPS` matches `A001/CLIPS`.",
                                    "File names like `A001C001_240101_0010.MOV` are matched in file patterns, not here."
                                ]
                            )
                        )
                    }
                    PatternEditor(
                        title: "",
                        placeholder: "A*\nA*/CLIPS\nPRIVATE",
                        patterns: Binding(
                            get: { viewModel.sourceAutoDetectPatterns },
                            set: { viewModel.sourceAutoDetectPatterns = $0 }
                        ),
                        showsTitle: false
                    )
                }
                .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                .padding(.top, 4)
            }

            optionsRow(
                icon: "waveform",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect sound sources",
                subtitle: "",
                isOn: $viewModel.soundAutoDetectEnabled,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Auto-detect sound sources",
                    description: "Tags a source as Sound (routed to Sound_Media under the Netflix preset) when its drive or folder name matches one of these patterns.",
                    pros: ["No need to flip each sound card to Sound by hand"],
                    cons: ["A broad pattern could mis-tag a camera card as sound"]
                ),
                availableWidth: availableWidth
            )

            if viewModel.soundAutoDetectEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Sound drive and folder names to detect")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Sound drive and folder names to detect",
                                description: "A drive name, folder name, or substring. Wildcards (*) supported; matching is case-insensitive.",
                                notes: [
                                    "Sound recorders: `SOUND`, `MIXPRE*`, `ZOOM*`, `F8*`, `TASCAM*`.",
                                    "A plain word like `SOUND` matches any volume/folder containing it."
                                ]
                            )
                        )
                    }
                    PatternEditor(
                        title: "",
                        placeholder: "SOUND\nMIXPRE*\nZOOM*",
                        patterns: Binding(
                            get: { viewModel.soundAutoDetectPatterns },
                            set: { viewModel.soundAutoDetectPatterns = $0 }
                        ),
                        showsTitle: false
                    )
                }
                .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                .padding(.top, 4)
            }

            let copyContentsInfo = InfoPopoverContent(
                title: "Copy folder contents only",
                description: "When on, FilmCan skips the top-level folder and copies only its contents into the destination.",
                pros: [
                    "Avoids an extra nested folder",
                    "Merges contents into an existing destination"
                ],
                cons: [
                    "Higher risk of name collisions",
                    "Less obvious where the files came from"
                ]
            )

            optionsRow(
                icon: "folder.badge.minus",
                iconColor: FilmCanTheme.textSecondary,
                title: "Copy folder contents only",
                subtitle: "",
                isOn: $viewModel.copyFolderContents,
                textWidth: OptionsLayout.basicTextWidth,
                info: copyContentsInfo,
                availableWidth: availableWidth
            )

            if let presetBinding = editingOrganizationPresetBinding {
                fileFilterPatternsSection(presetBinding: presetBinding)
                    .padding(.leading, OptionsLayout.iconWidth + OptionsLayout.spacing)
                    .padding(.top, 8)
            }
        }
    }

    private var editingOrganizationPresetBinding: Binding<OrganizationPreset>? {
        if let binding = selectedPresetBinding {
            return binding
        }
        return Binding(
            get: { viewModel.localOrganizationPreset },
            set: { viewModel.localOrganizationPreset = $0 }
        )
    }

    private var selectedPresetBinding: Binding<OrganizationPreset>? {
        guard let id = viewModel.selectedOrganizationPresetId,
              let index = viewModel.organizationPresets.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { viewModel.organizationPresets[index] },
            set: { newValue in
                var presets = viewModel.organizationPresets
                if index < presets.count {
                    presets[index] = newValue
                    viewModel.organizationPresets = presets
                }
            }
        )
    }

    private var defaultExcludePatterns: [String] {
        DefaultExcludes.patterns
    }

    private func hasCustomFilterPatterns(_ preset: OrganizationPreset) -> Bool {
        SourceFilterMatching.hasCustomFilterPatterns(
            include: preset.includePatterns,
            exclude: preset.excludePatterns,
            copyOnly: preset.copyOnlyPatterns
        )
    }

    private func excludePatternsBinding(
        _ presetBinding: Binding<OrganizationPreset>
    ) -> Binding<[String]> {
        Binding(
            get: {
                let existing = presetBinding.excludePatterns.wrappedValue
                return existing.isEmpty ? defaultExcludePatterns : existing
            },
            set: { newValue in
                presetBinding.excludePatterns.wrappedValue = newValue
            }
        )
    }

    private func fileFilterPatternsSection(
        presetBinding: Binding<OrganizationPreset>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup(isExpanded: $showCopyOnlyPatterns) {
                PatternEditor(
                    title: "",
                    placeholder: "*.mov\n*.mp4",
                    patterns: presetBinding.copyOnlyPatterns,
                    showsTitle: false
                )
            } label: {
                HStack {
                    Text("Copy-only patterns (optional)")
                    InfoPopoverButton(
                        content: InfoPopoverContent(
                            title: "Copy-only patterns",
                            description: "Copies only files that match these patterns while keeping the full folder structure.",
                            notes: [
                                "ARRI example: `*.ari` or `*.mov` to keep only camera clips.",
                                "Match a specific filename like `A001C001_240101_0010.MOV`.",
                                "Combine with folders: `A*/CLIPS/*.ari`."
                            ]
                        )
                    )
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { showCopyOnlyPatterns.toggle() }
            }

            DisclosureGroup(isExpanded: $showIncludePatterns) {
                PatternEditor(
                    title: "",
                    placeholder: "A*\nB*",
                    patterns: presetBinding.includePatterns,
                    showsTitle: false
                )
            } label: {
                HStack {
                    Text("Include patterns (optional)")
                    InfoPopoverButton(
                        content: InfoPopoverContent(
                            title: "Include patterns",
                            description: "Only include items that match these patterns. Everything else is ignored.",
                            notes: [
                                "ARRI card folders: `A*` includes A001, A002.",
                                "ARRI clip files: `*.ari` or `*.mov`.",
                                "Specific filename: `A001C001_240101_0010.MOV`."
                            ]
                        )
                    )
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { showIncludePatterns.toggle() }
            }

            DisclosureGroup(isExpanded: $showExcludePatterns) {
                PatternEditor(
                    title: "",
                    placeholder: "*.tmp\n.DS_Store",
                    patterns: excludePatternsBinding(presetBinding),
                    showsTitle: false
                )
            } label: {
                HStack {
                    Text("Exclude patterns (optional)")
                    InfoPopoverButton(
                        content: InfoPopoverContent(
                            title: "Exclude patterns",
                            description: "Always exclude items that match these patterns.",
                            notes: [
                                "Exclude proxies: `*/PROXIES/` or `*_proxy.MOV`.",
                                "Exclude cache: `*/Cache/`.",
                                "Exclude hidden files: `.DS_Store`."
                            ]
                        )
                    )
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { showExcludePatterns.toggle() }
            }
        }
    }
}
