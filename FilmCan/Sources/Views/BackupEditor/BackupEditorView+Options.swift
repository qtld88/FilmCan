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

    private func copyEnginePicker() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: optionSpacing) {
                Image(systemName: "gearshape.2")
                    .font(.title3)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Copy engine")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        Button(action: { showEngineHelp = true }) {
                            Image(systemName: "info.circle")
                                .foregroundColor(FilmCanTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help("Learn about copy engines")
                    }
                }
                .frame(width: resolvedTextWidth(basicOptionTextWidth), alignment: .leading)
                Menu {
                    ForEach(CopyEngine.allCases) { engine in
                        Button(action: { viewModel.setCopyEngine(engine) }) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(engine.displayName)
                                Text(engine.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.rsyncOptions.copyEngine.displayName)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(FilmCanTheme.card)
                    .cornerRadius(6)
                    .frame(width: resolvedMenuWidth(optionMenuWidth + 60, textWidth: resolvedTextWidth(basicOptionTextWidth)), alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
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
        return VStack(alignment: .leading, spacing: 16) {
            optionsTabBar
            if !isOptionsCollapsed {
                Divider()
                    .background(FilmCanTheme.cardStroke)
                optionsTabContent
            }
        }
        .padding(12)
        .background(FilmCanTheme.panel)
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
        switch selectedOptionsTab {
        case .basic:
            basicOptionsContent
        case .source:
            sourceOptionsContent
        case .refinements:
            transferRefinementsContent
        case .destinations:
            destinationsContent
        case .logs:
            logsContent
        }
    }

    private var availableOptionsTabs: [OptionsTab] {
        isCustomEngine ? OptionsTab.allCases.filter { $0 != .refinements } : OptionsTab.allCases
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

    private var basicOptionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            copyEnginePicker()

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

            let parallelCopyInfo = InfoPopoverContent(
                title: "Automatic parallel copy",
                description: "Let FilmCan decide when to copy multiple files in parallel.",
                pros: [
                    "Faster on SSDs with many small files",
                    "Better use of SSD bandwidth"
                ],
                cons: [
                    "Disabled for large files to avoid slowdowns",
                    "More disk activity during copy when enabled"
                ],
                notes: ["FilmCan only enables parallel copy when both source and destination are SSDs and files are small enough."]
            )

            optionRow(
                icon: "square.2.layers.3d.top.filled",
                iconColor: FilmCanTheme.textSecondary,
                title: "Automatic parallel copy",
                subtitle: "",
                isOn: $viewModel.rsyncOptions.parallelCopyEnabled,
                textWidth: basicOptionTextWidth,
                info: parallelCopyInfo
            )
            .disabled(!isCustomEngine)
            .opacity(isCustomEngine ? 1 : 0.5)
            
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
                                description: "Controls how FilmCan handles a file or folder that already exists at the destination.",
                                pros: [
                                    "Skip keeps existing files untouched",
                                    "Overwrite ensures destination matches source",
                                    "Increment preserves both versions"
                                ],
                                cons: [
                                    "Overwrite can destroy destination-only data",
                                    "Increment can create lots of duplicates",
                                    "Ask each time interrupts unattended runs"
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
                description: "Choose whether destinations run one at a time or in parallel.",
                pros: [
                    "Parallel can reduce total time with multiple destinations",
                    "Sequential is gentler on drives and CPU"
                ],
                cons: [
                    "Parallel uses more bandwidth and CPU",
                    "Sequential can be slower overall"
                ]
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
                    Button("One destination at a time") { viewModel.runInParallel = false }
                    Button("All destinations at once") { viewModel.runInParallel = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(viewModel.runInParallel ? "All destinations at once" : "One destination at a time")
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
                description: "Choose the order FilmCan uses to copy files when using the FilmCan Engine.",
                pros: [
                    "Default order preserves the filesystem order",
                    "Small first can speed up cards with lots of tiny files",
                    "Large first can stabilize throughput on big files",
                    "Creation date can help keep footage order consistent"
                ],
                cons: [
                    "Only affects FilmCan Engine",
                    "May not improve speed on all drives"
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
                .disabled(!isCustomEngine)
                .opacity(isCustomEngine ? 1 : 0.5)
            }
        }
    }

    private var sourceOptionsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            let sourceAutoDetectInfo = InfoPopoverContent(
                title: "Auto-detect sources",
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
                title: "Auto-detect sources",
                subtitle: "",
                isOn: $viewModel.sourceAutoDetectEnabled,
                textWidth: basicOptionTextWidth,
                info: sourceAutoDetectInfo
            )

            if viewModel.sourceAutoDetectEnabled {
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

    private var transferRefinementsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            optionRow(
                icon: "checkmark.shield.fill",
                iconColor: FilmCanTheme.textSecondary,
                title: "Verify after copy",
                subtitle: isCustomEngine
                    ? "Built into FilmCan Engine (always enabled)"
                    : "Ensures files copied correctly (recommended)",
                isOn: $viewModel.rsyncOptions.postVerify,
                textWidth: basicOptionTextWidth,
                helpText: isCustomEngine
                    ? "FilmCan Engine always verifies during the copy."
                    : "Runs a checksum-based verification after copying."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)

            optionRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: FilmCanTheme.textSecondary,
                title: "Only copy new or changed files",
                subtitle: isCustomEngine
                    ? "Not available with FilmCan Engine"
                    : "Incremental sync saves time and space",
                isOn: $viewModel.rsyncOptions.onlyCopyChanged,
                textWidth: basicOptionTextWidth,
                helpText: isCustomEngine
                    ? "FilmCan Engine always copies all files."
                    : "Compares file changes (size/date or checksum) and skips identical files."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: optionSpacing) {
                    Color.clear
                        .frame(width: optionIconWidth, height: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Checksum algorithm")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                    Text("Used for transfer integrity checks and pre/post-copy comparisons.")
                        .font(FilmCanFont.body(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
                .frame(width: resolvedTextWidth(optionTextWidth), alignment: .leading)
                HStack(spacing: 6) {
                    Text(FilmCanHashAlgorithm.xxh128.displayName)
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(FilmCanTheme.textSecondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(FilmCanTheme.card)
                .cornerRadius(6)
                .frame(width: resolvedMenuWidth(optionMenuWidth + 40, textWidth: resolvedTextWidth(optionTextWidth)), alignment: .leading)
            }
            .help("Checksum algorithm is fixed to xxHash128.")
            }
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            advancedOptionRow(
                icon: nil,
                title: "Use checksum to verify file contents before copy",
                subtitle: isCustomEngine
                    ? "Not available with FilmCan Engine"
                    : "Uses checksums instead of size/date to decide what needs copying. This is pre-copy, not the post-copy verification.",
                isOn: $viewModel.rsyncOptions.useChecksum,
                helpText: isCustomEngine
                    ? "FilmCan Engine always copies all files and verifies while copying."
                    : "Forces checksum comparison before copying; slower but more accurate."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            advancedOptionRow(
                icon: nil,
                title: "Update files in place",
                subtitle: isCustomEngine
                    ? "Not available with FilmCan Engine"
                    : "Writes updates directly into existing destination files instead of creating a new temp file and swapping it in at the end.",
                isOn: $viewModel.rsyncOptions.inplace,
                helpText: isCustomEngine
                    ? "FilmCan Engine always writes new destination files."
                    : "Can be faster for large files but is riskier if interrupted."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            advancedOptionRow(
                icon: nil,
                title: "Allow resume after stop",
                subtitle: isCustomEngine
                    ? "Not available with FilmCan Engine"
                    : "Keeps partial files in .filmcan/partial so you can stop and continue later.",
                isOn: $viewModel.rsyncOptions.allowResume,
                helpText: isCustomEngine
                    ? "FilmCan Engine does not support resuming."
                    : "Resume keeps partial files on disk so you can continue after stopping. This can use extra space, leave partials until completion, and can be confusing if sources change between runs. Turn it off for a clean destination on stop."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Custom rsync arguments")
                    .font(.body.weight(.medium))
                Text("For power users only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("e.g., --exclude '*.tmp' --exclude '.DS_Store'", text: $viewModel.rsyncOptions.customArgs)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 260, maxWidth: 360, alignment: .leading)
                    .disabled(isCustomEngine)
            }
            .help(isCustomEngine ? "Not available with FilmCan Engine." : "Advanced: pass extra rsync flags directly.")
            .opacity(isCustomEngine ? 0.5 : 1.0)

            Divider()

            advancedOptionRow(
                icon: nil,
                title: "Delete files not in source",
                subtitle: isCustomEngine
                    ? "Not available with FilmCan Engine"
                    : "Dangerous: makes destination a mirror of the source.",
                titleColor: .red,
                subtitleColor: .red,
                isOn: $viewModel.rsyncOptions.delete,
                helpText: isCustomEngine
                    ? "FilmCan Engine never deletes extra destination files."
                    : "Deletes destination files that are not present in the source."
            )
            .disabled(isCustomEngine)
            .opacity(isCustomEngine ? 0.5 : 1.0)
        }
    }

    private var destinationsContent: some View {
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
            .disabled(transferViewModel.isTransferring)
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
