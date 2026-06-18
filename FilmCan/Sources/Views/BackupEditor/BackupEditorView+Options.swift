import SwiftUI
import Foundation

extension BackupEditorView {
    private var selectedOrganizationPresetName: String {
        let presets = viewModel.organizationPresets
        if let id = viewModel.selectedOrganizationPresetId,
           let preset = presets.first(where: { $0.id == id }) {
            return preset.name
        }
        return "Off"
    }

    var selectedOrganizationPreset: OrganizationPreset? {
        let presets = viewModel.organizationPresets
        guard let id = viewModel.selectedOrganizationPresetId else { return nil }
        return presets.first { $0.id == id }
    }

    /// Preset for the destination-path preview: the effective preset with the user's
    /// edited Camera/Sound folder templates applied (matching the run-time resolver).
    var previewOrganizationPreset: OrganizationPreset? {
        guard var preset = effectiveOrganizationPreset else { return nil }
        if preset.name == OrganizationPreset.netflixIngestName {
            let cam = viewModel.cameraFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cam.isEmpty { preset.folderTemplate = viewModel.cameraFolderTemplate }
            let snd = viewModel.soundFolderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snd.isEmpty { preset.soundFolderTemplate = viewModel.soundFolderTemplate }
        }
        return preset
    }

    var previewShootMetadata: ShootMetadata {
        ShootMetadata(episode: viewModel.episode, day: viewModel.day,
                      unit: viewModel.unit, cameraFormat: viewModel.cameraFormat)
    }

    var effectiveOrganizationPreset: OrganizationPreset? {
        if let preset = selectedOrganizationPreset { return preset }
        let local = viewModel.localOrganizationPreset
        let hasTemplate = local.useFolderTemplate
            && !local.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRename = local.useRenameTemplate
            && !local.renameTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPatterns = hasCustomFilterPatterns(local)
        let hasCustomDate = local.useCustomDate
        guard hasTemplate || hasRename || hasPatterns || hasCustomDate else { return nil }
        return local
    }

    private var customDateStatusText: String? {
        guard let preset = effectiveOrganizationPreset, preset.useCustomDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        return "Custom date is set on \(formatter.string(from: preset.customDate))"
    }

    private var isLocalOrganizationPreset: Bool {
        viewModel.selectedOrganizationPresetId == nil
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

    private var tokenList: [(token: String, description: String)] {
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

    private var defaultExcludePatterns: [String] {
        RsyncOptions.defaultExcludedPatterns
    }

    private func normalizedPatterns(_ patterns: [String]) -> [String] {
        patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func hasCustomFilterPatterns(_ preset: OrganizationPreset) -> Bool {
        let include = normalizedPatterns(preset.includePatterns)
        let copyOnly = normalizedPatterns(preset.copyOnlyPatterns)
        if !include.isEmpty || !copyOnly.isEmpty {
            return true
        }
        let exclude = normalizedPatterns(preset.excludePatterns)
        let defaultSet = Set(defaultExcludePatterns)
        let nonDefaultExcludes = exclude.filter { !defaultSet.contains($0) }
        return !nonDefaultExcludes.isEmpty
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

    private func handleTokenDrop(providers: [NSItemProvider], into binding: Binding<String>) -> Bool {
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

    private func startEditingPresetName() {
        isEditingPresetName = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isPresetNameFocused = true
        }
    }

    private func finishEditingPresetName() {
        isEditingPresetName = false
        isPresetNameFocused = false
    }
    
    private func optionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        textWidth: CGFloat? = nil,
        helpText: String? = nil,
        info: InfoPopoverContent? = nil
    ) -> some View {
        let resolvedTextWidth = resolvedTextWidth(textWidth ?? optionTextWidth)
        let row = HStack(spacing: optionSpacing) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(FilmCanFont.label(13))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    if let info {
                        InfoPopoverButton(content: info)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(FilmCanFont.body(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
            }
            .frame(width: resolvedTextWidth, alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .scaleEffect(0.8)
                .tint(FilmCanTheme.toggleTint)
                .frame(width: optionToggleWidth, alignment: .leading)
        }
        if let helpText {
            return AnyView(row.help(helpText))
        }
        return AnyView(row)
    }

    private func advancedOptionRow(
        icon: String? = nil,
        iconColor: Color = .secondary,
        title: String,
        subtitle: String,
        titleColor: Color = .primary,
        subtitleColor: Color = .secondary,
        isOn: Binding<Bool>,
        helpText: String? = nil
    ) -> some View {
        let row = HStack(spacing: optionSpacing) {
            if let icon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FilmCanFont.label(13))
                    .foregroundColor(titleColor)
                Text(subtitle)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(subtitleColor)
            }
            .frame(width: resolvedTextWidth(optionTextWidth), alignment: .leading)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .scaleEffect(0.8)
                .tint(FilmCanTheme.toggleTint)
                .frame(width: optionToggleWidth, alignment: .leading)
        }

        if let helpText {
            return AnyView(row.help(helpText))
        }
        return AnyView(row)
    }

    private func disclosureCard<Content: View>(
        title: String,
        icon: String? = nil,
        iconColor: Color = .secondary,
        width: CGFloat? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            content()
                .padding(.top, 12)
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                }
                Text(title)
                    .font(icon == nil ? FilmCanFont.title(16) : FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.wrappedValue.toggle() }
        }
        .padding(12)
        .background(FilmCanTheme.panel)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
        )
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    func optionsSection() -> some View {
        optionsTabCard
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { optionsAvailableWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { optionsAvailableWidth = $0 }
                }
            )
            .padding(.horizontal, optionsHorizontalPadding)
    }

