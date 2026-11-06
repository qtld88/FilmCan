import SwiftUI
import AppKit

// MARK: - Root

struct QuickCopyWindowView: View {
    @ObservedObject var session: QuickCopySession

    var body: some View {
        ZStack {
            FilmCanTheme.background.ignoresSafeArea()
            switch session.phase {
            case .setup:
                QuickCopySetupView(session: session)
            case .running, .finished:
                QuickCopyProgressView(session: session, worker: session.worker)
            }
        }
        .foregroundColor(FilmCanTheme.textPrimary)
    }
}

// MARK: - Shared bits

private enum QCPanelStyle {
    /// Copy From / Save To: the data cards, headed loud.
    case data(icon: String? = nil)
    /// Settings: recessed, darker, dashed — reads as "how", not "what".
    case settings
}

private struct QCPanel<Content: View>: View {
    let title: String
    var trailing: String?
    var style: QCPanelStyle = .settings
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var header: some View {
        switch style {
        case .data(let icon):
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(FilmCanTheme.brandYellow)
                }
                Text(title).font(FilmCanFont.title(16)).foregroundColor(FilmCanTheme.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing).font(FilmCanFont.label(11)).foregroundColor(FilmCanTheme.textSecondary)
                }
            }
            .padding(.bottom, 2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(FilmCanTheme.brandYellow).frame(height: 2).offset(y: 6)
            }
            .padding(.bottom, 6)
        case .settings:
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11, weight: .semibold))
                Text(title).font(FilmCanFont.label(11))
                Spacer()
                if let trailing {
                    Text(trailing).font(FilmCanFont.body(11))
                }
            }
            .foregroundColor(FilmCanTheme.textTertiary)
        }
    }

    private var background: Color {
        if case .data = style { return FilmCanTheme.panel }
        return FilmCanTheme.settingsCard
    }

    @ViewBuilder private var border: some View {
        switch style {
        case .data:
            RoundedRectangle(cornerRadius: 8).stroke(FilmCanTheme.cardStrokeStrong, lineWidth: 1)
        case .settings:
            RoundedRectangle(cornerRadius: 8)
                .stroke(FilmCanTheme.cardStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}

private struct QCSettingRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(label).font(FilmCanFont.body(12)).foregroundColor(FilmCanTheme.textSecondary)
            Spacer()
            control.labelsHidden().frame(maxWidth: 220, alignment: .trailing)
        }
    }
}

// MARK: - Setup

struct QuickCopySetupView: View {
    @ObservedObject var session: QuickCopySession

    private var totalBytes: Int64 {
        session.form.items.compactMap { session.sizes[$0.path] }.reduce(0, +)
    }

    private var totalSize: String {
        totalBytes > 0 ? FilmCanFormatters.bytes(totalBytes) : ""
    }

