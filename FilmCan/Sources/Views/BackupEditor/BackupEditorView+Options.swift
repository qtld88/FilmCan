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

    private func hasCustomFilterPatterns(_ preset: OrganizationPreset) -> Bool {
        SourceFilterMatching.hasCustomFilterPatterns(
            include: preset.includePatterns,
            exclude: preset.excludePatterns,
            copyOnly: preset.copyOnlyPatterns
        )
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
                DestinationsOptionsView(model: organizationModel, viewModel: viewModel, availableWidth: effectiveOptionsWidth, destinationCount: viewModel.destinations.count)
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
            BasicOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
        case .source:
            SourceOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
        case .logs:
            LogsOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
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
