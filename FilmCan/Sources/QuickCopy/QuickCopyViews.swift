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

private struct QCPanel<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(FilmCanFont.label(12)).foregroundColor(FilmCanTheme.textSecondary)
                Spacer()
                if let trailing {
                    Text(trailing).font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textTertiary)
                }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FilmCanTheme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FilmCanTheme.cardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private var totalSize: String {
        let total = session.form.items.compactMap { session.sizes[$0.path] }.reduce(0, +)
        return total > 0 ? FilmCanFormatters.bytes(total) : ""
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sourcesPanel
                    destinationsPanel
                    settingsPanel
                    if session.form.organizationActive { organizationPanel }
                    if session.form.selectedPresetId == nil { savePresetPanel }
                }
                .padding(16)
            }
            Divider()
            footer
        }
    }

    // Copy From
    private var sourcesPanel: some View {
        QCPanel(title: "COPY FROM",
                trailing: "\(session.form.items.count) item\(session.form.items.count == 1 ? "" : "s")"
                    + (totalSize.isEmpty ? "" : " · \(totalSize)")) {
            ForEach(Array(session.form.items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(FilmCanFont.label(11))
                        .foregroundColor(.black)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(FilmCanTheme.brandYellow))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(FilmCanFont.label(13)).lineLimit(1)
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
                        .labelsHidden().frame(width: 100)
                    }
                }
            }
        }
    }

    // Copy To
    private var destinationsPanel: some View {
        QCPanel(title: "COPY TO") {
            ForEach(session.form.destinations, id: \.self) { path in
                let capacity = DriveUtilities.capacity(for: path)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((path as NSString).lastPathComponent).font(FilmCanFont.label(13)).lineLimit(1)
                        if let total = capacity.total, let free = capacity.available, total > 0 {
                            ProgressView(value: Double(total - free), total: Double(total))
                                .tint(FilmCanTheme.brandYellow)
                            Text("\(FilmCanFormatters.bytes(free)) free of \(FilmCanFormatters.bytes(total))")
                                .font(FilmCanFont.body(10)).foregroundColor(FilmCanTheme.textTertiary)
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
        }
    }

    // Organization
    private var organizationPanel: some View {
        QCPanel(title: "ORGANIZATION") {
            QCSettingRow(label: "Date") {
                HStack {
                    Toggle("Pick a date", isOn: Binding(
                        get: { session.form.pickedDate != nil },
                        set: { session.form.pickedDate = $0 ? Date() : nil }))
                        .toggleStyle(.checkbox)
                    if session.form.pickedDate != nil {
                        DatePicker("", selection: Binding(
                            get: { session.form.pickedDate ?? Date() },
                            set: { session.form.pickedDate = $0 }), displayedComponents: .date)
                    } else {
                        Text("Today").foregroundColor(FilmCanTheme.textSecondary)
                    }
                }
            }
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
            if let first = session.form.destinations.first {
                Divider()
                Text("Will be created in \((first as NSString).lastPathComponent)")
                    .font(FilmCanFont.body(11)).foregroundColor(FilmCanTheme.textTertiary)
                let lines = session.form.treePreview(for: first)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(spacing: 6) {
                        Image(systemName: "folder").font(.system(size: 10))
                        Text(line.name).font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.leading, CGFloat(line.depth) * 16)
                    .foregroundColor(line.isNew ? FilmCanTheme.brandYellow : FilmCanTheme.textSecondary)
                }
            }
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
        QCPanel(title: name.uppercased(), trailing: destination) {
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
