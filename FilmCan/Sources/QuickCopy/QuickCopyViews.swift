import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
        .accentColor(FilmCanTheme.brandYellow)
        .tint(FilmCanTheme.brandYellow)
    }
}

// MARK: - Shared bits

private enum QCPanelStyle {
    /// Copy From / Save To: the data cards, headed loud.
    case data(icon: String? = nil, accent: Color? = nil)
    /// Settings: recessed and darker — reads as "how", not "what".
    case settings
}

private struct QCPanel<Content: View>: View {
    let title: String
    var trailing: String?
    var style: QCPanelStyle = .settings
    @ViewBuilder var content: Content

    var body: some View {
        switch style {
        case .data(let icon, let accent):
            FCCard(title: title, trailing: trailing, role: .data, dot: icon == nil ? FilmCanTheme.brandYellow : nil,
                   icon: icon, accent: accent ?? FilmCanTheme.brandYellow) { content }
        case .settings:
            FCCard(title: title, trailing: trailing, role: .settings, icon: "slider.horizontal.3") { content }
        }
    }
}

/// Accepts Finder file/folder drops and hands the paths over in one batch.
/// Highlights the card with a dashed yellow border while a drag hovers it.
private struct QCFileDrop: ViewModifier {
    let onPaths: ([String]) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: FCRadius.card)
                    .strokeBorder(FilmCanTheme.brandYellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .opacity(isTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                load(providers)
                return true
            }
    }

    private func load(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [Int: URL] = [:]
        for (index, provider) in providers.enumerated()
        where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                lock.lock(); urls[index] = url; lock.unlock()
            }
        }
        group.notify(queue: .main) {
            let paths = urls.sorted { $0.key < $1.key }.map { $0.value.standardizedFileURL.path }
            if !paths.isEmpty { onPaths(paths) }
        }
    }
}

private extension View {
    func qcFileDrop(_ onPaths: @escaping ([String]) -> Void) -> some View {
        modifier(QCFileDrop(onPaths: onPaths))
    }
}

private struct QCChipFlow: View {
    let chips: [String]

    var body: some View {
        QCWrapLayout(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(FCType.metaStrong)
                    .foregroundColor(FilmCanTheme.textPrimary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(FilmCanTheme.background.opacity(0.7)))
                    .overlay(Capsule().stroke(FilmCanTheme.cardStroke, lineWidth: 1))
            }
        }
    }
}

private struct QCWrapLayout: Layout {
    var spacing: CGFloat

