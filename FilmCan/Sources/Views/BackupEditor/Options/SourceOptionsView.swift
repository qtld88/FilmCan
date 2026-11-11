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
                            .font(FCType.itemTitle)
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Camera drive and folder names to detect",
                                description: "Enter a drive name or a drive/folder path (Drive/Folder). Files are ignored. Wildcards (*) are supported.",
                                notes: [
                                    "ARRI cards named A001, A002: use `A*`.",
                                    "ARRI folder example: `A*/CLIPS` matches `A001/CLIPS`.",
                                    "File names like `A001C001_240101_0010.MOV` are matched in file patterns, not here.",
                                    "`{jour}` stands for the folder of the day, e.g. `CARD*/{jour}`."
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
                            .font(FCType.itemTitle)
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Sound drive and folder names to detect",
                                description: "A drive name, folder name, or substring. Wildcards (*) supported; matching is case-insensitive.",
                                notes: [
                                    "Sound recorders: `SOUND`, `MIXPRE*`, `ZOOM*`, `F8*`, `TASCAM*`.",
                                    "A plain word like `SOUND` matches any volume/folder containing it.",
                                    "`{jour}` stands for the folder of the day: `688*/PROJECT/{jour}` or `688*/*/HAWAII/{jour}`. Recognised names: `26Y11M09`, `20261109`, `2026-11-09`, `261109`. No folder for today ⇒ the latest earlier day."
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

            optionsRow(
                icon: "calendar",
                iconColor: FilmCanTheme.textSecondary,
                title: "Copy only today's folder from sound cards",
                subtitle: "",
                isOn: $viewModel.soundDayFolderAutoDetect,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Copy only today's folder from sound cards",
                    description: "Sound cards are often never wiped and keep each day in a dated folder. When a sound card or sound folder is detected, FilmCan looks up to 3 levels down for a dated folder (26Y11M09, 20261109, 2026-11-09, 261109) and adds the folder of the day instead of the whole card.",
                    pros: [
                        "Earlier days are not copied again",
                        "Works with PROJECT/DATE/... and PROJECT/.../DATE layouts"
                    ],
                    cons: [
                        "No folder dated today ⇒ the latest earlier day is used (night shoots); check it after midnight",
                        "No dated folder found ⇒ the whole card is added"
                    ]
                ),
                availableWidth: availableWidth
            )

            CardsAndRollsSection(viewModel: viewModel, availableWidth: availableWidth)

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


/// "Cards & rolls": camera/sound card recognition, automatic roll numbers, shoot-day counter.
private struct CardsAndRollsSection: View {
    @ObservedObject var viewModel: BackupEditorViewModel
    let availableWidth: CGFloat
    @State private var showResetAlert = false
    @State private var todayDraft = ""
    @FocusState private var todayFocused: Bool

    private func commitTodayDraft() {
        let trimmed = todayDraft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != viewModel.shootDayToday {
            viewModel.shootDayToday = trimmed
        }
        todayDraft = viewModel.shootDayToday
    }

    private var indent: CGFloat { OptionsLayout.iconWidth + OptionsLayout.spacing }

    private func prefixBinding(_ keyPath: WritableKeyPath<RollNumbering, String>) -> Binding<String> {
        Binding(
            get: { viewModel.rollNumbering[keyPath: keyPath] },
            set: { newValue in
                let letters = String(newValue.filter { $0.isLetter }.prefix(2)).uppercased()
                guard !letters.isEmpty else { return }
                viewModel.rollNumbering[keyPath: keyPath] = letters
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionsRow(
                icon: "sdcard",
                iconColor: FilmCanTheme.textSecondary,
                title: "Detect camera and sound cards automatically",
                subtitle: "",
                isOn: $viewModel.cardAutoDetectEnabled,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Detect cards automatically",
                    description: "Recognises a card from the folders the camera writes (ARRI, RED, Sony, Canon, Panasonic, Blackmagic, DJI, GoPro) or a sound card holding only WAV/BWF files, and adds it to the sources. Right-click a source to correct a wrong guess; FilmCan remembers it for that drive.",
                    pros: ["No patterns to maintain", "Sound cards are tagged Sound"],
                    cons: ["A card that is still empty is not recognised"]
                ),
                availableWidth: availableWidth
            )

            optionsRow(
                icon: "number",
                iconColor: FilmCanTheme.textSecondary,
                title: "Number rolls automatically",
                subtitle: "",
                isOn: $viewModel.rollNumbering.enabled,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Number rolls automatically",
                    description: "Roll folders use these names instead of the card name. The rename template no longer applies to roll folders.",
                    pros: ["No more \"Untitled\" cards", "The same card always gets the same roll name"],
                    cons: ["A reformatted card is a new roll"]
                ),
                availableWidth: availableWidth
            )

            if viewModel.rollNumbering.enabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        labeled("Camera prefix") {
                            TextField("A", text: prefixBinding(\.cameraPrefix)).frame(width: 44)
                        }
                        labeled("Sound prefix") {
                            TextField("S", text: prefixBinding(\.soundPrefix)).frame(width: 44)
                        }
                        Stepper("Digits: \(viewModel.rollNumbering.digits)",
                                value: $viewModel.rollNumbering.digits, in: 2...4)
                    }
                    HStack(spacing: 14) {
                        Stepper("Camera start: \(viewModel.rollNumbering.cameraStart)",
                                value: $viewModel.rollNumbering.cameraStart, in: 1...9999)
                        Stepper("Sound start: \(viewModel.rollNumbering.soundStart)",
                                value: $viewModel.rollNumbering.soundStart, in: 1...9999)
                    }
                    Toggle("ARRI and RED keep their reel name", isOn: $viewModel.rollNumbering.keepCameraReelNames)
                    Text(viewModel.nextRollSummary)
                        .font(FCType.meta)
                        .foregroundColor(FilmCanTheme.textSecondary)
                    Button("Reset numbering…") { showResetAlert = true }
                        .buttonStyle(.bordered)
                }
                .font(FCType.body)
                .padding(.leading, indent)
                .alert("Reset numbering?", isPresented: $showResetAlert) {
                    Button("Reset", role: .destructive) { viewModel.resetRollNumbering() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Cards seen before will be numbered again from the start values. Backups already made keep their folder names.")
                }
            }

            optionsRow(
                icon: "calendar",
                iconColor: FilmCanTheme.textSecondary,
                title: "Advance the shoot day automatically",
                subtitle: "",
                isOn: $viewModel.dayAutoAdvance,
                textWidth: OptionsLayout.basicTextWidth,
                info: InfoPopoverContent(
                    title: "Advance the shoot day automatically",
                    description: "On the first backup of each new day, {day} goes up by one (Day01 → Day02). The Day field is the starting value."
                ),
                availableWidth: availableWidth
            )

            if viewModel.dayAutoAdvance {
                HStack(spacing: 6) {
                    Text("Today:").foregroundColor(FilmCanTheme.textSecondary)
                    TextField("Day01", text: $todayDraft)
                        .frame(width: 80)
                        .focused($todayFocused)
                        .onSubmit(commitTodayDraft)
                        .help("Shoot day used by backups made today. Tomorrow's first backup goes up by one from this value.")
                }
                .font(FCType.meta)
                .padding(.leading, indent)
                .onAppear { todayDraft = viewModel.shootDayToday }
                .onChange(of: todayFocused) { focused in
                    if !focused { commitTodayDraft() }
                }
            }
        }
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundColor(FilmCanTheme.textSecondary)
            content()
        }
    }
}
