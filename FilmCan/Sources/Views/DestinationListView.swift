import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DestinationListView: View {
    @Binding var destinations: [String]
    @ObservedObject var transferViewModel: TransferViewModel
    @ObservedObject var progress: TransferProgress
    @ObservedObject private var driveCache = DriveInfoCache.shared
    var refreshToken: Int = 0
    @State private var isDropTargeted: Bool = false
    @State private var dragPayload: String? = nil
    @State private var draggingDriveId: String? = nil
    @State private var draggingPath: String? = nil
    @State private var knownDestinations: Set<String> = []
    @State private var ejectErrorMessage: String? = nil
    var showsTitle: Bool = true
    var headerView: AnyView? = nil
    var footerView: AnyView? = nil
    var isTourHighlighted: Bool = false
    var requiredBytes: Int64 = 0
    var organizationPreset: OrganizationPreset? = nil
    var sourcePaths: [String] = []
    /// Camera/Sound tag per source path, so the preview shows the Camera_Media /
    /// Sound_Media path the source will actually land in.
    var mediaKind: (String) -> SourceMediaKind = { _ in .camera }
    /// Roll folder given to a generic-named card (Untitled_01), shown in the folder tree.
    var rollName: (String) -> String? = { _ in nil }
    var shootMetadata: ShootMetadata = .empty
    var copyFolderContents: Bool = true
    var configId: UUID
    var postVerifyEnabled: Bool = false
    var fulfilledDestinations: Set<String> = []
    /// Checkbox per drive: unchecked drives stay listed, greyed, but get no copy.
    var isIncluded: (String) -> Bool = { _ in true }
    var setIncluded: (([String], Bool) -> Void)? = nil
    @ObservedObject private var todayClock = TodayClock.shared
    private var isActiveTransfer: Bool {
        transferViewModel.isTransferActive(for: configId)
    }
    
    var body: some View {
        let _ = refreshToken
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text("Save To")
                    .font(FCType.bodyStrong)
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
            
            VStack(spacing: 8) {
                if let headerView {
                    headerView
                }
                if destinations.isEmpty {
                    // EMPTY STATE - Big and obvious
                    emptyDropZone
                } else {
                    // Grouped by drive
                    driveBlocks
                }

                if isActiveTransfer {
                    transferControls
                }
                
                // Add button (always visible)
                if !destinations.isEmpty {
                    Button(action: addDestination) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(FilmCanTheme.brandYellow)
                            Text("Add another destination")
                                .font(FCType.body)
                        }
                    }
                    .buttonStyle(.borderless)
                }

                if sharedTree, let first = treeDestinations.first {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Folders on every drive")
                            .font(FCType.metaStrong)
                            .foregroundColor(FilmCanTheme.textSecondary)
                        FolderTreePreview(lines: treeLines(for: first))
                    }
                }
                
                if let footerView {
                    footerView
                }
            }
            .fcCardSurface(
                role: .data,
                strokeColor: isDropTargeted || isTourHighlighted ? FilmCanTheme.brandYellow : nil,
                lineWidth: isDropTargeted || isTourHighlighted ? 2 : FCStroke.hairline,
                dash: isDropTargeted ? [6, 4] : []
            )
            .shadow(color: isTourHighlighted ? FilmCanTheme.brandYellow.opacity(0.35) : .clear, radius: 10)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
            }
            .onAppear {
                knownDestinations = Set(destinations)
            }
            .onChange(of: destinations) { newValue in
                let updated = Set(newValue)
                let added = updated.subtracting(knownDestinations)
                if !added.isEmpty {
                    for path in added {
                        transferViewModel.resetDestinationPresentation(for: path)
                    }
                }
                knownDestinations = updated
            }
            .alert("Couldn't eject drive", isPresented: Binding(
                get: { ejectErrorMessage != nil },
                set: { if !$0 { ejectErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { ejectErrorMessage = nil }
            } message: {
                Text(ejectErrorMessage ?? "")
            }
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundColor(FilmCanTheme.brandYellow.opacity(isDropTargeted ? 1.0 : 0.6))
                .opacity(isDropTargeted ? 1.0 : 0.8)
                .scaleEffect(isDropTargeted ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDropTargeted)
            
            VStack(spacing: 4) {
                Text("Drop destination folder here")
                    .font(FCType.cardTitle)
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text("or")
                    .font(FCType.meta)
                    .foregroundColor(FilmCanTheme.textSecondary)
            }
            
            Button("Browse Folders...") {
                addDestination()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
    }
    
    private var driveBlocks: some View {
        let summaries = driveSummaries(for: destinations)
        let fulfilled = fulfilledDestinationsForCurrentConfig()
        let numbers = DriveIncludeColumn.numbers(for: summaries.map(\.id)) { id in
            summaries.first { $0.id == id }?.paths.contains { isIncluded($0.path) } ?? true
        }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(summaries) { summary in
                let paths = summary.paths.map(\.path)
                let driveIncluded = paths.contains(where: isIncluded)
                let driveRequiredBytes = driveIncluded ? requiredBytes : 0
                let backupStoredOnDrive = !isActiveTransfer
                    ? driveHasStoredBackup(
                        summary: summary,
                        fulfilledDestinations: fulfilled
                    )
                    : false
                HStack(alignment: .center, spacing: 12) {
                    DriveIncludeColumn(
                        number: numbers[summary.id],
                        isIncluded: driveIncluded,
                        isLocked: isActiveTransfer,
                        setIncluded: setIncluded.map { set in { set(paths, $0) } })
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: DriveUtilities.driveIconName(isExternal: summary.isExternal, style: .filled))
                                .foregroundColor(FilmCanTheme.textSecondary)
                                .frame(width: 18)
                            Text(driveIncluded ? summary.name : "\(summary.name) · Skipped")
                                .font(FCType.itemTitle)
                                .foregroundColor(FilmCanTheme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if summary.isConnected, let first = summary.paths.first?.path {
                                EjectButton(path: first, onError: { ejectErrorMessage = $0 })
                            }
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Remove drive from this backup") {
                                removeDriveGroup(summary.id)
                            }
                            Button("Remove and eject drive from this backup") {
                                removeAndEjectDriveGroup(summary.id, paths: summary.paths)
                            }
                            Button("Eject drive") {
                                ejectDriveGroup(paths: summary.paths)
                            }
                        }
                    
                        if summary.isConnected {
                            destinationCapacityBlock(
                                summary: summary,
                                requiredBytes: driveRequiredBytes,
                                backupStoredOnDrive: backupStoredOnDrive
                            )
                            .padding(.leading, 26)
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(summary.paths) { destination in
                                    destinationPathRow(destination: destination, isExternal: summary.isExternal)
                                }
                            }
                            .padding(.leading, 26)

                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(summary.paths) { destination in
                                    destinationPathRow(destination: destination, isExternal: summary.isExternal)
                                }
                                Text(summary.connectionMessage)
                                    .font(FCType.meta)
                                    .foregroundColor(FilmCanTheme.dangerText)
                            }
                            .padding(.leading, 26)
                        }
                    }
                    .opacity(driveIncluded ? 1 : 0.4)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: FCRadius.inner)
                        .fill(FilmCanTheme.card)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FCRadius.inner)
                        .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
                )
                .cornerRadius(FCRadius.inner)
                .anchorPreference(key: DriveAnchorPreferenceKey.self, value: .bounds) { bounds in
                    DriveAnchorData(destinations: [summary.id: bounds])
                }
                .onDrag {
                    let payload = "drive:\(summary.id)"
                    dragPayload = payload
                    draggingDriveId = summary.id
                    return NSItemProvider(object: payload as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: DriveDropDelegate(
                        targetId: summary.id,
                        draggingId: $draggingDriveId,
                        moveAction: { fromId, toId in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                moveDriveGroup(fromId: fromId, toId: toId)
                            }
                        }
                    )
                )
            }
        }
    }

    private func destinationPathRow(destination: DestinationPath, isExternal: Bool) -> some View {
        let icon = DriveUtilities.iconName(
            isExternal: isExternal,
            isRoot: destination.isRoot,
            isDirectory: true,
            style: .filled,
            treatExternalAsDrive: false,
            treatRootAsDrive: true
        )
        let displayPaths = destinationDisplayPaths(destinationRoot: destination.path)
        let presentation = transferViewModel.destinationPresentation(
            for: destination.path,
            configId: configId,
            progress: progress
        )
        let rootLabel = destinationRootLabel(destination.path)
        let isFanOutActive = !progress.perDestProgress.isEmpty
        let showProgress = presentation.shouldShowInfo && !isFanOutActive
        let status = presentation.status
        let progressLabelWidth: CGFloat = 120
        let percentLabelWidth: CGFloat = 42
        let rowHasContent = !destination.isRoot || treeSources.isEmpty || showProgress
            || (!sharedTree && isIncluded(destination.path))
        return VStack(alignment: .leading, spacing: 6) {
            if rowHasContent || status != .pending {
            HStack(spacing: 10) {
                statusOrDriveIcon(status: status, systemIcon: icon)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    if !destination.isRoot {
                        Text((destination.path as NSString).lastPathComponent)
                            .font(FCType.bodyStrong)
                            .foregroundColor(FilmCanTheme.textPrimary)
                            .lineLimit(1)
                    }
                    if treeSources.isEmpty {
                        Text("→ \(rootLabel)")
                            .font(FCType.meta)
                            .foregroundColor(FilmCanTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if !sharedTree, isIncluded(destination.path) {
                        FolderTreePreview(lines: treeLines(for: destination.path))
                    }
                    ForEach(displayPaths) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            if showProgress {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(copyLabelText(for: destination.path, source: item.source))
                                            .font(FCType.metaStrong)
                                            .foregroundColor(FilmCanTheme.textSecondary)
                                            .lineLimit(1)
                                            .frame(width: progressLabelWidth, alignment: .leading)
                                        ProgressView(value: progressValue(
                                            for: destination.path,
                                            source: item.source
                                        ))
                                        .progressViewStyle(ThickLinearProgressStyle(
                                            height: 6,
                                            fill: progressTintColor(for: status)
                                        ))
                                        .frame(maxWidth: .infinity)

                                        let percentText = progressPercentText(
                                            for: destination.path,
                                            source: item.source
                                        )
                                        Text(percentText ?? "")
                                            .font(FCType.metaStrong)
                                            .foregroundColor(FilmCanTheme.textSecondary)
                                            .frame(width: percentLabelWidth, alignment: .trailing)
                                            .opacity(percentText == nil ? 0 : 1)
                                    }

                                    if shouldShowVerificationRow(
                                        for: destination.path,
                                        source: item.source,
                                        showProgress: showProgress
                                    ) {
                                        HStack(spacing: 8) {
                                            Text(verificationLabelText(for: destination.path, source: item.source))
                                                .font(FCType.metaStrong)
                                                .foregroundColor(FilmCanTheme.textSecondary)
                                                .lineLimit(1)
                                                .frame(width: progressLabelWidth, alignment: .leading)
                                            ProgressView(value: verificationProgressValue(
                                                for: destination.path,
                                                source: item.source,
                                                showProgress: showProgress
                                            ))
                                                .progressViewStyle(ThickLinearProgressStyle(
                                                    height: 6,
                                                    fill: FilmCanTheme.brandBlue
                                                ))
                                                .frame(maxWidth: .infinity)

                                            let verifyPercent = verificationPercentText(
                                                for: destination.path,
                                                source: item.source,
                                                showProgress: showProgress
                                            )
                                            Text(verifyPercent ?? "")
                                                .font(FCType.metaStrong)
                                                .foregroundColor(FilmCanTheme.textSecondary)
                                                .frame(width: percentLabelWidth, alignment: .trailing)
                                                .opacity(verifyPercent == nil ? 0 : 1)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            }

            if isFanOutActive {
                if let destProg = progress.perDestProgress.first(where: { $0.id == destination.path }) {
                    InlineFanOutProgress(progress: destProg, showPill: true,
                                         multiDestination: progress.perDestProgress.count > 1)
                        .padding(.leading, 28)
                }
            } else if showProgress {
                transferInfoRow(for: destination.path, presentation: presentation)
                    .padding(.leading, 28)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Remove destination from this backup") {
                removeDestination(destination.path)
            }
            Button("Remove and eject destination from this backup") {
                removeAndEjectDestination(destination.path)
            }
        }
        .overlay(
            dragPayload == "path:\(destination.path)" ?
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor, lineWidth: 2)
                : nil
        )
        .onDrag {
            let payload = "path:\(destination.path)"
            dragPayload = payload
            draggingPath = destination.path
            return NSItemProvider(object: payload as NSString)
        }
        .onDrop(
            of: [.text],
            delegate: PathDropDelegate(
                targetPath: destination.path,
                draggingPath: $draggingPath,
                moveAction: { fromPath, toPath in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        movePath(fromPath: fromPath, toPath: toPath)
                    }
                }
            )
        )
    }

    private var treeSources: [FolderTreeBuilder.Source] {
        sourcePaths.map { path in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return FolderTreeBuilder.Source(path: path, isDirectory: isDir.boolValue, kind: mediaKind(path),
                                       rollName: isDir.boolValue ? rollName(path) : nil)
        }
    }

    private var treeOptions: FolderTreeBuilder.Options {
        var o = FolderTreeBuilder.Options()
        o.preset = organizationPreset
        o.organizationActive = organizationPreset.map {
            $0.useFolderTemplate && !FolderTreeBuilder.isBlank($0.folderTemplate)
        } ?? false
        o.copyContents = copyFolderContents
        o.date = todayClock.today
        o.metadata = shootMetadata
        o.mediaIndexPreset = organizationPreset
        return o
    }

    private func treeLines(for destination: String) -> [FolderTreeLine] {
        FolderTreeBuilder.lines(for: destination, sources: treeSources, options: treeOptions)
    }

    /// Destinations that will receive the copy (unchecked drives get none).
    private var treeDestinations: [String] {
        let included = destinations.filter(isIncluded)
        return included.isEmpty ? destinations : included
    }

    /// One tree stands for every destination unless they would differ (a folder that
    /// exists on one drive only changes the "new" highlight).
    private var sharedTree: Bool {
        guard !treeSources.isEmpty, let first = treeDestinations.first else { return false }
        let reference = treeLines(for: first)
        return treeDestinations.dropFirst().allSatisfy { treeLines(for: $0) == reference }
    }

    private func destinationRootLabel(_ path: String) -> String {
        let trimmed = displayPath(path).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : trimmed + "/"
    }

    private func displayPath(_ path: String) -> String {
        let volumesPrefix = "/Volumes/"
        guard path.hasPrefix(volumesPrefix) else { return path }
        let rest = String(path.dropFirst(volumesPrefix.count))
        return "/" + rest
    }

    private struct DestinationDisplayPath: Identifiable {
        let id: String
        let source: String
        let path: String
    }

    private func destinationDisplayPaths(destinationRoot: String) -> [DestinationDisplayPath] {
        guard !sourcePaths.isEmpty else {
            return [DestinationDisplayPath(id: destinationRoot, source: "", path: displayPath(destinationRoot))]
        }
        var paths: [DestinationDisplayPath] = []
        paths.reserveCapacity(sourcePaths.count)
        for (index, source) in sourcePaths.enumerated() {
            let finalPath = resolveDestinationPath(
                destinationRoot: destinationRoot,
                sourcePath: source,
                counter: index + 1
            )
            let display = displayPath(finalPath)
            let id = destinationRoot + "||" + source
            paths.append(DestinationDisplayPath(id: id, source: source, path: display))
        }
        return paths
    }

    private func resolveDestinationPath(
        destinationRoot: String,
        sourcePath: String,
        counter: Int
    ) -> String {
        if let preset = organizationPreset {
            let resolved = OrganizationTemplate.resolve(
                preset: preset,
                sourcePath: sourcePath,
                destinationRoot: destinationRoot,
                counter: counter,
                date: todayClock.today,
                metadata: shootMetadata,
                mediaKind: mediaKind(sourcePath)
            )
            let base: String
            if resolved.folderPath.isEmpty {
                base = destinationRoot
            } else {
                base = (destinationRoot as NSString).appendingPathComponent(resolved.folderPath)
            }
            if copyFolderContents {
                return base
            }
            return (base as NSString).appendingPathComponent(resolved.renamedItem)
        }
        let name = (sourcePath as NSString).lastPathComponent
        if copyFolderContents {
            return destinationRoot
        }
        return (destinationRoot as NSString).appendingPathComponent(name)
    }

    private var transferControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExFATBanner(activeDests: progress.perDestProgress)
            if !isActiveTransfer, !latestFanOutDestResults.isEmpty, latestFanOutDestResults.contains(where: { !$0.success }) {
                FailedDestRetryPanel(
                    results: latestFanOutDestResults,
                    sourcePaths: transferViewModel.currentSources,
                    onRepair: { failed, sibling, choice in
                        Task { @MainActor in
                            _ = await transferViewModel.repairFailedDest(failed: failed, sibling: sibling, choice: choice)
                        }
                    }
                )
            }
            HStack(spacing: 12) {
                Button(destinations.count > 1 ? "Stop Backups" : "Stop Backup") {
                    transferViewModel.cancelAll(for: configId)
                }
                .buttonStyle(.bordered)
                .tint(FilmCanTheme.dangerText)
                .disabled(transferViewModel.isCancellingAll)
                if transferViewModel.isCancellingAll, isActiveTransfer {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(destinations.count > 1
                             ? "Stopping the backups properly…"
                             : "Stopping the backup properly…")
                            .font(FCType.metaStrong)
                            .foregroundColor(FilmCanTheme.textSecondary)
                    }
                }
                Spacer()
            }
        }
        .padding(.top, 4)
    }

    /// Most-recent per-destination results from the fan-out engine.
    private var latestFanOutDestResults: [DestResult] {
        guard let mostRecent = transferViewModel.results.last(where: { !$0.destinationResults.isEmpty }) else { return [] }
        let start = mostRecent.startTime
        let end = mostRecent.endTime
        return transferViewModel.results
            .filter { $0.startTime == start && $0.endTime == end && !$0.destinationResults.isEmpty }
            .flatMap { $0.destinationResults }
    }

    private func destinationCapacityBlock(
        summary: DriveSummary,
        requiredBytes: Int64,
        backupStoredOnDrive: Bool
    ) -> some View {
        let info = DriveCapacityInfo(
            requiredBytes: requiredBytes,
            available: summary.availableBytes,
            total: summary.totalBytes,
            treatBackupAsUsed: backupStoredOnDrive
        )
        return VStack(alignment: .leading, spacing: 4) {
            DriveCapacityBar(info: info, requiredBytes: requiredBytes)
            if info.hasTotal, let total = summary.totalBytes, let available = summary.availableBytes {
                capacityLegend(
                    info: info,
                    requiredBytes: requiredBytes,
                    available: available,
                    total: total,
                    treatBackupAsUsed: backupStoredOnDrive
                )
            }
            if info.notEnoughSpace {
                Label("Not enough space", systemImage: "exclamationmark.triangle.fill")
                    .font(FCType.metaStrong)
                    .foregroundColor(FilmCanTheme.dangerText)
            }
        }
    }

    private func capacityLegend(
        info: DriveCapacityInfo,
        requiredBytes: Int64,
        available: Int64,
        total: Int64,
        treatBackupAsUsed: Bool
    ) -> some View {
        let usedBytes = max(total - available, 0)
        let toCopy: Int64
        let usedOther: Int64
        let left: Int64
        if treatBackupAsUsed {
            toCopy = min(requiredBytes, usedBytes)
            usedOther = max(usedBytes - toCopy, 0)
            left = max(total - usedBytes, 0)
        } else {
            toCopy = min(requiredBytes, max(available, 0))
            usedOther = usedBytes
            left = max(total - usedBytes - toCopy, 0)
        }
        let copyLabel = treatBackupAsUsed ? "already there" : "to copy"
        func pct(_ value: Int) -> String { value == 0 ? "<1%" : "\(value)%" }
        return HStack(spacing: 10) {
            legendItem(info.usedColor, "\(FilmCanFormatters.bytes(usedOther)) used")
            legendItem(info.backupSegmentColor.opacity(FCCapacity.toCopyOpacity),
                       "\(FilmCanFormatters.bytes(toCopy)) \(copyLabel)")
            legendItem(info.freeColor, "\(FilmCanFormatters.bytes(left)) left")
        }
        .help("\(pct(info.usedPercent)) used · \(pct(info.backupPercent)) \(copyLabel) · \(pct(info.freePercent)) left")
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(FCType.meta)
                .foregroundColor(FilmCanTheme.textSecondary)
        }
    }

    private func fulfilledDestinationsForCurrentConfig() -> Set<String> {
        var fulfilled = fulfilledDestinations
        guard isActiveTransfer else { return fulfilled }
        for result in transferViewModel.results where result.success {
            fulfilled.insert(result.destination)
        }
        return fulfilled
    }

    private func driveHasStoredBackup(
        summary: DriveSummary,
        fulfilledDestinations: Set<String>
    ) -> Bool {
        guard !summary.paths.isEmpty else { return false }
        return summary.paths.allSatisfy { fulfilledDestinations.contains($0.path) }
    }

    // MARK: - Transfer Status

    private func transferResult(for destination: String) -> TransferResult? {
        transferViewModel.results.last { $0.destination == destination }
    }

    private func transferInfoRow(
        for destination: String,
        presentation: TransferViewModel.DestinationPresentation
    ) -> some View {
        let failureText = presentation.failureMessage
        let failureDetails = failureDetails(for: destination)
        let warning = presentation.warningMessage
        let showCancel = presentation.canCancel
        return VStack(alignment: .leading, spacing: 10) {
            if let failureText {
                HStack(alignment: .top, spacing: 10) {
                    Text(failureText)
                        .font(FCType.cardTitle)
                        .foregroundColor(FilmCanTheme.dangerText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    if let failureDetails {
                        InfoPopoverButton(content: failureDetails)
                    }
                    Spacer()
                    if showCancel {
                        Button("Cancel") { transferViewModel.cancelDestination(destination) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } else if showCancel {
                HStack {
                    Spacer()
                    Button("Cancel") { transferViewModel.cancelDestination(destination) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            if let warning, !warning.isEmpty {
                HStack {
                    Spacer(minLength: 0)
                    Text(warning)
                        .font(FCType.body)
                        .foregroundColor(FilmCanTheme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 16) {
                Label(presentation.progressText, systemImage: "externaldrive")
                    .font(FCType.body)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 160, alignment: .leading)
                Label(presentation.speedText, systemImage: "speedometer")
                    .font(FCType.body)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 140, alignment: .leading)
                Label(presentation.etaText, systemImage: "clock")
                    .font(FCType.body)
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 120, alignment: .leading)
            }
            .padding(.leading, 24)
        }
    }

    private func failureDetails(for destination: String) -> InfoPopoverContent? {
        guard let result = transferResult(for: destination),
              let message = result.errorMessage,
              !message.isEmpty,
              !result.errors.isEmpty else {
            return nil
        }
        let limit = 8
        let normalized = result.errors.prefix(limit).map(normalizeFailureLine(_:))
        let extraCount = result.errors.count - normalized.count
        var notes = normalized
        if extraCount > 0 {
            notes.append("…and \(extraCount) more")
        }
        return InfoPopoverContent(
            title: "Failure details",
            description: message,
            notes: notes
        )
    }

    private func normalizeFailureLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(of: ": source=") {
            return String(trimmed[..<range.lowerBound])
        }
        if let space = trimmed.firstIndex(of: " ") {
            let suffix = trimmed[trimmed.index(after: space)...]
            return String(suffix)
        }
        return trimmed
    }

    private func progressValue(for destination: String, source: String) -> Double {
        if source.isEmpty {
            if let value = transferViewModel.destinationProgress[destination] {
                return min(max(0, value), 1)
            }
            if transferResult(for: destination)?.success == true {
                return 1
            }
            return 0
        }
        let value = transferViewModel.progressForPath(destination: destination, source: source)
        return min(max(0, value), 1)
    }

    private func progressPercentText(for destination: String, source: String) -> String? {
        let value = progressValue(for: destination, source: source)
        let percent = Int(round(value * 100))
        return "\(percent)%"
    }

    private func copyLabelText(for destination: String, source: String) -> String {
        let value = progressValue(for: destination, source: source)
        if value >= 1 {
            return "Copied"
        }

        if isActiveTransfer,
           let activeSource = transferViewModel.activeSource(for: destination),
           !source.isEmpty,
           activeSource == source,
           let live = transferViewModel.liveProgress(for: destination) {
            let total = max(live.filesTotal, 0)
            let completed = min(max(live.filesCompleted, 0), total)
            if total > 0, completed < total {
                let currentIndex = min(completed + 1, total)
                return "Copying \(currentIndex)/\(total)"
            }
            return "Copying \(completed)/\(total)"
        }

        if isActiveTransfer,
           !source.isEmpty,
           let activeSource = transferViewModel.activeSource(for: destination),
           activeSource != source {
            return "Waiting"
        }

        if transferResult(for: destination)?.success == true {
            return value >= 1 ? "Copied" : "Waiting"
        }
        return "Copying"
    }

    private func shouldShowVerificationRow(for destination: String, source: String, showProgress: Bool) -> Bool {
        guard isActiveTransfer else { return false }
        guard let activeSource = transferViewModel.activeSource(for: destination) else { return false }
        if !source.isEmpty && activeSource != source {
            return false
        }
        let liveHasStarted = transferViewModel.liveProgress(for: destination)?.verificationHasStarted ?? false
        let wantsVerificationRow = postVerifyEnabled || liveHasStarted
        guard wantsVerificationRow else { return false }
        return showProgress
    }

    private func verificationProgressValue(for destination: String, source: String, showProgress: Bool) -> Double {
        guard shouldShowVerificationRow(for: destination, source: source, showProgress: showProgress) else { return 0 }
        guard let live = transferViewModel.liveProgress(for: destination) else { return 0 }
        return min(max(0, live.verificationWeightedProgress), 1)
    }

    private func verificationPercentText(for destination: String, source: String, showProgress: Bool) -> String? {
        guard shouldShowVerificationRow(for: destination, source: source, showProgress: showProgress) else { return nil }
        guard let live = transferViewModel.liveProgress(for: destination) else { return nil }
        guard live.verificationHasStarted else { return nil }
        guard live.verificationBytesTotal > 0 || live.verificationFilesTotal > 0 else { return nil }
        let percent = Int(round(live.verificationWeightedProgress * 100))
        return "\(percent)%"
    }

    private func verificationLabelText(for destination: String, source: String) -> String {
        guard shouldShowVerificationRow(for: destination, source: source, showProgress: true),
              let live = transferViewModel.liveProgress(for: destination) else {
            return "Will verify"
        }
        if !live.verificationHasStarted {
            return "Will verify"
        }
        let total = max(live.verificationFilesTotal, 0)
        let completed = min(max(live.verificationFilesCompleted, 0), total)
        if !live.verificationIsActive && !live.copyingDone && completed < total {
            let waitingIndex = min(completed + 1, total)
            return "Waiting for \(waitingIndex)/\(total)"
        }
        let inProgress = (completed == 0 && live.verificationBytesCompleted > 0) ? 1 : 0
        let done = min(completed + inProgress, total)
        return "Verifying \(done)/\(total)"
    }

    private func statusIndicator(_ status: TransferViewModel.DestinationPresentation.Status) -> some View {
        switch status {
        case .pending:
            return AnyView(Image(systemName: "circle")
                .foregroundColor(Color(nsColor: .tertiaryLabelColor)))
        case .active:
            return AnyView(ProgressView().progressViewStyle(.circular).controlSize(.mini))
        case .done:
            return AnyView(Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(FilmCanTheme.brandGreen))
        case .failed:
            return AnyView(Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(FilmCanTheme.brandRed))
        case .paused:
            return AnyView(Image(systemName: "stop.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.orange))
        }
    }

    private func statusOrDriveIcon(
        status: TransferViewModel.DestinationPresentation.Status,
        systemIcon: String
    ) -> some View {
        if status == .pending {
            return AnyView(
                Image(systemName: systemIcon)
                    .foregroundColor(FilmCanTheme.textSecondary)
            )
        }
        return AnyView(statusIndicator(status))
    }

    private func progressTintColor(for status: TransferViewModel.DestinationPresentation.Status) -> Color {
        switch status {
        case .failed:
            return FilmCanTheme.brandRed
        case .paused:
            return .orange
        case .pending:
            return FilmCanTheme.textTertiary
        case .active, .done:
            return FilmCanTheme.brandGreen
        }
    }

    private struct ThickLinearProgressStyle: ProgressViewStyle {
        let height: CGFloat
        let fill: Color

        func makeBody(configuration: Configuration) -> some View {
            let value = configuration.fractionCompleted ?? 0
            return GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(Color(nsColor: .tertiaryLabelColor).opacity(0.35))
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(fill)
                        .frame(width: proxy.size.width * CGFloat(value))
                }
            }
            .frame(height: height)
        }
    }

    private func driveSummaries(for destinations: [String]) -> [DriveSummary] {
        PerfSignpost.region("destListSummaries") {
        var summaries: [String: DriveSummary] = [:]
        var order: [String] = []

        for path in destinations {
            // All metadata from DriveInfoCache (off-main). Cold miss returns a
            // placeholder with nil capacity ("—") until the populate fills it in;
            // never a synchronous disk stat on the main thread.
            let cached = DriveInfoCache.shared.info(for: path)
            let summary = cached.summary
            let volumeId = summary.id
            let name = summary.name
            let isExternal = summary.isExternal
            var total: Int64? = cached.totalBytes
            var available: Int64? = cached.liveAvailableBytes

            if isActiveTransfer,
               let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                total = snapshot.totalBytes
                available = snapshot.availableBytes
            }

            let isRoot = summary.isRoot
            let entry = DestinationPath(path: path, isRoot: isRoot)

            let connection = connectionStatus(for: path, summary: summary, cached: cached)

            if summaries[volumeId] == nil {
                order.append(volumeId)
                summaries[volumeId] = DriveSummary(
                    id: volumeId,
                    name: name,
                    availableBytes: available,
                    totalBytes: total,
                    paths: [entry],
                    isExternal: isExternal,
                    isConnected: connection.isConnected,
                    connectionMessage: connection.message
                )
            } else if var existing = summaries[volumeId] {
                existing.paths.append(entry)
                if existing.availableBytes == nil, let available {
                    existing.availableBytes = available
                }
                if existing.totalBytes == nil, let total {
                    existing.totalBytes = total
                }
                existing.isConnected = existing.isConnected || connection.isConnected
                if existing.connectionMessage.isEmpty {
                    existing.connectionMessage = connection.message
                }
                summaries[volumeId] = existing
            }
        }
        
        return order.compactMap { summaries[$0] }
        }
    }

    private func connectionStatus(for path: String, summary: DriveUtilities.Summary, cached: DriveInfoSnapshot) -> (isConnected: Bool, message: String) {
        if VolumesInUse.volumeRoot(for: path) != nil {
            if cached.rootExists {
                if summary.isReadOnly == true {
                    let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                    return (true, "Read-only\(formatLabel)")
                }
                return (true, "")
            }
            return (false, "Drive not connected")
        }
        if cached.pathExists {
            if summary.isReadOnly == true {
                let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                return (true, "Read-only\(formatLabel)")
            }
            return (true, "")
        }
        return (false, "Destination path not found")
    }

    private func removeDestination(_ path: String) {
        if let index = destinations.firstIndex(of: path) {
            destinations.remove(at: index)
        }
    }

    private func removeDriveGroup(_ driveGroupId: String) {
        destinations.removeAll { driveId(for: $0) == driveGroupId }
    }

    // Eject FIRST, then drop the config entry on success. Removing before the
    // device is gone lets the timer-based drive refresh re-add the still-mounted
    // card. If eject fails we keep the entry and surface why.
    private func removeAndEjectDriveGroup(_ driveGroupId: String, paths: [DestinationPath]) {
        guard let firstPath = paths.first?.path else { return }
        ejectVolume(for: firstPath) { removeDriveGroup(driveGroupId) }
    }

    // Plain eject: keep the entry in the backup so it shows as offline once the
    // card is gone (summary.isConnected flips false on the unmount notification).
    private func ejectDriveGroup(paths: [DestinationPath]) {
        guard let firstPath = paths.first?.path else { return }
        ejectVolume(for: firstPath)
    }

    private func removeAndEjectDestination(_ path: String) {
        ejectVolume(for: path) { removeDestination(path) }
    }

    private func ejectVolume(for path: String, onSuccess: (() -> Void)? = nil) {
        Task { @MainActor in
            switch await VolumeEjectFlow.eject(path: path, warnIfUnsealed: false) {
            case .ejected: onSuccess?()
            case .cancelled: break
            case .failed(let message): ejectErrorMessage = message
            }
        }
    }

    private func handleDriveDrop(providers: [NSItemProvider], targetDriveId: String) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, text.hasPrefix("drive:") else { return }
                    let fromId = String(text.dropFirst("drive:".count))
                    DispatchQueue.main.async {
                        moveDriveGroup(fromId: fromId, toId: targetDriveId)
                    }
                }
                return true
            }
        }
        return false
    }

    private struct DriveDropDelegate: DropDelegate {
        let targetId: String
        @Binding var draggingId: String?
        let moveAction: (String, String) -> Void

        func dropEntered(info: DropInfo) {
            guard let draggingId, draggingId != targetId else { return }
            moveAction(draggingId, targetId)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingId = nil
            return true
        }

        func dropExited(info: DropInfo) {
            // no-op
        }
    }

    private struct PathDropDelegate: DropDelegate {
        let targetPath: String
        @Binding var draggingPath: String?
        let moveAction: (String, String) -> Void

        func dropEntered(info: DropInfo) {
            guard let draggingPath, draggingPath != targetPath else { return }
            moveAction(draggingPath, targetPath)
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            draggingPath = nil
            return true
        }
    }

    private func handlePathDrop(providers: [NSItemProvider], targetPath: String) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                    guard let text = object as? String, text.hasPrefix("path:") else { return }
                    let fromPath = String(text.dropFirst("path:".count))
                    DispatchQueue.main.async {
                        movePath(fromPath: fromPath, toPath: targetPath)
                    }
                }
                return true
            }
        }
        return false
    }

    private func moveDriveGroup(fromId: String, toId: String) {
        guard fromId != toId else { return }
        let idsByPath = destinations.map { driveId(for: $0) }
        let driveOrder = idsByPath.reduce(into: [String]()) { order, id in
            if order.last != id {
                order.append(id)
            }
        }
        let fromIndex = driveOrder.firstIndex(of: fromId) ?? 0
        let toIndex = driveOrder.firstIndex(of: toId) ?? 0
        let insertAfter = fromIndex < toIndex

        let fromPaths = zip(destinations, idsByPath).filter { $0.1 == fromId }.map { $0.0 }
        var remaining = zip(destinations, idsByPath).filter { $0.1 != fromId }.map { $0.0 }
        if insertAfter {
            let lastIndex = remaining.lastIndex { driveId(for: $0) == toId } ?? (remaining.count - 1)
            let insertIndex = min(lastIndex + 1, remaining.count)
            remaining.insert(contentsOf: fromPaths, at: insertIndex)
        } else {
            let firstIndex = remaining.firstIndex { driveId(for: $0) == toId } ?? remaining.count
            remaining.insert(contentsOf: fromPaths, at: firstIndex)
        }
        destinations = remaining
    }

    private func movePath(fromPath: String, toPath: String) {
        guard fromPath != toPath,
              let fromIndex = destinations.firstIndex(of: fromPath),
              let toIndex = destinations.firstIndex(of: toPath) else { return }
        let fromDrive = driveId(for: fromPath)
        let toDrive = driveId(for: toPath)
        guard fromDrive == toDrive else { return }
        var updated = destinations
        let item = updated.remove(at: fromIndex)
        let insertIndex = min(toIndex, updated.count)
        updated.insert(item, at: insertIndex)
        destinations = updated
    }

    private func driveId(for path: String) -> String {
        DriveUtilities.driveId(for: path)
    }

    private func selectDestination(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if index < destinations.count {
                destinations[index] = url.path
            }
        }
    }
    
    private func addDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !destinations.contains(url.path) {
                destinations.append(url.path)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                           isDir.boolValue,
                           !destinations.contains(url.path) {
                            destinations.append(url.path)
                        }
                    }
                }
            }
        }
        return true
    }
}

private struct DriveSummary: Identifiable {
    let id: String
    let name: String
    var availableBytes: Int64?
    var totalBytes: Int64?
    var paths: [DestinationPath]
    let isExternal: Bool
    var isConnected: Bool
    var connectionMessage: String
}

private struct DestinationPath: Identifiable {
    let id: String
    let path: String
    let isRoot: Bool

    init(path: String, isRoot: Bool) {
        self.path = path
        self.isRoot = isRoot
        self.id = path
    }
}
