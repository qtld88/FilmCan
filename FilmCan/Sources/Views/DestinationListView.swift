import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DestinationListView: View {
    @Binding var destinations: [String]
    @ObservedObject var transferViewModel: TransferViewModel
    @ObservedObject var progress: TransferProgress
    var refreshToken: Int = 0
    @State private var isDropTargeted: Bool = false
    @State private var dragPayload: String? = nil
    @State private var draggingDriveId: String? = nil
    @State private var draggingPath: String? = nil
    @State private var knownDestinations: Set<String> = []
    var showsTitle: Bool = true
    var headerView: AnyView? = nil
    var footerView: AnyView? = nil
    var isTourHighlighted: Bool = false
    var requiredBytes: Int64 = 0
    var organizationPreset: OrganizationPreset? = nil
    var sourcePaths: [String] = []
    var copyFolderContents: Bool = true
    var configId: UUID
    var postVerifyEnabled: Bool = false
    var fulfilledDestinations: Set<String> = []
    private let previewDate = Date()
    private var isActiveTransfer: Bool {
        transferViewModel.activeConfigId == configId
    }
    
    var body: some View {
        let _ = refreshToken
        VStack(alignment: .leading, spacing: 8) {
            if showsTitle {
                Text("Save To")
                    .font(FilmCanFont.label(12))
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

                if isActiveTransfer && transferViewModel.isTransferring {
                    transferControls
                }
                
                // Add button (always visible)
                if !destinations.isEmpty {
                    Button(action: addDestination) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(FilmCanTheme.brandYellow)
                            Text("Add another destination")
                                .font(FilmCanFont.body(12))
                        }
                    }
                    .buttonStyle(.borderless)
                }
                
                if let footerView {
                    footerView
                }
            }
            .padding(12)
            .background(FilmCanTheme.panel)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDropTargeted || isTourHighlighted ? FilmCanTheme.brandYellow : FilmCanTheme.cardStrokeStrong,
                        style: StrokeStyle(
                            lineWidth: isDropTargeted || isTourHighlighted ? 2 : 1,
                            dash: isDropTargeted ? [6, 4] : []
                        )
                    )
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
                    .font(FilmCanFont.label(16))
                    .foregroundColor(FilmCanTheme.textPrimary)
                Text("or")
                    .font(FilmCanFont.body(11))
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
        let indexed = Array(summaries.enumerated())
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(indexed, id: \.element.id) { index, summary in
                let driveRequiredBytes = requiredBytes
                let backupStoredOnDrive = (!isActiveTransfer || !transferViewModel.isTransferring)
                    ? driveHasStoredBackup(
                        summary: summary,
                        fulfilledDestinations: fulfilled
                    )
                    : false
                let summaryLine = summary.isConnected
                    ? destinationSummaryLine(
                        summary: summary,
                        requiredBytes: driveRequiredBytes,
                        backupStoredOnDrive: backupStoredOnDrive
                    )
                    : nil
                HStack(alignment: .center, spacing: 12) {
                    Text("\(index + 1)")
                        .font(FilmCanFont.label(11))
                        .foregroundColor(FilmCanTheme.textSecondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: DriveUtilities.driveIconName(isExternal: summary.isExternal, style: .filled))
                                .foregroundColor(FilmCanTheme.textSecondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.name)
                                    .font(FilmCanFont.body(11))
                                    .foregroundColor(FilmCanTheme.textSecondary)
                                if let summaryLine {
                                    Text(summaryLine)
                                        .font(FilmCanFont.body(10))
                                        .foregroundColor(FilmCanTheme.textSecondary)
                                }
                            }
                            Spacer()
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
                                    .font(FilmCanFont.body(10))
                                    .foregroundColor(FilmCanTheme.brandRed)
                            }
                            .padding(.leading, 26)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FilmCanTheme.card)
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(FilmCanTheme.cardStroke, lineWidth: 1)
                )
                .cornerRadius(8)
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
        let showProgress = presentation.shouldShowInfo
        let status = presentation.status
        let progressLabelWidth: CGFloat = 120
        let percentLabelWidth: CGFloat = 42
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                statusOrDriveIcon(status: status, systemIcon: icon)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text((destination.path as NSString).lastPathComponent)
                        .font(FilmCanFont.label(12))
                        .foregroundColor(FilmCanTheme.textPrimary)
                        .lineLimit(1)
                    ForEach(displayPaths) { item in
                        let label = item.source.isEmpty
                            ? item.path
                            : "\(sourceLabel(item.source)) -> \(item.path)"
                        VStack(alignment: .leading, spacing: 4) {
                            Text(label)
                                .font(FilmCanFont.body(10))
                                .foregroundColor(FilmCanTheme.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if showProgress {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(copyLabelText(for: destination.path, source: item.source))
                                            .font(FilmCanFont.label(10))
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
                                            .font(FilmCanFont.label(10))
                                            .foregroundColor(FilmCanTheme.textSecondary)
                                            .frame(width: percentLabelWidth, alignment: .trailing)
                                            .opacity(percentText == nil ? 0 : 1)
                                    }

                                    if shouldShowVerificationRow(for: destination.path, showProgress: showProgress) {
                                        HStack(spacing: 8) {
                                            Text(verificationLabelText(for: destination.path))
                                                .font(FilmCanFont.label(10))
                                                .foregroundColor(FilmCanTheme.textSecondary)
                                                .lineLimit(1)
                                                .frame(width: progressLabelWidth, alignment: .leading)
                                            ProgressView(value: verificationProgressValue(
                                                for: destination.path,
                                                showProgress: showProgress
                                            ))
                                                .progressViewStyle(ThickLinearProgressStyle(
                                                    height: 6,
                                                    fill: FilmCanTheme.brandBlue
                                                ))
                                                .frame(maxWidth: .infinity)

                                            let verifyPercent = verificationPercentText(
                                                for: destination.path,
                                                showProgress: showProgress
                                            )
                                            Text(verifyPercent ?? "")
                                                .font(FilmCanFont.label(10))
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

            if showProgress {
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

    private func sourceLabel(_ source: String) -> String {
        (source as NSString).lastPathComponent
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
                date: previewDate
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
        HStack(spacing: 12) {
            Button(transferViewModel.allDestinations.count > 1 ? "Stop Backups" : "Stop Backup") {
                transferViewModel.cancelAll()
            }
            .buttonStyle(.bordered)
            .tint(.red)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func capacityBar(
        requiredBytes: Int64,
        available: Int64?,
        total: Int64?,
        driveName: String,
        backupStoredOnDrive: Bool = false
    ) -> some View {
        let info = capacityInfo(
            requiredBytes: requiredBytes,
            available: available,
            total: total,
            treatBackupAsUsed: backupStoredOnDrive
        )
        return VStack(alignment: .leading, spacing: 6) {
            capacityBarVisualization(info: info, requiredBytes: requiredBytes)
            if info.ratioToAvailable.map({ $0 > 1.0 }) == true {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Not enough space!")
                        .font(FilmCanFont.label(11))
                        .foregroundColor(.red)
                }
            }
            capacityLegend(info: info, treatBackupAsUsed: backupStoredOnDrive)
        }
    }

    private struct CapacityInfo {
        let ratioToAvailable: Double?
        let hasTotal: Bool
        let usedRatio: Double
        let backupRatio: Double
        let freeRatio: Double
        let usedPercent: Int
        let backupPercent: Int
        let freePercent: Int
        let usedColor: Color
        let freeColor: Color
        let backupSegmentColor: Color
    }

    private func capacityInfo(
        requiredBytes: Int64,
        available: Int64?,
        total: Int64?,
        treatBackupAsUsed: Bool = false
    ) -> CapacityInfo {
        let totalBytes = total ?? 0
        let hasTotal = totalBytes > 0 && available != nil
        let availableBytes = available ?? 0
        let usedBytes = max(totalBytes - availableBytes, 0)
        let backupBytes: Int64
        let usedOtherBytes: Int64
        let freeAfterBytes: Int64
        let effectiveRequiredForSpace: Int64
        if treatBackupAsUsed {
            backupBytes = min(requiredBytes, usedBytes)
            usedOtherBytes = max(usedBytes - backupBytes, 0)
            freeAfterBytes = max(totalBytes - usedBytes, 0)
            effectiveRequiredForSpace = 0
        } else {
            backupBytes = min(requiredBytes, max(availableBytes, 0))
            usedOtherBytes = usedBytes
            freeAfterBytes = max(totalBytes - usedBytes - backupBytes, 0)
            effectiveRequiredForSpace = requiredBytes
        }
        let ratioToAvailable = available.map { availableBytes in
            if effectiveRequiredForSpace <= 0 {
                return 0.0
            }
            if availableBytes <= 0 {
                return Double.infinity
            }
            return Double(effectiveRequiredForSpace) / Double(availableBytes)
        }
        let usedRatio = hasTotal ? Double(usedOtherBytes) / Double(totalBytes) : 0
        let backupRatio = hasTotal ? Double(backupBytes) / Double(totalBytes) : 0
        let freeRatio = hasTotal ? Double(freeAfterBytes) / Double(totalBytes) : 0
        let usedPercent = Int(round(usedRatio * 100))
        let backupPercent = Int(round(backupRatio * 100))
        let freePercent = max(0, 100 - usedPercent - backupPercent)
        let usedColor = Color.gray.opacity(0.35)
        let freeColor = Color.gray.opacity(0.75)
        let backupSegmentColor: Color
        if treatBackupAsUsed {
            backupSegmentColor = FilmCanTheme.brandGreen
        } else {
            if let ratio = ratioToAvailable, ratio > 1.0 {
                backupSegmentColor = .red
            } else if backupPercent > 80 {
                backupSegmentColor = .red
            } else if backupPercent > 60 {
                backupSegmentColor = .orange
            } else {
                backupSegmentColor = FilmCanTheme.brandGreen
            }
        }
        return CapacityInfo(
            ratioToAvailable: ratioToAvailable,
            hasTotal: hasTotal,
            usedRatio: usedRatio,
            backupRatio: backupRatio,
            freeRatio: freeRatio,
            usedPercent: usedPercent,
            backupPercent: backupPercent,
            freePercent: freePercent,
            usedColor: usedColor,
            freeColor: freeColor,
            backupSegmentColor: backupSegmentColor
        )
    }

    private func destinationSummaryLine(
        summary: DriveSummary,
        requiredBytes: Int64,
        backupStoredOnDrive: Bool
    ) -> String? {
        let info = capacityInfo(
            requiredBytes: requiredBytes,
            available: summary.availableBytes,
            total: summary.totalBytes,
            treatBackupAsUsed: backupStoredOnDrive
        )
        let freeText = info.freePercent == 0 ? "<1%" : "\(info.freePercent)%"
        let backupText = info.backupPercent == 0 ? "<1%" : "\(info.backupPercent)%"
        let usedText = info.usedPercent == 0 ? "<1%" : "\(info.usedPercent)%"
        let backupLabel = backupStoredOnDrive ? "already there" : "backup"
        return "\(freeText) free · \(backupText) \(backupLabel) · \(usedText) full"
    }

    private func capacityBarVisualization(info: CapacityInfo, requiredBytes: Int64) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                if info.hasTotal {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(info.freeColor)
                            .frame(width: geo.size.width * info.freeRatio)
                        Rectangle()
                            .fill(info.backupSegmentColor.opacity(0.6))
                            .frame(width: geo.size.width * info.backupRatio)
                        Rectangle()
                            .fill(info.usedColor)
                            .frame(width: geo.size.width * info.usedRatio)
                    }
                    .animation(.easeInOut(duration: 0.5), value: requiredBytes)
                } else {
                    Rectangle()
                        .fill(info.backupSegmentColor.opacity(0.6))
                        .frame(width: geo.size.width * min(1.0, info.ratioToAvailable ?? 0))
                        .animation(.easeInOut(duration: 0.5), value: requiredBytes)
                }
            }
            .cornerRadius(4)
        }
        .frame(height: 12)
    }

    private func capacityLegend(info: CapacityInfo, treatBackupAsUsed: Bool = false) -> some View {
        let backupLabel = treatBackupAsUsed ? "already there" : "for backup"
        return HStack(spacing: 12) {
            legendDot(color: info.freeColor)
            Text("\(info.freePercent)% will remain free")
                .font(FilmCanFont.body(10))
                .foregroundColor(FilmCanTheme.textSecondary)
            legendDot(color: info.backupSegmentColor.opacity(0.6))
            Text("\(info.backupPercent)% \(backupLabel)")
                .font(FilmCanFont.body(10))
                .foregroundColor(FilmCanTheme.textSecondary)
            legendDot(color: info.usedColor)
            Text("\(info.usedPercent)% already full")
                .font(FilmCanFont.body(10))
                .foregroundColor(FilmCanTheme.textSecondary)
        }
    }
    
    private func legendDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private func fulfilledDestinationsForCurrentConfig() -> Set<String> {
        var fulfilled = fulfilledDestinations
        guard transferViewModel.activeConfigId == configId else { return fulfilled }
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
                        .font(FilmCanFont.label(14))
                        .foregroundColor(FilmCanTheme.brandRed)
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
                        .font(FilmCanFont.body(12))
                        .foregroundColor(FilmCanTheme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 16) {
                Label(presentation.progressText, systemImage: "externaldrive")
                    .font(FilmCanFont.body(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 160, alignment: .leading)
                Label(presentation.speedText, systemImage: "speedometer")
                    .font(FilmCanFont.body(12))
                    .foregroundColor(FilmCanTheme.textSecondary)
                    .frame(width: 140, alignment: .leading)
                Label(presentation.etaText, systemImage: "clock")
                    .font(FilmCanFont.body(12))
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
        if transferViewModel.isTransferring && progress.totalBytes <= 0 {
            return nil
        }
        let value = progressValue(for: destination, source: source)
        let percent = Int(round(value * 100))
        return "\(percent)%"
    }

    private func copyLabelText(for destination: String, source: String) -> String {
        if destination == transferViewModel.currentDestination, transferViewModel.isTransferring {
            let total = max(progress.filesTotal, 0)
            let completed = min(max(progress.filesCompleted, 0), total)
            if total > 0, completed < total {
                let currentIndex = min(completed + 1, total)
                return "Copying \(currentIndex)/\(total)"
            }
            return "Copying \(completed)/\(total)"
        }
        if transferResult(for: destination)?.success == true {
            return "Copied"
        }
        return "Copying"
    }

    private func shouldShowVerificationRow(for destination: String, showProgress: Bool) -> Bool {
        guard destination == transferViewModel.currentDestination else { return false }
        let wantsVerificationRow = postVerifyEnabled || progress.verificationHasStarted
        guard wantsVerificationRow else { return false }
        return showProgress
    }

    private func verificationProgressValue(for destination: String, showProgress: Bool) -> Double {
        guard shouldShowVerificationRow(for: destination, showProgress: showProgress) else { return 0 }
        return min(max(0, progress.verificationWeightedProgress), 1)
    }

    private func verificationPercentText(for destination: String, showProgress: Bool) -> String? {
        guard shouldShowVerificationRow(for: destination, showProgress: showProgress) else { return nil }
        guard progress.verificationHasStarted else { return nil }
        guard progress.verificationBytesTotal > 0 || progress.verificationFilesTotal > 0 else { return nil }
        let percent = Int(round(progress.verificationWeightedProgress * 100))
        return "\(percent)%"
    }

    private func verificationLabelText(for destination: String) -> String {
        if !progress.verificationHasStarted {
            return "Will verify"
        }
        let total = max(progress.verificationFilesTotal, 0)
        let completed = min(max(progress.verificationFilesCompleted, 0), total)
        if !progress.verificationIsActive && !progress.copyingDone && completed < total {
            let waitingIndex = min(completed + 1, total)
            return "Waiting for \(waitingIndex)/\(total)"
        }
        let inProgress = (completed == 0 && progress.verificationBytesCompleted > 0) ? 1 : 0
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
                .foregroundColor(.red))
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
        var summaries: [String: DriveSummary] = [:]
        var order: [String] = []

        for path in destinations {
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [
                .volumeUUIDStringKey,
                .volumeNameKey,
                .volumeIsInternalKey,
                .volumeIsRemovableKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            let summary = DriveUtilities.summary(for: path)
            let volumeId = summary.id
            let name = summary.name
            let isExternal = summary.isExternal
            var total: Int64? = nil
            var available: Int64? = nil
            if let values,
               let cap = values.volumeTotalCapacity,
               cap > 0 {
                total = Int64(cap)
            } else if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
                      let cap = attrs[.systemSize] as? Int64,
                      cap > 0 {
                total = cap
            }
            if let values,
               let cap = values.volumeAvailableCapacityForImportantUsage,
               cap > 0 {
                available = Int64(cap)
            } else if let values,
                      let cap = values.volumeAvailableCapacity,
                      cap > 0 {
                available = Int64(cap)
            } else if let cap = availableSpace(at: path) {
                available = cap
            }

            if isActiveTransfer,
               transferViewModel.isTransferring,
               let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                total = snapshot.totalBytes
                available = snapshot.availableBytes
            }
            
            let isRoot = summary.isRoot
            let entry = DestinationPath(path: path, isRoot: isRoot)
            
            let connection = connectionStatus(for: path, summary: summary)

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

    private func connectionStatus(for path: String, summary: DriveUtilities.Summary) -> (isConnected: Bool, message: String) {
        if let root = volumeRootPath(for: path) {
            if FileManager.default.fileExists(atPath: root) {
                if summary.isReadOnly == true {
                    let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                    return (true, "Read-only\(formatLabel)")
                }
                return (true, "")
            }
            return (false, "Drive not connected")
        }
        if FileManager.default.fileExists(atPath: path) {
            if summary.isReadOnly == true {
                let formatLabel = summary.formatLabel.map { " (\($0))" } ?? ""
                return (true, "Read-only\(formatLabel)")
            }
            return (true, "")
        }
        return (false, "Destination path not found")
    }

    private func volumeRootPath(for path: String) -> String? {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count >= 3, components[1] == "Volumes" else { return nil }
        return "/Volumes/\(components[2])"
    }

    private func removeDestination(_ path: String) {
        if let index = destinations.firstIndex(of: path) {
            destinations.remove(at: index)
        }
    }

    private func removeDriveGroup(_ driveGroupId: String) {
        destinations.removeAll { driveId(for: $0) == driveGroupId }
    }

    private func removeAndEjectDriveGroup(_ driveGroupId: String, paths: [DestinationPath]) {
        removeDriveGroup(driveGroupId)
        ejectDriveGroup(paths: paths)
    }

    private func ejectDriveGroup(paths: [DestinationPath]) {
        guard let firstPath = paths.first?.path else { return }
        ejectVolume(for: firstPath)
    }

    private func removeAndEjectDestination(_ path: String) {
        removeDestination(path)
        ejectVolume(for: path)
    }

    private func ejectVolume(for path: String) {
        guard let root = volumeRootPath(for: path) else { return }
        let url = URL(fileURLWithPath: root)
        Task {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: url)
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

    private func availableSpace(at path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let cap = values.volumeAvailableCapacityForImportantUsage,
           cap > 0 {
            return Int64(cap)
        }
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
           let cap = values.volumeAvailableCapacity,
           cap > 0 {
            return Int64(cap)
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let cap = attrs[.systemFreeSize] as? Int64,
           cap > 0 {
            return cap
        }
        return nil
    }
    
    private func selectDestination(at index: Int) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
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