    private func capacityLegend(info: DriveCapacityInfo, free: Int64, total: Int64) -> some View {
        let toCopy = min(totalBytes, free)
        let used = max(total - free, 0)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                legendItem(info.backupSegmentColor.opacity(0.6), "\(FilmCanFormatters.bytes(toCopy)) to copy")
                legendItem(info.usedColor, "\(FilmCanFormatters.bytes(used)) used")
                legendItem(info.freeColor, "\(FilmCanFormatters.bytes(max(free - toCopy, 0))) left")
            }
            if info.notEnoughSpace {
                Label("Not enough space", systemImage: "exclamationmark.triangle.fill")
                    .font(FilmCanFont.label(11)).foregroundColor(.red)
            }
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(FilmCanFont.body(10)).foregroundColor(FilmCanTheme.textTertiary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    sourcesPanel
                        .frame(width: 300)
                    flowArrow
                    VStack(alignment: .leading, spacing: 10) {
                        settingsPanel
                        if session.form.selectedPresetId == nil { savePresetPanel }
                    }
                    .frame(width: 300)
                    flowArrow
                    destinationsPanel
                        .frame(minWidth: 340, maxWidth: .infinity)
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            session.refreshCapacities()
        }
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(FilmCanTheme.textTertiary)
            .padding(.top, 40)
    }

    // Copy From
    private var sourcesPanel: some View {
        QCPanel(title: "COPY FROM",
                trailing: "\(session.form.items.count) item\(session.form.items.count == 1 ? "" : "s")"
                    + (totalSize.isEmpty ? "" : " · \(totalSize)"),
                style: .data()) {
            ForEach(Array(session.form.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(FilmCanFont.label(11))
                        .foregroundColor(.black)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(FilmCanTheme.brandYellow))
                    VStack(alignment: .leading, spacing: 1) {
                        Label(item.name, systemImage: item.kind == .sound ? "waveform" : "sdcard.fill")
                            .font(FilmCanFont.label(13)).lineLimit(1)
                        Text(item.path).font(FilmCanFont.body(10))
                            .foregroundColor(FilmCanTheme.textTertiary)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    if let bytes = session.sizes[item.path] {
                        Text(FilmCanFormatters.bytes(bytes))
                            .font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textSecondary)
                    }
                    if session.form.showsMediaKind {
                        Picker("", selection: $session.form.items[index].kind) {
                            ForEach(SourceMediaKind.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                    }
                    if session.form.items.count > 1 {
                        Button { session.removeSource(item.path) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundColor(FilmCanTheme.textSecondary)
                            .help("Remove source")
                    }
                }
            }
            Button { session.addSourceViaPanel() } label: {
                Label("Add source", systemImage: "plus")
            }
            .buttonStyle(.plain).foregroundColor(FilmCanTheme.brandYellow)
        }
    }

    // Copy To
    private var destinationsPanel: some View {
        QCPanel(title: "SAVE TO", style: .data()) {
            ForEach(Array(session.form.destinations.enumerated()), id: \.element) { index, path in
                let capacity = session.capacities[path] ?? (total: nil, available: nil)
                if index > 0 { Divider().padding(.vertical, 2) }
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label((path as NSString).lastPathComponent, systemImage: "externaldrive.fill")
                            .font(FilmCanFont.label(13)).lineLimit(1)
                        if let total = capacity.total, let free = capacity.available, total > 0 {
                            let info = DriveCapacityInfo(requiredBytes: totalBytes, available: free, total: total)
                            DriveCapacityBar(info: info, requiredBytes: totalBytes)
                                .padding(.vertical, 2)
                            capacityLegend(info: info, free: free, total: total)
                        } else {
                            Text(path).font(FilmCanFont.body(10)).foregroundColor(FilmCanTheme.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button { session.removeDestination(path) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundColor(FilmCanTheme.textSecondary)
                        .help("Remove destination")
                }
                folderTree(for: path, autoEdit: index == 0)
            }
            Button { session.addDestinationViaPanel() } label: {
                Label("Add destination", systemImage: "plus")
            }
            .buttonStyle(.plain).foregroundColor(FilmCanTheme.brandYellow)
        }
    }

    // Settings
    private var settingsPanel: some View {
        QCPanel(title: "SETTINGS") {
            QCSettingRow(label: "Preset") {
                Picker("", selection: $session.form.selectedPresetId) {
                    Text("None").tag(UUID?.none)
                    ForEach(session.form.savedPresets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            if let summary = session.form.presetSummary {
                Text(summary).font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textSecondary)
                Button("Edit in FilmCan…") { QuickCopyCoordinator.shared.showMainWindow() }
                    .buttonStyle(.link)
            } else {
                QCSettingRow(label: "Verification") {
                    Picker("", selection: $session.form.verification) {
                        ForEach(VerifyMode.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                QCSettingRow(label: "If file exists") {
                    Picker("", selection: $session.form.duplicatePolicy) {
                        ForEach(OrganizationPreset.DuplicatePolicy.allCases.filter { $0 != .ask }) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
                QCSettingRow(label: "Copy") {
                    Picker("", selection: $session.form.copyFolderContents) {
                        Text("The folder").tag(false)
                        Text("Its contents").tag(true)
                    }
                }
                QCSettingRow(label: "Organization") {
                    Picker("", selection: $session.form.organization) {
                        ForEach(QuickCopyFormModel.OrganizationMode.allCases) {
                            Text($0.displayName).tag($0)
                        }
                    }
                }
            }
            if session.form.organizationActive {
                if session.form.showsProjectField {
                    QCSettingRow(label: "Project") {
                        TextField("Project", text: $session.form.project).textFieldStyle(.roundedBorder)
                    }
                }
                if session.form.showsDayField {
                    QCSettingRow(label: "Day (optional)") {
                        TextField("Day", text: $session.form.day).textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    /// Folders the copy will create under `destination`. Renames are shared by every
    /// destination; only the first one opens an empty required name by itself.
    @ViewBuilder
    private func folderTree(for destination: String, autoEdit: Bool) -> some View {
        let lines = session.form.treePreview(for: destination)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    QCTreeRow(
                        line: line,
                        edited: session.form.isFolderNameEdited(root: line.isRoot, kind: line.mediaKind),
                        autoEdit: autoEdit,
                        copyContents: session.form.effectiveCopyFolderContents,
                        copyModeEdited: session.form.copyFolderContentsOverride != nil,
                        onSetCopyContents: { session.form.setCopyFolderContents($0) },
                        onResetCopyMode: { session.form.copyFolderContentsOverride = nil },
                        onRename: { session.form.setFolderName($0, root: line.isRoot, kind: line.mediaKind) },
                        onReset: {
                            if line.isRoot { session.form.rootFolderName = nil }
                            else if let kind = line.mediaKind { session.form.mediaFolderNames[kind] = nil }
                        })
                    .padding(.leading, CGFloat(line.depth) * 16)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(FilmCanTheme.background.opacity(0.6)))
        }
    }


    // Save as preset
    private var savePresetPanel: some View {
        QCPanel(title: "SAVE AS PRESET") {
            TextField("Preset name (empty = don't save)", text: $session.form.savePresetName)
                .textFieldStyle(.roundedBorder)
        }
    }

    // Footer
    private var footer: some View {
        let blocker = session.form.blocker
        return HStack {
            if let message = blocker?.message {
                Text(message).font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.brandRed)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { session.window?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
            Button("Run") { session.run() }
                .keyboardShortcut(.defaultAction)
                .disabled(blocker != nil)
        }
        .padding(12)
    }
}

/// One folder of the preview. Editable folders (top folder, Camera/Sound folder)
/// are renamed in place; the text lives in local state so a focused field never
/// writes back a stale suggestion.
private struct QCTreeRow: View {
    let line: QuickCopyFormModel.TreeLine
    let edited: Bool
    var autoEdit = true
    var copyContents = false
    var copyModeEdited = false
    var onSetCopyContents: (Bool) -> Void = { _ in }
    var onResetCopyMode: () -> Void = {}
    let onRename: (String) -> Void
    let onReset: () -> Void

    @State private var editing = false
    @State private var text = ""
    @State private var original = ""
    @FocusState private var focused: Bool

    private var needsName: Bool { line.isEditable && line.name.isEmpty }

    private var icon: String {
        switch line.role {
        case .folder: return "folder"
        case .copiedFolder: return "folder.fill"
        case .copiedFile: return "doc"
        case .contents: return "doc.on.doc"
        case .hashListOnly: return "number.square"
        }
    }
    private var mono: Font { .system(size: 11, design: .monospaced) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).frame(width: 14)
            if editing {
                TextField(line.mediaKind.map { "\($0.displayName) folder name" } ?? "Folder name", text: $text)
                    .font(mono)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .frame(maxWidth: 260)
                    .overlay(RoundedRectangle(cornerRadius: 4)
                        .stroke(text.isEmpty ? FilmCanTheme.brandRed : FilmCanTheme.brandYellow, lineWidth: 1))
                    .onChange(of: text) { onRename($0) }
                    .onSubmit { if !text.isEmpty { editing = false } }
                    .onExitCommand { text = original; editing = needsName }
                    .onChange(of: focused) { if !$0, !text.isEmpty { editing = false } }
            } else if line.togglesCopyMode {
                Text(line.name).font(mono)
                Button { onSetCopyContents(!copyContents) } label: {
                    Image(systemName: "pencil").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                .help(copyContents ? "Copy the whole folder instead" : "Copy only its contents instead")
                if copyModeEdited {
                    Button(action: onResetCopyMode) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                    .help("Back to the preset's choice")
                }
            } else {
                Text(line.name).font(mono)
                if line.isEditable {
                    Button(action: startEditing) {
                        Image(systemName: "pencil").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                    .help("Rename this folder")
                    if edited {
                        Button(action: onReset) {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                        }
                        .buttonStyle(.plain).foregroundColor(FilmCanTheme.textTertiary)
                        .help("Back to the preset's name")
                    }
                }
            }
        }
        .foregroundColor(line.isNew ? FilmCanTheme.brandYellow : FilmCanTheme.textSecondary)
        .onAppear { if needsName && autoEdit { startEditing() } }
    }

    private func startEditing() {
        original = line.name
        text = line.name
        editing = true
        DispatchQueue.main.async { focused = true }
    }
}

// MARK: - Progress / result

struct QuickCopyProgressView: View {
    @ObservedObject var session: QuickCopySession
    @ObservedObject var worker: TransferViewModel

    private var destinations: [String] { session.form.destinations }
    /// Results are on screen (the run's tail may still be writing history etc.).
    private var finished: Bool { session.resultsComplete }
    private var fullyFinished: Bool { session.phase == .finished }

    private func result(for destination: String) -> TransferResult? {
        worker.results.last { $0.destination == destination }
    }

    private var anySuccess: Bool { worker.results.contains { $0.success } }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    ForEach(destinations, id: \.self) { destination in
                        destinationCard(destination)
                    }
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .sheet(item: $worker.activeDuplicatePrompt) { prompt in
            DuplicatePromptSheet(
                prompt: prompt,
                onDecision: { action, applyToAll, counterTemplate in
                    worker.submitDuplicateResolution(
                        action: action,
                        applyToAll: applyToAll,
                        counterTemplate: counterTemplate
                    )
                },
                onCancel: {
                    worker.cancelRunFromDuplicatePrompt()
                }
            )
            .interactiveDismissDisabled()
        }
        .sheet(item: $worker.activeRollIdentityPrompt) { prompt in
            RollIdentitySheet(prompt: prompt) { isResume in
                worker.submitRollIdentity(isResume: isResume)
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(
            get: { !worker.pendingUnreadableFiles.isEmpty },
            set: { if !$0 { worker.resolveUnreadable(proceed: false) } }
        )) {
            UnreadableFilesSheet(
                paths: worker.pendingUnreadableFiles,
                onContinue: { worker.resolveUnreadable(proceed: true) },
                onCancel: { worker.resolveUnreadable(proceed: false) }
            )
        }
    }

    private var header: some View {
        HStack {
            if finished && !fullyFinished {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finalizing…").font(FilmCanFont.title(18))
                }
            } else {
                Text(fullyFinished ? "Finished" : "Copying…").font(FilmCanFont.title(18))
            }
            Spacer()
            Text("\(session.form.items.count) item\(session.form.items.count == 1 ? "" : "s") → "
                 + "\(destinations.count) destination\(destinations.count == 1 ? "" : "s")")
                .font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func destinationCard(_ destination: String) -> some View {
        let name = (destination as NSString).lastPathComponent
        QCPanel(title: name.uppercased(), style: .data(icon: "externaldrive.fill")) {
            ForEach(session.form.copyFolders(for: destination), id: \.self) { folder in
                Button { openInFinder(folder, under: destination) } label: {
                    Label(folder, systemImage: "folder")
                        .font(FilmCanFont.body(11)).lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.link)
                .help("Open in Finder")
            }
            if worker.alreadyBackedUp != nil {
                Label("Already backed up — nothing to copy", systemImage: "checkmark.circle.fill")
                    .foregroundColor(FilmCanTheme.brandGreen)
            } else if let result = result(for: destination) {
                resultRow(result)
            } else if finished {
                let fallback = worker.results.first(where: { !$0.success })?.errorMessage
                Label(fallback ?? "Not completed", systemImage: "xmark.circle.fill")
                    .foregroundColor(FilmCanTheme.brandRed)
            } else {
                let live = worker.progress.perDestProgress.first { $0.id == destination }
                    ?? DestProgress(id: destination, displayName: name, status: .preparing,
                                    verifyMode: session.form.effectiveVerification)
                InlineFanOutProgress(progress: live, showPill: true,
                                     multiDestination: destinations.count > 1)
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: TransferResult) -> some View {
        if result.success {
            VStack(alignment: .leading, spacing: 4) {
                let verified = session.form.effectiveVerification != .off
                Label(verified ? "Copied and verified" : "Copied",
                      systemImage: "checkmark.circle.fill")
                    .foregroundColor(FilmCanTheme.brandGreen)
                Text("\(result.filesTransferred) file\(result.filesTransferred == 1 ? "" : "s") copied"
                     + (result.filesSkipped > 0 ? ", \(result.filesSkipped) already present" : ""))
                    .font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textSecondary)
                if let warning = result.warningMessage {
                    Text(warning).font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.brandOrange)
                }
            }
        } else {
            Label(result.errorMessage ?? "Failed", systemImage: "xmark.circle.fill")
                .foregroundColor(FilmCanTheme.brandRed)
        }
    }

    private var footer: some View {
        HStack {
            if finished {
                Button("Show in Finder") { revealInFinder() }
                    .disabled(!(anySuccess || worker.alreadyBackedUp != nil))
                Button("Back to settings") { session.backToSetup() }
                    .disabled(!fullyFinished)
                Spacer()
                Button("Close") { session.window?.performClose(nil) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!fullyFinished)
            } else {
                Spacer()
                Button(session.stopRequested ? "Stopping…" : "Stop") { session.stop() }
                    .disabled(session.stopRequested)
            }
        }
        .padding(12)
    }

    /// Before the copy creates it, the folder may not exist yet: open the nearest
    /// existing parent, never above the destination.
    private func openInFinder(_ folder: String, under destination: String) {
        var path = folder
        while !FileManager.default.fileExists(atPath: path), path.count > destination.count {
            path = (path as NSString).deletingLastPathComponent
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func revealInFinder() {
        let destination: String
        if worker.alreadyBackedUp != nil {
            guard let first = destinations.first else { return }
            destination = first
        } else {
            guard let ok = worker.results.first(where: { $0.success }) else { return }
            destination = ok.destination
        }
        let path = session.form.revealPath(for: destination)
        let target = FileManager.default.fileExists(atPath: path) ? path : destination
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: target)])
    }
}
