import SwiftUI

struct OrganizationSettingsView: View {
    @Binding var presets: [OrganizationPreset]
    @Binding var selectedPresetId: UUID?
    let onAddPreset: () -> Void
    let onDeletePreset: (UUID) -> Void
    let showHeader: Bool
    let allowsLocalPreset: Bool
    var localPreset: Binding<OrganizationPreset>
    @State private var isFolderDropTargeted = false
    @State private var isRenameDropTargeted = false
    @State private var isEditingPresetName = false
    @FocusState private var isPresetNameFocused: Bool
    @State private var showCopyOnlyPatterns = false
    @State private var showIncludePatterns = false
    @State private var showExcludePatterns = false
    private let rowIconWidth: CGFloat = 32
    private let rowSpacing: CGFloat = 20
    private let rowTextWidth: CGFloat = 320
    private let rowToggleWidth: CGFloat = 60
    private let rowLeadingAdjustment: CGFloat = -8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showHeader {
                HStack(spacing: 12) {
                    Picker("Preset", selection: $selectedPresetId) {
                        Text("None").tag(UUID?.none)
                        ForEach(presets) { preset in
                            Text(preset.name).tag(Optional(preset.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()

                    Spacer()

                    Button(action: onAddPreset) {
                        Image(systemName: "plus")
                            .font(.title3)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderless)
                    .help("Add preset")
                }
            }

            if let presetBinding = editingPresetBinding {
                let isLocal = allowsLocalPreset && selectedPresetId == nil
                VStack(alignment: .leading, spacing: 8) {
                    if !isLocal {
                        HStack(spacing: 8) {
                            if isEditingPresetName {
                                TextField("Preset name", text: presetBinding.name)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($isPresetNameFocused)
                                    .onSubmit { finishEditingPresetName() }
                                    .onChange(of: isPresetNameFocused) { focused in
                                        if !focused { finishEditingPresetName() }
                                    }
                            } else {
                                Text(presetBinding.name.wrappedValue)
                                    .font(.title3.weight(.semibold))
                                    .onTapGesture { startEditingPresetName() }
                            }
                            Button(action: { startEditingPresetName() }) {
                                Image(systemName: "pencil")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)

                            Button(role: .destructive) {
                                onDeletePreset(presetBinding.wrappedValue.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete preset")
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: rowSpacing) {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                                .frame(width: rowIconWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Folder template")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                Text("Creates the folder structure inside the destination. Use \"/\" for subfolders.")
                                    .font(FilmCanFont.body(11))
                                    .foregroundColor(FilmCanTheme.textSecondary)
                            }
                            .frame(width: rowTextWidth, alignment: .leading)
                            Toggle("", isOn: presetBinding.useFolderTemplate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .scaleEffect(0.8)
                                .tint(FilmCanTheme.toggleTint)
                                .frame(width: rowToggleWidth, alignment: .leading)
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
                                .padding(.leading, rowIconWidth + rowSpacing)
                            TokenFlowLayout(spacing: 10) {
                                ForEach(tokenList, id: \.token) { entry in
                                    TokenChip(text: entry.token)
                                        .help(entry.description)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, rowIconWidth + rowSpacing)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Rename only patterns (optional)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                PatternEditor(
                                    title: "",
                                    placeholder: "*.mp4",
                                    patterns: presetBinding.renameOnlyPatterns,
                                    showsTitle: false
                                )
                            }
                            .padding(.leading, rowIconWidth + rowSpacing)
                        }

                        HStack(spacing: rowSpacing) {
                            Image(systemName: "doc.text")
                                .foregroundColor(.secondary)
                                .frame(width: rowIconWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("File name template")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                Text("Renames each copied item before it is placed in the destination.")
                                    .font(FilmCanFont.body(11))
                                    .foregroundColor(FilmCanTheme.textSecondary)
                            }
                            .frame(width: rowTextWidth, alignment: .leading)
                            Toggle("", isOn: presetBinding.useRenameTemplate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .scaleEffect(0.8)
                                .tint(FilmCanTheme.toggleTint)
                                .frame(width: rowToggleWidth, alignment: .leading)
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
                                .padding(.leading, rowIconWidth + rowSpacing)
                            TokenFlowLayout(spacing: 10) {
                                ForEach(tokenList, id: \.token) { entry in
                                    TokenChip(text: entry.token)
                                        .help(entry.description)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, rowIconWidth + rowSpacing)
                        }

                        HStack(spacing: rowSpacing) {
                            Image(systemName: "calendar")
                                .foregroundColor(.secondary)
                                .frame(width: rowIconWidth)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Custom date for tokens")
                                    .font(FilmCanFont.label(13))
                                    .foregroundColor(FilmCanTheme.textPrimary)
                                Text("Use a specific date for {date}, {time}, {datetime}.")
                                    .font(FilmCanFont.body(11))
                                    .foregroundColor(FilmCanTheme.textSecondary)
                            }
                            .frame(width: rowTextWidth, alignment: .leading)
                            Toggle("", isOn: presetBinding.useCustomDate)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .scaleEffect(0.8)
                                .tint(FilmCanTheme.toggleTint)
                                .frame(width: rowToggleWidth, alignment: .leading)
                        }

                        if presetBinding.useCustomDate.wrappedValue {
                            DatePicker(
                                "Date",
                                selection: presetBinding.customDate,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.field)
                            .padding(.leading, rowIconWidth + rowSpacing)
                        }
                    }
                    .padding(.leading, rowLeadingAdjustment)
                    .padding(.bottom, 16)

                    VStack(alignment: .leading, spacing: 10) {
                        DisclosureGroup(isExpanded: $showCopyOnlyPatterns) {
                            Text("Copy only files that match these patterns while keeping the full folder structure.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            PatternEditor(
                                title: "",
                                placeholder: "*.mov\n*.mp4",
                                patterns: presetBinding.copyOnlyPatterns,
                                showsTitle: false
                            )
                        } label: {
                            HStack {
                                Text("Copy-only patterns (optional)")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showCopyOnlyPatterns.toggle() }
                        }

                        DisclosureGroup(isExpanded: $showIncludePatterns) {
                            Text("Only include items that match these patterns. Everything else is ignored.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            PatternEditor(
                                title: "",
                                placeholder: "A*\nB*",
                                patterns: presetBinding.includePatterns,
                                showsTitle: false
                            )
                        } label: {
                            HStack {
                                Text("Include patterns (optional)")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showIncludePatterns.toggle() }
                        }

                        DisclosureGroup(isExpanded: $showExcludePatterns) {
                            Text("Always exclude items that match these patterns.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            PatternEditor(
                                title: "",
                                placeholder: "*.tmp\n.DS_Store",
                                patterns: presetBinding.excludePatterns,
                                showsTitle: false
                            )
                        } label: {
                            HStack {
                                Text("Exclude patterns (optional)")
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { showExcludePatterns.toggle() }
                        }
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Text("Select a preset to edit destination organization settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: selectedPresetId) { _ in
            isEditingPresetName = false
            isPresetNameFocused = false
        }
    }

    private var selectedIndex: Int? {
        guard let id = selectedPresetId else { return nil }
        return presets.firstIndex { $0.id == id }
    }

    private var editingPresetBinding: Binding<OrganizationPreset>? {
        if let index = selectedIndex {
            return Binding<OrganizationPreset>(
                get: { presets[index] },
                set: { presets[index] = $0 }
            )
        }
        if allowsLocalPreset {
            return localPreset
        }
        return nil
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
}

struct TokenChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .textSelection(.disabled)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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

struct PatternEditor: View {
    let title: String
    let placeholder: String
    @Binding var patterns: [String]
    var showsTitle: Bool = true
    @State private var editorText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showsTitle {
                Text(title)
                    .font(.subheadline)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $editorText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 56)
                .focused($isFocused)
                .onChange(of: editorText) { newValue in
                    let newPatterns = splitPatterns(newValue)
                    if newPatterns != patterns {
                        patterns = newPatterns
                    }
                }

                if editorText.isEmpty {
                    Text(placeholder)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
            Text("One pattern per line")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .onAppear {
            editorText = patterns.joined(separator: "\n")
        }
        .onChange(of: patterns) { newValue in
            guard !isFocused else { return }
            let joined = newValue.joined(separator: "\n")
            if editorText != joined {
                editorText = joined
            }
        }
    }

    private func splitPatterns(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