    private var optionsTabCard: some View {
        let isWide = effectiveOptionsWidth >= 600
        return VStack(alignment: .leading, spacing: isOptionsCollapsed ? 0 : 16) {
            optionsTabBar
            // Keep the tab content mounted and just hide it (height 0) when collapsed.
            // The Destinations tab carries the heavy organization editor (TextEditor-
            // backed pattern editors, 26 draggable token chips); mounting/unmounting it
            // on every open/close was the slowness. Staying mounted makes toggling free.
            VStack(alignment: .leading, spacing: 16) {
                Divider()
                    .background(FilmCanTheme.cardStroke)
                optionsTabContent
            }
            .frame(height: isOptionsCollapsed ? 0 : nil, alignment: .top)
            .clipped()
            .opacity(isOptionsCollapsed ? 0 : 1)
            .allowsHitTesting(!isOptionsCollapsed)
        }
        .onAppear { if selectedOptionsTab == .destinations { didLoadDestinations = true } }
        .onChange(of: selectedOptionsTab) { if $0 == .destinations { didLoadDestinations = true } }
        .padding(12)
        .background(FilmCanTheme.settingsCard)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
        )
        .frame(minWidth: isWide ? 600 : nil, maxWidth: .infinity, alignment: .leading)
    }

    private var optionsTabBar: some View {
        let isWide = effectiveOptionsWidth >= 600
        return Group {
            if isWide {
                HStack(spacing: 8) {
                    ForEach(availableOptionsTabs) { tab in
                        let isSelected = selectedOptionsTab == tab
                        Button {
                            if isSelected {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isOptionsCollapsed.toggle()
                                }
                            } else {
                                selectedOptionsTab = tab
                                if isOptionsCollapsed {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isOptionsCollapsed = false
                                    }
                                }
                            }
                        } label: {
                            Text(tab.shortTitle)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? FilmCanTheme.card : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? FilmCanTheme.cardStrokeStrong : FilmCanTheme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    presetSelector
                }
                .tourAnchor("optionsTabs")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(availableOptionsTabs) { tab in
                        let isSelected = selectedOptionsTab == tab
                        Button {
                            if isSelected {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isOptionsCollapsed.toggle()
                                }
                            } else {
                                selectedOptionsTab = tab
                                if isOptionsCollapsed {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        isOptionsCollapsed = false
                                    }
                                }
                            }
                        } label: {
                            Text(tab.shortTitle)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(isSelected ? FilmCanTheme.card : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(isSelected ? FilmCanTheme.cardStrokeStrong : FilmCanTheme.cardStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    presetSelector
                }
                .tourAnchor("optionsTabs")
            }
        }
    }

    private var presetSelector: some View {
        HStack(spacing: 8) {
            Text("Preset:")
                .font(.subheadline)
                .foregroundColor(FilmCanTheme.textSecondary)
            Menu {
                Button("Off") {
                    viewModel.applyOffOrganizationSettings()
                    expandOptionsIfNeeded()
                }
                Button("Netflix Ingest (built-in)") {
                    viewModel.applyNetflixIngestPreset()
                    expandOptionsIfNeeded()
                }
                ForEach(viewModel.organizationPresets) { preset in
                    Button(preset.name) {
                        viewModel.applyPreset(preset)
                        expandOptionsIfNeeded()
                    }
                }
                Divider()
                Button("Create new preset") {
                    viewModel.saveCurrentSettingsAsPreset()
                    expandOptionsIfNeeded()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedOrganizationPresetName)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(FilmCanTheme.card)
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if let presetBinding = selectedPresetBinding {
                if isEditingPresetName {
                    TextField("Preset name", text: presetBinding.name)
                        .textFieldStyle(.roundedBorder)
                        .focused($isPresetNameFocused)
                        .onSubmit { finishEditingPresetName() }
                        .onChange(of: isPresetNameFocused) { focused in
                            if !focused { finishEditingPresetName() }
                        }
                        .frame(width: 160)
                } else {
                    Button(action: { startEditingPresetName() }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }

                Button(role: .destructive) {
                    viewModel.deleteOrganizationPreset(id: presetBinding.wrappedValue.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete preset")
            }
        }
        .help("Presets auto-update when you make any change.")
    }

    private func expandOptionsIfNeeded() {
        guard isOptionsCollapsed else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            isOptionsCollapsed = false
        }
    }

    @ViewBuilder
    private var optionsTabContent: some View {
        ZStack(alignment: .topLeading) {
            // Light tabs build on demand (cheap).
            if selectedOptionsTab != .destinations {
                nonDestinationsContent
            }
            // Destinations carries the heavy organization editor. Build it once on
            // first visit and keep it mounted (height 0 when not selected) so later
            // tab switches and open/close toggles don't pay the mount/teardown cost.
            if didLoadDestinations {
                destinationsContent
                    .frame(height: selectedOptionsTab == .destinations ? nil : 0, alignment: .top)
                    .clipped()
                    .opacity(selectedOptionsTab == .destinations ? 1 : 0)
                    .allowsHitTesting(selectedOptionsTab == .destinations)
            }
        }
    }

    @ViewBuilder
    private var nonDestinationsContent: some View {
        switch selectedOptionsTab {
        case .basic:
            basicOptionsContent
        case .source:
            sourceOptionsContent
        case .logs:
            logsContent
        case .destinations:
            EmptyView()
        }
    }

    private var availableOptionsTabs: [OptionsTab] {
        OptionsTab.allCases
    }

    private var optionsHorizontalPadding: CGFloat {
        let width = effectiveOptionsWidth
        if width <= 0 { return 24 }
        let padding = width * 0.05
        return min(50, max(10, padding))
    }

    private var effectiveOptionsWidth: CGFloat {
        let historyWidth = isHistoryVisible ? historyPanelWidth : 0
        return max(0, optionsAvailableWidth - historyWidth)
    }

    private func resolvedTextWidth(_ base: CGFloat) -> CGFloat {
        let available = effectiveOptionsWidth
        guard available > 0 else { return base }
        let minWidth: CGFloat = 180
        let reserved = optionIconWidth + optionToggleWidth + optionSpacing * 2 + 24
        let maxForText = max(minWidth, available - reserved)
        return min(base, maxForText)
    }

    private func resolvedMenuWidth(_ base: CGFloat, textWidth: CGFloat) -> CGFloat {
        let available = effectiveOptionsWidth
        guard available > 0 else { return base }
        let minWidth: CGFloat = 120
        let reserved = optionIconWidth + optionSpacing * 2 + textWidth + 16
        let maxForMenu = max(minWidth, available - reserved)
        return min(base, maxForMenu)
    }

    private var hashListStyleLocked: Bool {
        selectedOrganizationPresetName == OrganizationPreset.netflixIngestName
    }

    @ViewBuilder
    private var hashListStyleRow: some View {
        let info = InfoPopoverContent(
            title: "Hash list style",
            description: "Which checksum manifest FilmCan writes next to each backed-up roll.",
            options: [
                .init("ASC MHL (Netflix-ready)",
                      good: ["Visible ascmhl/ folder + chain of custody",
                             "Validated by the reference ascmhl tool; accepted for delivery"],
                      bad: ["More files on the destination (manifest + chain per generation)"]),
                .init("Simple (hidden)",
                      good: ["One lightweight hidden .filmcan hash list per roll",
                             "Cleaner destination for users who don't deliver an MHL"],
                      bad: ["No chain of custody / generations",
                            "Not a Netflix-conformant deliverable"])
            ],
            notes: ["Resume-skip and verification work the same either way.",
                    "The Netflix Ingest preset always uses ASC MHL (this picker is locked)."]
        )
        HStack(spacing: optionSpacing) {
            Image(systemName: "list.bullet.rectangle")
                .font(.title3)
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Hash list style")
                        .font(FilmCanFont.label(13))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    InfoPopoverButton(content: info)
                }
            }
            .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
            Menu {
                ForEach(HashListStyle.allCases) { style in
                    Button(action: { viewModel.hashListStyle = style }) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.displayName)
                            Text(style.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(hashListStyleLocked ? HashListStyle.ascMHL.shortName : viewModel.hashListStyle.shortName)
                    Image(systemName: "chevron.down").font(.caption)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(FilmCanTheme.card)
                .cornerRadius(6)
                .frame(width: resolvedMenuWidth(optionMenuWidth + 60, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(hashListStyleLocked)
            .opacity(hashListStyleLocked ? 0.5 : 1)
        }
    }

    private var basicOptionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Copy-engine picker removed: rsync retired, FilmCan is the only engine.
            // "Automatic parallel copy" toggle removed: destination parallelism is
            // now controlled by the Copy mode picker below.

            let verificationInfo = InfoPopoverContent(
                title: "Verification",
                description: "How thoroughly FilmCan confirms each file landed correctly.",
                options: [
                    .init("Paranoid",
                          good: ["Re-reads every file from disk and compares",
                                 "Catches write errors and in-memory corruption"],
                          bad: ["Roughly doubles disk I/O (the re-read pass)"]),
                    .init("Fast",
                          good: ["Verifies against the hash computed during the copy",
                                 "No re-read — about twice as fast as Paranoid"],
                          bad: ["Doesn't catch a bad write that the OS reported as OK",
                                "Trusts the data already in memory wasn't corrupted"]),
                    .init("Off",
                          good: ["Fastest — no hashing or checking"],
                          bad: ["A write error or corruption goes undetected",
                                "No hash list — the transfer log can't list individual files (status + counts only)"])
                ],
                notes: ["Paranoid is recommended for safety-critical backups.",
                        "The transfer log's per-file list is derived from the hash list, so it needs Fast or Paranoid."]
            )

            HStack(spacing: optionSpacing) {
                Image(systemName: "checkmark.seal")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Verification")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: verificationInfo)
                    }
                }
                .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                Menu {
                    ForEach(VerifyMode.allCases) { mode in
                        Button(action: { viewModel.verificationMode = mode }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.verificationMode.displayName)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: resolvedMenuWidth(optionMenuWidth + 60, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            hashListStyleRow

            optionRow(
                icon: "checkmark.shield",
                iconColor: FilmCanTheme.textSecondary,
                title: "Re-verify on resume",
                subtitle: "",
                isOn: $viewModel.reVerifyExistingOnResume,
                textWidth: basicOptionTextWidth,
                info: InfoPopoverContent(
                    title: "Re-verify existing files on resume",
                    description: "When resuming a backup, re-read and hash each already-copied source file to confirm it hasn't changed since the last run.",
                    options: [
                        .init("Off (trust size)",
                              good: ["Fast resume — skips based on file size match"],
                              bad: ["Won't catch same-size content changes"]),
                        .init("On (re-hash source)",
                              good: ["Detects same-size file replacements cryptographically"],
                              bad: ["Slower — re-reads every already-backed-up file"])
                    ],
                    notes: ["Use when card contents may have been silently corrupted or replaced with same-size data."]
                )
            )

            optionRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: FilmCanTheme.textSecondary,
                title: "Force re-copy",
                subtitle: "",
                isOn: $viewModel.forceRecopy,
                textWidth: basicOptionTextWidth,
                info: InfoPopoverContent(
                    title: "Force re-copy",
                    description: "Whether a re-run copies files that are already backed up.",
                    options: [
                        .init("Off (resume skip)",
                              good: ["Skips files already in every destination's hash list and still present",
                                     "Fast re-runs — only new/changed files are copied"],
                              bad: ["A file deleted from a destination is re-copied (presence is checked)"]),
                        .init("On (force re-copy)",
                              good: ["Re-copies every file — guarantees a fresh copy"],
                              bad: ["Slower — ignores the hash list entirely"])
                    ],
                    notes: ["With a {date} folder template, resuming on a different day re-copies into that day's folder (earlier files aren't matched)."]
                )
            )

            HStack(spacing: optionSpacing) {
                Image(systemName: "doc.on.doc")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Duplicate policy")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(
                            content: InfoPopoverContent(
                                title: "Duplicate policy",
                                description: "What FilmCan does with a file or folder that already exists at the destination.",
                                options: [
                                    .init("Skip",
                                          good: ["Keeps existing destination files untouched"],
                                          bad: ["An out-of-date file at the destination stays out of date"]),
                                    .init("Overwrite",
                                          good: ["Destination ends up matching the source"],
                                          bad: ["Can destroy a destination-only version of the file"]),
                                    .init("Increment",
                                          good: ["Preserves both versions (adds a counter suffix)"],
                                          bad: ["Can create many duplicates over time"]),
                                    .init("Ask",
                                          good: ["You decide per conflict"],
                                          bad: ["Interrupts unattended runs"])
                                ]
                            )
                        )
                    }
                }
                .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                Menu {
                    ForEach(OrganizationPreset.DuplicatePolicy.allCases) { policy in
                        Button(policy.displayName) { viewModel.duplicatePolicy = policy }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.duplicatePolicy.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: resolvedMenuWidth(optionMenuWidth + 100, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if viewModel.duplicatePolicy == .increment {
                HStack(spacing: optionSpacing) {
                    Color.clear
                        .frame(width: 32, height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Counter style")
                                .font(FilmCanFont.label(13))
                                .foregroundColor(FilmCanTheme.textPrimary)
                            InfoPopoverButton(
                                content: InfoPopoverContent(
                                    title: "Counter style",
                                    description: "Defines the suffix format when using Increment. Example: `_001` produces file_001, file_002, etc.",
                                    pros: [
                                        "Keeps duplicates organized and predictable",
                                        "Supports zero-padded counters"
                                    ],
                                    cons: [
                                        "Only used when Increment is selected",
                                        "Inconsistent styles can clutter naming"
                                    ]
                                )
                            )
                        }
                    }
                    .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                    TextField("_001", text: $viewModel.duplicateCounterTemplate)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: resolvedMenuWidth(optionMenuWidth, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
            }

            let copyModeInfo = InfoPopoverContent(
                title: "Copy mode",
                description: "How FilmCan writes to multiple destinations.",
                options: [
                    .init("Automatic",
                          good: ["Parallel for SSDs, sequential for hard drives / shared buses",
                                 "Sensible default — no need to think about it"]),
                    .init("All destinations at once (parallel)",
                          good: ["Reads the source once, writes everywhere together",
                                 "Fastest with multiple SSDs"],
                          bad: ["More bandwidth and disk activity",
                                "Can thrash if destinations share one drive/bus"]),
                    .init("One destination at a time (sequential)",
                          good: ["Gentler on shared buses and hard drives"],
                          bad: ["Re-reads the source for each destination",
                                "Slower total time with multiple destinations"])
                ],
                notes: ["With one destination this setting has no effect."]
            )

            HStack(spacing: optionSpacing) {
                Image(systemName: "square.stack.3d.down.right")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Copy mode")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: copyModeInfo)
                    }
                }
                .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                Menu {
                    ForEach(DestinationCopyMode.allCases) { mode in
                        Button(action: { viewModel.destinationCopyMode = mode }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.displayName)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.destinationCopyMode.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: resolvedMenuWidth(optionMenuWidth + 100, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            let fileOrderInfo = InfoPopoverContent(
                title: "Copy order",
                description: "The order FilmCan copies files in.",
                options: [
                    .init("Default", good: ["Preserves the filesystem order"]),
                    .init("Smallest first",
                          good: ["Can speed up cards with lots of tiny files"],
                          bad: ["May not help on all drives"]),
                    .init("Largest first",
                          good: ["Can stabilize throughput on big files"]),
                    .init("Creation date",
                          good: ["Keeps footage order consistent"])
                ]
            )

            HStack(spacing: optionSpacing) {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Copy order")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        InfoPopoverButton(content: fileOrderInfo)
                    }
                }
                .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                Menu {
                    ForEach(FileOrdering.allCases) { ordering in
                        Button(ordering.displayName) { viewModel.rsyncOptions.fileOrdering = ordering }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.rsyncOptions.fileOrdering.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: resolvedMenuWidth(optionMenuWidth + 100, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sourceOptionsContent: some View {
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

            optionRow(
                icon: "externaldrive",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect camera sources",
                subtitle: "",
                isOn: $viewModel.sourceAutoDetectEnabled,
                textWidth: basicOptionTextWidth,
                info: sourceAutoDetectInfo
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
                .padding(.leading, optionIconWidth + optionSpacing)
                .padding(.top, 4)
            }

            optionRow(
                icon: "waveform",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect sound sources",
                subtitle: "",
                isOn: $viewModel.soundAutoDetectEnabled,
                textWidth: basicOptionTextWidth,
                info: InfoPopoverContent(
                    title: "Auto-detect sound sources",
                    description: "Tags a source as Sound (routed to Sound_Media under the Netflix preset) when its drive or folder name matches one of these patterns.",
                    pros: ["No need to flip each sound card to Sound by hand"],
                    cons: ["A broad pattern could mis-tag a camera card as sound"]
                )
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
                .padding(.leading, optionIconWidth + optionSpacing)
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

            optionRow(
                icon: "folder.badge.minus",
                iconColor: FilmCanTheme.textSecondary,
                title: "Copy folder contents only",
                subtitle: "",
                isOn: $viewModel.copyFolderContents,
                textWidth: basicOptionTextWidth,
                info: copyContentsInfo
            )

            if let presetBinding = editingOrganizationPresetBinding {
                fileFilterPatternsSection(presetBinding: presetBinding)
                    .padding(.leading, optionIconWidth + optionSpacing)
                    .padding(.top, 8)
            }
        }
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

    private func netflixMetaField(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: optionSpacing) {
            Text(label)
                .font(FilmCanFont.body(12))
                .foregroundColor(FilmCanTheme.textSecondary)
                .frame(width: 130, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
        }
    }

    @ViewBuilder
    private var netflixMetadataSection: some View {
        if selectedOrganizationPresetName == OrganizationPreset.netflixIngestName {
            VStack(alignment: .leading, spacing: 8) {
                Text("Shoot metadata")
                    .font(FilmCanFont.label(13))
                    .foregroundColor(FilmCanTheme.textPrimary)
                netflixMetaField("Episode / Block", placeholder: "EP103 / B01",
                                 text: Binding(get: { viewModel.episode }, set: { viewModel.episode = $0 }))
                netflixMetaField("Day", placeholder: "Day05 / D05",
                                 text: Binding(get: { viewModel.day }, set: { viewModel.day = $0 }))
                netflixMetaField("Unit", placeholder: "MU / 2U",
                                 text: Binding(get: { viewModel.unit }, set: { viewModel.unit = $0 }))
                netflixMetaField("Camera format", placeholder: "ARRI / RED (optional)",
                                 text: Binding(get: { viewModel.cameraFormat }, set: { viewModel.cameraFormat = $0 }))

                folderTemplatesSection
                netflixReadinessHint
            }
            .padding(.bottom, 8)
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
                             text: Binding(get: { viewModel.cameraFolderTemplate },
                                           set: { viewModel.cameraFolderTemplate = $0 }))
            netflixMetaField("Sound folder", placeholder: "{date}_{episode}_{day}_{unit}/Sound_Media",
                             text: Binding(get: { viewModel.soundFolderTemplate },
                                           set: { viewModel.soundFolderTemplate = $0 }))
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

    private var destinationsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            netflixMetadataSection
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

            optionRow(
                icon: "externaldrive",
                iconColor: FilmCanTheme.textSecondary,
                title: "Auto-detect destinations",
                subtitle: "",
                isOn: $viewModel.destinationAutoDetectEnabled,
                textWidth: basicOptionTextWidth,
                info: destinationAutoDetectInfo
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
                .padding(.leading, optionIconWidth + optionSpacing)
                .padding(.top, 4)
            }

            organizationOptionsContent
        }
    }

    private var organizationOptionsContent: some View {
        Group {
            if let presetBinding = editingOrganizationPresetBinding {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: optionSpacing) {
                        Image(systemName: "folder")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: optionIconWidth)
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
                        .frame(width: resolvedTextWidth(optionTextWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useFolderTemplate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: optionToggleWidth, alignment: .leading)
                    }

                    if presetBinding.useFolderTemplate.wrappedValue {
                        TextField("RUSHES/DAY_{counter}_{date}/CARD_{source}", text: presetBinding.folderTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onDrop(of: [.text], isTargeted: $isFolderDropTargeted) { providers in
                                handleTokenDrop(providers: providers, into: presetBinding.folderTemplate)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isFolderDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                            .padding(.leading, optionIconWidth + optionSpacing)
                        TokenFlowLayout(spacing: 10) {
                            ForEach(tokenList, id: \.token) { entry in
                                TokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, optionIconWidth + optionSpacing)

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
                        .padding(.leading, optionIconWidth + optionSpacing)
                    }

                    HStack(spacing: optionSpacing) {
                        Image(systemName: "doc.text")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: optionIconWidth)
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
                        .frame(width: resolvedTextWidth(optionTextWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useRenameTemplate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: optionToggleWidth, alignment: .leading)
                    }

                    if presetBinding.useRenameTemplate.wrappedValue {
                        TextField("{filename}{ext}", text: presetBinding.renameTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .onDrop(of: [.text], isTargeted: $isRenameDropTargeted) { providers in
                                handleTokenDrop(providers: providers, into: presetBinding.renameTemplate)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isRenameDropTargeted ? Color.accentColor : Color.clear, lineWidth: 1)
                            )
                            .padding(.leading, optionIconWidth + optionSpacing)
                        TokenFlowLayout(spacing: 10) {
                            ForEach(tokenList, id: \.token) { entry in
                                TokenChip(text: entry.token)
                                    .help(entry.description)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, optionIconWidth + optionSpacing)
                    }

                    HStack(spacing: optionSpacing) {
                        Image(systemName: "calendar")
                            .font(.title3)
                            .foregroundColor(FilmCanTheme.textSecondary)
                            .frame(width: optionIconWidth)
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
                        .frame(width: resolvedTextWidth(optionTextWidth), alignment: .leading)
                        Toggle("", isOn: presetBinding.useCustomDate)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .scaleEffect(0.8)
                            .tint(FilmCanTheme.toggleTint)
                            .frame(width: optionToggleWidth, alignment: .leading)
                    }

            if presetBinding.useCustomDate.wrappedValue {
                DatePicker(
                    "Date",
                    selection: presetBinding.customDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.field)
                .padding(.leading, optionIconWidth + optionSpacing)
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

    private var logsContent: some View {
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
    }

    var nameRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if isEditingName {
                    TextField("Backup name", text: $viewModel.name)
                        .textFieldStyle(.plain)
                        .focused($isNameFocused)
                        .font(FilmCanFont.title(24))
                        .foregroundColor(FilmCanTheme.textPrimary)
                        .multilineTextAlignment(.leading)
                        .onSubmit { confirmEditingName(shouldAdvanceTour: true) }
                        .onChange(of: isNameFocused) { focused in
                            if !focused { confirmEditingName() }
                        }
                } else {
                    Text(viewModel.name.isEmpty ? "Untitled Backup" : viewModel.name)
                        .font(FilmCanFont.title(24))
                        .foregroundColor(viewModel.name.isEmpty ? FilmCanTheme.textTertiary : FilmCanTheme.textPrimary)
                        .textSelection(.disabled)
                        .highPriorityGesture(
                            TapGesture(count: 2).onEnded { startEditingName() }
                        )
                }
            }
            .tourAnchor("backupName")
            
            Spacer()

            if let customDateStatusText {
                Text(customDateStatusText)
                    .font(FilmCanFont.body(11))
                    .foregroundColor(.accentColor)
            }

            Button(action: {
                refreshAllDriveData(force: true)
            }) {
                HStack(spacing: 6) {
                    Text("Refresh drives")
                        .font(FilmCanFont.label(12))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(FilmCanTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(FilmCanTheme.card)
            .cornerRadius(8)
            .help("Refresh drives")

            Button(action: { startTransfer() }) {
                Text("Run Now")
                    .font(FilmCanFont.label(13))
                    .foregroundColor(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(FilmCanTheme.brandYellow)
            .cornerRadius(8)
            .disabled(transferViewModel.isTransferActive(for: viewModel.config.id))
        }
        .frame(maxWidth: .infinity)
    }
    
    func startEditingName() {
        isEditingName = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isNameFocused = true
        }
    }

    func confirmEditingName(shouldAdvanceTour: Bool = false) {
        finishEditingName()
        NotificationCenter.default.post(name: .filmCanTourNameConfirmed, object: nil)
        if shouldAdvanceTour {
            let trimmedName = viewModel.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                NotificationCenter.default.post(name: .filmCanTourNameSubmitted, object: nil)
            }
        }
    }
    
    func finishEditingName() {
        isEditingName = false
        isNameFocused = false
    }

    
    var sourcePreviewHeader: AnyView? {
        nil
    }
    
    var sourcePreviewFooter: AnyView? {
        guard !viewModel.sourcePaths.isEmpty else { return nil }
        let fileCount = previewInfo.fileCount
        let folderCount = displayFolderCount
        let sizeLabel = previewInfo.isLoading
            ? "--"
            : (previewInfo.totalBytes > 0 ? FilmCanFormatters.bytes(previewInfo.totalBytes, style: .decimal) : "--")
        let fileLabel = previewInfo.isLoading
            ? "-- files"
            : "\(fileCount) file" + (fileCount == 1 ? "" : "s")
        let folderLabel = previewInfo.isLoading
            ? "-- folders"
            : "\(folderCount) folder" + (folderCount == 1 ? "" : "s")
        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                VStack(spacing: 2) {
                    Text(sizeLabel)
                        .font(FilmCanFont.title(20))
                        .foregroundColor(FilmCanTheme.textPrimary)
                    Text("\(fileLabel) • \(folderLabel)")
                        .font(FilmCanFont.body(12))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .foregroundColor(FilmCanTheme.textPrimary)
        )
    }

    private var displayFolderCount: Int {
        guard !viewModel.copyFolderContents else { return previewInfo.folderCount }
        let fm = FileManager.default
        let selectedFolderCount = viewModel.sourcePaths.reduce(0) { count, path in
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return count + 1
            }
            return count
        }
        return previewInfo.folderCount + selectedFolderCount
    }
}
