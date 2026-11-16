import SwiftUI
import Foundation

extension BackupEditorView {
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
        ShootMetadata(episode: viewModel.episode, day: viewModel.effectiveShootDay(),
                      unit: viewModel.unit, cameraFormat: viewModel.cameraFormat,
                      movie: viewModel.config.name)
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

    private func hasCustomFilterPatterns(_ preset: OrganizationPreset) -> Bool {
        SourceFilterMatching.hasCustomFilterPatterns(
            include: preset.includePatterns,
            exclude: preset.excludePatterns,
            copyOnly: preset.copyOnlyPatterns
        )
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
                        .font(FCType.itemTitle)
                        .foregroundColor(FilmCanTheme.textPrimary)
                    if let info {
                        InfoPopoverButton(content: info)
                    }
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(FCType.meta)
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
                    .font(icon == nil ? FCType.cardTitle : FCType.itemTitle)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture { isExpanded.wrappedValue.toggle() }
        }
        .fcCardSurface(role: .data)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    /// The movie settings, stacked: the preset menu, then one folding group per area
    /// (Basic, Source, Destinations, Logs), each opened or closed on its title.
    func optionsSection() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            presetSelector
                .padding(.horizontal, MovieSettingsSections.contentInset)
                .padding(.bottom, 12)
            Divider().background(FilmCanTheme.cardStroke)
            ForEach(OptionsTab.allCases) { tab in
                settingsGroup(tab)
                Divider().background(FilmCanTheme.cardStroke)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { optionsAvailableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { optionsAvailableWidth = $0 }
            }
        )
        .onAppear { if isGroupOpen(.destinations) { scheduleDestinationsLoad() } }
    }

    func isGroupOpen(_ tab: OptionsTab) -> Bool {
        MovieSettingsSections.isOpen(tab.sectionKey, stored: openSettingsGroups)
    }

    private func toggleGroup(_ tab: OptionsTab) {
        withAnimation(.easeInOut(duration: 0.15)) {
            openSettingsGroups = MovieSettingsSections.toggling(tab.sectionKey, in: openSettingsGroups)
        }
        if isGroupOpen(.destinations) { scheduleDestinationsLoad() }
    }

    @ViewBuilder
    private func settingsGroup(_ tab: OptionsTab) -> some View {
        let open = isGroupOpen(tab)
        VStack(alignment: .leading, spacing: 0) {
            Button { toggleGroup(tab) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(FilmCanTheme.textTertiary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 12)
                    Text(tab.shortTitle)
                        .font(FCType.itemTitle)
                        .foregroundColor(open ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, MovieSettingsSections.contentInset)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tab.shortTitle)
            .accessibilityValue(open ? "Open" : "Closed")
            .help(open ? "Close \(tab.shortTitle)" : "Open \(tab.shortTitle)")

            groupContent(tab)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, MovieSettingsSections.contentInset)
                .padding(.bottom, open ? 14 : 0)
                .frame(height: open ? nil : 0, alignment: .top)
                .clipped()
                .opacity(open ? 1 : 0)
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
    }

    @ViewBuilder
    private func groupContent(_ tab: OptionsTab) -> some View {
        switch tab {
        case .basic:
            if isGroupOpen(.basic) {
                BasicOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
            }
        case .source:
            if isGroupOpen(.source) {
                SourceOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
            }
        case .logs:
            if isGroupOpen(.logs) {
                LogsOptionsView(viewModel: viewModel, availableWidth: effectiveOptionsWidth)
            }
        case .destinations:
            // Destinations carries the heavy organization editor: built one runloop after
            // it is first opened (spinner meanwhile), then kept mounted so folding it
            // closed and open again costs nothing.
            if didLoadDestinations {
                DestinationsOptionsView(model: organizationModel, viewModel: viewModel, availableWidth: effectiveOptionsWidth, destinationCount: viewModel.destinations.count)
            } else if isGroupOpen(.destinations) {
                destinationsLoadingPlaceholder
            }
        }
    }

    /// Folder organization on/off, the Netflix Ingest model and the settings export.
    private var presetSelector: some View {
        HStack(spacing: 12) {
            Toggle("Organize folders", isOn: Binding(
                get: { viewModel.folderOrganizationIsOn },
                set: { on in
                    viewModel.setFolderOrganization(on)
                    if on { expandOptionsIfNeeded() }
                }))
                .toggleStyle(.switch)
                .help("On: this movie creates folders and names files from its own settings. Off: it copies as is; its settings are kept aside.")
            Button("Use Netflix Ingest folders") { confirmNetflixIngest = true }
                .help("Replaces this movie's folder and naming settings with the Netflix Ingest ones.")
            Button("Export Settings\u{2026}") { exportMovieSettings() }
                .help("Saves this movie's settings to a file another movie can start from.")
            Spacer(minLength: 0)
        }
        .alert("Use Netflix Ingest folders?", isPresented: $confirmNetflixIngest) {
            Button("Replace", role: .destructive) {
                viewModel.applyNetflixIngestPreset()
                expandOptionsIfNeeded()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replaces this movie's folder and naming settings.")
        }
        .fileExporter(
            isPresented: $showSettingsExport,
            document: settingsExportDocument,
            contentType: MovieSettingsFile.contentType,
            defaultFilename: viewModel.config.name
        ) { result in
            if case .failure(let error) = result {
                viewModel.validationMessage = "Failed to export settings: \(error.localizedDescription)"
                viewModel.showValidationError = true
            }
        }
    }

    private func exportMovieSettings() {
        do {
            settingsExportDocument = JSONExportDocument(
                data: try AppState.shared.settingsFileData(for: viewModel.config))
            showSettingsExport = true
        } catch {
            viewModel.validationMessage = "Failed to export settings: \(error.localizedDescription)"
            viewModel.showValidationError = true
        }
    }

    private func expandOptionsIfNeeded() {
        if !isMovieSettingsShown { openMovieSettings() }
    }

    private var destinationsLoadingPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(height: 120, alignment: .center)
    }

    /// Defer mounting the heavy Destinations editor to the next runloop so the tab
    /// selection (highlight + expand + spinner) paints first — the click feels
    /// instant even though the form's layout cost is unchanged.
    private func scheduleDestinationsLoad() {
        guard !didLoadDestinations else { return }
        DispatchQueue.main.async { didLoadDestinations = true }
    }

    /// Width the rows of a group may use: inside the group's inset, never the panel's
    /// outer width (sizing rows from the outer width pushed them past the edge).
    private var effectiveOptionsWidth: CGFloat {
        MovieSettingsSections.contentWidth(panelWidth: optionsAvailableWidth)
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

    func nameRow(runSubtitle: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                if isEditingName {
                    // A bare TextField takes all the free width and pushes the day
                    // stepper to the far right. Size it to its text instead, using a
                    // hidden copy of the name, so the stepper stays next to the title.
                    Text(viewModel.name.isEmpty ? "Backup name" : viewModel.name)
                        .font(FilmCanFont.title(24))
                        .lineLimit(1)
                        .padding(.trailing, 12)
                        .hidden()
                        .overlay(alignment: .leading) {
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

            if ShootDayStepper.usesShootDay(previewOrganizationPreset) {
                ShootDayStepperView(day: viewModel.effectiveShootDay()) { newDay in
                    viewModel.setShootDayFromHeader(newDay)
                }
                .disabled(transferViewModel.isTransferActive(for: viewModel.config.id))
            }

            Spacer()

            if let customDateStatusText {
                Text(customDateStatusText)
                    .font(FCType.meta)
                    .foregroundColor(.accentColor)
            }

            Button(action: {
                refreshAllDriveData(force: true)
            }) {
                HStack(spacing: 6) {
                    Text("Refresh drives")
                        .font(FCType.bodyStrong)
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
                VStack(spacing: 1) {
                    Text("Run Now")
                    Text(runSubtitle)
                        .font(FilmCanFont.body(10))
                        .opacity(0.75)
                        .lineLimit(1)
                }
            }
            .buttonStyle(FCPrimaryButtonStyle())
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
                        .font(FCType.body)
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