    private func place(_ subviews: Subviews, in width: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        place(subviews, in: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = place(subviews, in: bounds.width)
        for (view, point) in zip(subviews, result.positions) {
            view.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }
}

private struct QCSettingRow<Control: View>: View {
    let label: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack {
            Text(label).font(FCType.body).foregroundColor(FilmCanTheme.textSecondary)
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
                legendItem(info.usedColor, "\(FilmCanFormatters.bytes(used)) used")
                legendItem(info.backupSegmentColor.opacity(FCCapacity.toCopyOpacity), "\(FilmCanFormatters.bytes(toCopy)) to copy")
                legendItem(info.freeColor, "\(FilmCanFormatters.bytes(max(free - toCopy, 0))) left")
            }
            if info.notEnoughSpace {
                Label("Not enough space", systemImage: "exclamationmark.triangle.fill")
                    .font(FCType.metaStrong).foregroundColor(FilmCanTheme.dangerText)
            }
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(FCType.meta).foregroundColor(FilmCanTheme.textTertiary)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 10) {
                        sourcesPanel
                        settingsPanel
                        if session.form.selectedPresetId == nil { savePresetPanel }
                    }
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
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
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(FCType.metaStrong)
                        .foregroundColor(.black)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(FilmCanTheme.brandYellow))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Label(item.name, systemImage: item.kind == .sound ? "waveform" : "sdcard.fill")
                                .font(FCType.itemTitle).lineLimit(1).truncationMode(.middle)
                                .help(item.name)
                            Spacer(minLength: 4)
                            if let bytes = session.sizes[item.path] {
                                Text(FilmCanFormatters.bytes(bytes))
                                    .font(FCType.meta).foregroundColor(FilmCanTheme.textSecondary)
                                    .fixedSize()
                            }
                        }
                        HStack(spacing: 8) {
                            Text(item.path).font(FCType.meta)
                                .foregroundColor(FilmCanTheme.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                                .help(item.path)
                            Spacer(minLength: 4)
                            if session.form.showsMediaKind {
                                CameraSoundSwitch(kind: item.kind) { session.form.items[index].kind = $0 }
                            }
                            if session.form.items.count > 1 {
                                Button { session.removeSource(item.path) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).foregroundColor(FilmCanTheme.textSecondary)
                                    .help("Remove source")
                            }
                        }
                    }
                }
            }
            Button { session.addSourceViaPanel() } label: {
                Label("Add source", systemImage: "plus")
            }
            .buttonStyle(.plain).foregroundColor(FilmCanTheme.brandYellow)
            .help("Or drop files and folders on this card")
        }
        .qcFileDrop { session.addSources($0) }
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
                            .font(FCType.itemTitle).lineLimit(1)
                        if let total = capacity.total, let free = capacity.available, total > 0 {
                            let info = DriveCapacityInfo(requiredBytes: totalBytes, available: free, total: total)
                            DriveCapacityBar(info: info, requiredBytes: totalBytes)
                                .padding(.vertical, 2)
                            capacityLegend(info: info, free: free, total: total)
                        } else {
                            Text(path).font(FCType.meta).foregroundColor(FilmCanTheme.textTertiary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Button { session.removeDestination(path) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).foregroundColor(FilmCanTheme.textSecondary)
                        .help("Remove destination")
                }
                if !sharedTree { folderTree(for: path, autoEdit: index == 0) }
            }
            Button { session.addDestinationViaPanel() } label: {
                Label("Add destination", systemImage: "plus")
            }
            .buttonStyle(.plain).foregroundColor(FilmCanTheme.brandYellow)
            .help("Or drop folders or drives on this card")
            if sharedTree, let first = session.form.destinations.first {
                Divider().padding(.vertical, 2)
                Text("Folders on every drive")
                    .font(FCType.metaStrong).foregroundColor(FilmCanTheme.textSecondary)
                folderTree(for: first, autoEdit: true)
            }
        }
        .qcFileDrop { session.addDestinations($0) }
    }

    /// One tree stands for every destination unless they would differ (a folder that
    /// exists on one drive only changes the "new" highlight).
    private var sharedTree: Bool {
        let destinations = session.form.destinations
        guard let first = destinations.first else { return false }
        let reference = session.form.treePreview(for: first)
        return destinations.dropFirst().allSatisfy { session.form.treePreview(for: $0) == reference }
    }

    // Settings
    private var settingsPanel: some View {
        QCPanel(title: "SETTINGS") {
            QCSettingRow(label: "Movie") {
                Picker("", selection: Binding(
                    get: { session.form.selectedFilmId },
                    set: { session.selectFilm($0) })) {
                    Text("None").tag(UUID?.none)
                    ForEach(session.form.savedFilms) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            .help("History and the catalog file this copy under the movie.")
            if let filmPreset = session.form.filmPresetName {
                Text(session.form.presetDiffersFromFilm
                     ? "Preset changed for this copy (movie uses \u{201C}\(filmPreset)\u{201D})"
                     : "Preset of this movie: \u{201C}\(filmPreset)\u{201D}")
                    .font(FCType.meta)
                    .foregroundColor(session.form.presetDiffersFromFilm
                                     ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary)
            }
            QCSettingRow(label: "Preset") {
                Picker("", selection: $session.form.selectedPresetId) {
                    Text("None").tag(UUID?.none)
                    ForEach(session.form.savedPresets) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            if let chips = session.form.presetChips {
                QCChipFlow(chips: chips).help(session.form.presetChipsHelp ?? "")
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
    private func folderTree(for destination: String, autoEdit: Bool) -> some View {
        let form = session.form
        return FolderTreePreview(
            lines: form.treePreview(for: destination),
            editing: FolderTreeEditing(
                autoEdit: autoEdit,
                copyContents: form.effectiveCopyFolderContents,
                copyModeEdited: form.copyFolderContentsOverride != nil,
                isEdited: { form.isFolderNameEdited(root: $0.isRoot, kind: $0.mediaKind) },
                onSetCopyContents: { session.form.setCopyFolderContents($0) },
                onResetCopyMode: { session.form.copyFolderContentsOverride = nil },
                onRename: { line, name in session.form.setFolderName(name, root: line.isRoot, kind: line.mediaKind) },
                onReset: { line in
                    if line.isRoot { session.form.rootFolderName = nil }
                    else if let kind = line.mediaKind { session.form.mediaFolderNames[kind] = nil }
                }))
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
                Text(message).font(FCType.meta).foregroundColor(FilmCanTheme.dangerText)
                    .lineLimit(2)
            }
            Spacer()
            Button("Cancel") { session.window?.performClose(nil) }
                .keyboardShortcut(.cancelAction)
            Button("Run") { session.run() }
                .buttonStyle(FCPrimaryButtonStyle())
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

    private var allActiveDestsVerifying: Bool {
        let active = worker.progress.perDestProgress.filter { dest in
            guard destinations.contains(dest.id) else { return false }
            if case .active = dest.status { return true }
            return false
        }
        return !active.isEmpty && active.allSatisfy(\.isVerifyOnly)
    }

    private func cardAccent(for destination: String) -> Color {
        if worker.alreadyBackedUp != nil { return FilmCanTheme.brandGreen }
        if let result = result(for: destination) {
            return result.success ? FilmCanTheme.brandGreen : FilmCanTheme.brandRed
        }
        return finished ? FilmCanTheme.brandRed : FilmCanTheme.brandYellow
    }

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
                Text(fullyFinished ? "Finished" : (allActiveDestsVerifying ? "Verifying…" : "Copying…"))
                    .font(FilmCanFont.title(18))
            }
            Spacer()
            Text("\(session.form.items.count) item\(session.form.items.count == 1 ? "" : "s") → "
                 + "\(destinations.count) destination\(destinations.count == 1 ? "" : "s")")
                .font(FCType.meta).foregroundColor(FilmCanTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func destinationCard(_ destination: String) -> some View {
        let name = (destination as NSString).lastPathComponent
        QCPanel(title: name, style: .data(icon: "externaldrive.fill", accent: cardAccent(for: destination))) {
            ForEach(session.form.copyFolders(for: destination), id: \.self) { folder in
                Button { openInFinder(folder, under: destination) } label: {
                    Label(folder, systemImage: "folder")
                        .font(FCType.meta).lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.link)
                .help("Open in Finder")
            }
            if worker.alreadyBackedUp != nil {
                Label("Already backed up — nothing to copy", systemImage: "checkmark.circle.fill")
                    .foregroundColor(FilmCanTheme.successText)
            } else if let result = result(for: destination) {
                resultRow(result)
            } else if finished {
                let fallback = worker.results.first(where: { !$0.success })?.errorMessage
                Label(fallback ?? "Not completed", systemImage: "xmark.circle.fill")
                    .foregroundColor(FilmCanTheme.dangerText)
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
                FanOutProgressBar(copyFraction: 1, verifyFraction: 1, status: .complete)
                let verified = session.form.effectiveVerification != .off
                Label(verified ? "Copied and verified" : "Copied",
                      systemImage: "checkmark.circle.fill")
                    .foregroundColor(FilmCanTheme.successText)
                Text("\(result.filesTransferred) file\(result.filesTransferred == 1 ? "" : "s") copied"
                     + (result.filesSkipped > 0 ? ", \(result.filesSkipped) already present" : ""))
                    .font(FCType.meta).foregroundColor(FilmCanTheme.textSecondary)
                if let warning = result.warningMessage {
                    Text(warning).font(FCType.meta).foregroundColor(FilmCanTheme.brandOrange)
                }
            }
        } else {
            Label(result.errorMessage ?? "Failed", systemImage: "xmark.circle.fill")
                .foregroundColor(FilmCanTheme.dangerText)
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
                    .buttonStyle(FCPrimaryButtonStyle())
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
