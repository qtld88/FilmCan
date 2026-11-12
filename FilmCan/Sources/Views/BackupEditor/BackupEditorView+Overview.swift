import SwiftUI
import Foundation

extension BackupEditorView {
    func overviewSection(isWide: Bool) -> some View {
        let facts = mainScreenFacts()
        return VStack(alignment: .leading, spacing: 16) {
            nameRow(runSubtitle: facts.runSubtitle)

            if let summary = facts.summary {
                BackupSummaryRow(summary: summary)
            }

            if isWide {
                overviewRowLayout
            } else {
                overviewColumnLayout
            }

            SpeedAdviceSection(
                viewModel: viewModel,
                transferViewModel: transferViewModel,
                bytesToCopy: includedRequiredBytes,
                refreshToken: driveRefreshCounter
            )
        }
    }

    // MARK: - Summary line and Run subtitle (logic in `MainScreenSummary.swift`)

    private var summarySources: [FolderTreeBuilder.Source] {
        viewModel.includedSourcePaths.map { path in
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            return FolderTreeBuilder.Source(
                path: path, isDirectory: isDir.boolValue, kind: viewModel.mediaKind(for: path),
                rollName: isDir.boolValue ? viewModel.rollNameOverride(for: path) : nil)
        }
    }

    /// Same options as the Save To folder preview, so the summary names the same folders.
    private var summaryOptions: FolderTreeBuilder.Options {
        var o = FolderTreeBuilder.Options()
        let preset = previewOrganizationPreset
        o.preset = preset
        o.organizationActive = preset.map {
            $0.useFolderTemplate && !FolderTreeBuilder.isBlank($0.folderTemplate)
        } ?? false
        o.copyContents = viewModel.copyFolderContents
        o.date = TodayClock.shared.today
        o.metadata = previewShootMetadata
        o.mediaIndexPreset = preset
        return o
    }

    private var summaryDestinations: [String] { viewModel.config.includedDestinationPaths }

    /// Summary line + Run subtitle, resolved in one pass per render so the sources and
    /// their destination paths are looked up once (the folder preview already stats them).
    func mainScreenFacts() -> (summary: BackupSummary?, runSubtitle: String) {
        let isRunning = transferViewModel.isTransferActive(for: viewModel.config.id)
        // A running copy re-renders this view on every progress tick: keep the line
        // resolved before the run instead of touching the disks again each time.
        if isRunning, let frozen = summaryFreeze.summary {
            return (frozen, RunSubtitle.text(sourceCount: 1, driveCount: 1,
                                             newFolderCount: 0, isRunning: true))
        }
        let sources = summarySources
        let destinations = summaryDestinations
        guard !sources.isEmpty else {
            summaryFreeze.summary = nil
            return (nil, RunSubtitle.text(sourceCount: 0, driveCount: destinations.count,
                                          newFolderCount: 0, isRunning: isRunning))
        }
        let options = summaryOptions
        // Without a drive yet, resolve against a placeholder root: the folders are the same.
        let root = destinations.first ?? "/Volumes/Drive"
        let counts = sources.compactMap { previewInfo.sourceItemCounts[$0.path] }
        let summary = BackupSummary.make(
            relativePaths: FolderTreeBuilder.relativePaths(for: root, sources: sources, options: options),
            totalBytes: previewInfo.totalBytes,
            itemCount: counts.count == sources.count ? counts.reduce(0, +) : nil,
            driveCount: destinations.count,
            isLoading: previewInfo.isLoading)
        summaryFreeze.summary = summary
        // Nothing to count while a copy runs: the subtitle then only says so.
        let newFolders = isRunning ? 0 : destinations.reduce(0) { total, destination in
            total + RunSubtitle.newFolderCount(
                in: FolderTreeBuilder.lines(for: destination, sources: sources, options: options))
        }
        return (summary, RunSubtitle.text(
            sourceCount: sources.count, driveCount: destinations.count,
            newFolderCount: newFolders, isRunning: isRunning))
    }

    private var overviewRowLayout: some View {
        let flow = sourceDriveNodesAndTotal()
        return HStack(alignment: .top, spacing: 12) {
            SourceListView(
                sources: Binding(
                    get: { viewModel.sourcePaths },
                    set: { viewModel.sourcePaths = $0 }
                ),
                refreshToken: driveRefreshCounter,
                sourceSizes: previewInfo.sourceSizes,
                sourceItemCounts: previewInfo.sourceItemCounts,
                isLoading: previewInfo.isLoading,
                isTourHighlighted: appState.activeTourTargetId == "sourcePanel",
                showsTitle: false,
                headerView: AnyView(
                    FCCardHeader(title: "COPY FROM", dot: FilmCanTheme.brandYellow)
                ),
                footerView: sourcePreviewFooter,
                mediaKind: { viewModel.mediaKind(for: $0) },
                setMediaKind: { viewModel.setMediaKind($1, for: $0) },
                genericRollName: { path in
                    guard viewModel.isGenericSource(path) else { return nil }
                    let override = viewModel.rollNameOverride(for: path)
                    return viewModel.copyFolderContents && override == nil ? nil : (override ?? "")
                },
                setGenericRollName: { viewModel.setRollNameOverride($1, for: $0) },
                genericCardWarning: viewModel.genericCardWarning,
                resolveGenericCardWarning: { accept in
                    if accept { viewModel.acceptGenericCardWarning() } else { viewModel.dismissGenericCardWarning() }
                },
                cardSignature: { viewModel.detectedCard(for: $0) },
                rollNamePreview: { viewModel.rollNamePreview(for: $0) },
                setCardRole: { viewModel.setCardRole($1, for: $0) },
                isIncluded: { viewModel.isSourceIncluded($0) },
                setIncluded: { viewModel.setSourcesIncluded($0, $1) },
                isSelectionLocked: transferViewModel.isTransferActive(for: viewModel.config.id)
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("sourcePanel")
            
            Color.clear
                .frame(width: 60)
                .anchorPreference(key: DriveAnchorPreferenceKey.self, value: .bounds) { bounds in
                    DriveAnchorData(flowFrame: bounds)
                }
            
            let verifyEnabled = viewModel.engineOptions.customVerifyEnabled

            DestinationListView(
                destinations: Binding(
                    get: { viewModel.destinations },
                    set: { viewModel.destinations = $0 }
                ),
                transferViewModel: transferViewModel,
                progress: transferViewModel.progress,
                refreshToken: driveRefreshCounter,
                showsTitle: false,
                headerView: AnyView(
                    FCCardHeader(title: "SAVE TO", dot: FilmCanTheme.brandYellow)
                ),
                footerView: nil,
                isTourHighlighted: appState.activeTourTargetId == "destinationPanel",
                requiredBytes: includedRequiredBytes,
                organizationPreset: previewOrganizationPreset,
                sourcePaths: viewModel.includedSourcePaths,
                mediaKind: { viewModel.mediaKind(for: $0) },
                rollName: { viewModel.rollNameOverride(for: $0) },
                shootMetadata: previewShootMetadata,
                copyFolderContents: viewModel.copyFolderContents,
                configId: viewModel.config.id,
                postVerifyEnabled: verifyEnabled,
                fulfilledDestinations: fulfilledDestinationsForCurrentConfig(),
                isIncluded: { viewModel.isDestinationIncluded($0) },
                setIncluded: { viewModel.setDestinationsIncluded($0, $1) }
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("destinationPanel")
        }
        .tourAnchor("flowArea")
        .coordinateSpace(name: "FlowSpace")
        .overlayPreferenceValue(DriveAnchorPreferenceKey.self) { anchors in
            GeometryReader { geo in
                if let flowFrame = anchors.flowFrame {
                    let frame = geo[flowFrame]
                    let sourceCenters = anchors.sources.mapValues { geo[$0].midY - frame.minY }
                    let destinationCenters = anchors.destinations.mapValues { geo[$0].midY - frame.minY }
                    let fulfilled = fulfilledDestinationsForCurrentConfig()
                    let storedDriveIds = transferViewModel.isTransferActive(for: viewModel.config.id)
                        ? []
                        : storedDriveIds(from: fulfilled)
                    FlowLinkView(
                        sources: flow.nodes,
                        destinations: destinationDriveNodes(),
                        totalBytes: flow.totalBytes,
                        destinationStoredDrives: storedDriveIds,
                        sourceCenters: sourceCenters,
                        destinationCenters: destinationCenters
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
    }

    private var overviewColumnLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            SourceListView(
                sources: Binding(
                    get: { viewModel.sourcePaths },
                    set: { viewModel.sourcePaths = $0 }
                ),
                refreshToken: driveRefreshCounter,
                sourceSizes: previewInfo.sourceSizes,
                sourceItemCounts: previewInfo.sourceItemCounts,
                isLoading: previewInfo.isLoading,
                isTourHighlighted: appState.activeTourTargetId == "sourcePanel",
                showsTitle: false,
                headerView: AnyView(
                    FCCardHeader(title: "COPY FROM", dot: FilmCanTheme.brandYellow)
                ),
                footerView: sourcePreviewFooter,
                mediaKind: { viewModel.mediaKind(for: $0) },
                setMediaKind: { viewModel.setMediaKind($1, for: $0) },
                genericRollName: { path in
                    guard viewModel.isGenericSource(path) else { return nil }
                    let override = viewModel.rollNameOverride(for: path)
                    return viewModel.copyFolderContents && override == nil ? nil : (override ?? "")
                },
                setGenericRollName: { viewModel.setRollNameOverride($1, for: $0) },
                genericCardWarning: viewModel.genericCardWarning,
                resolveGenericCardWarning: { accept in
                    if accept { viewModel.acceptGenericCardWarning() } else { viewModel.dismissGenericCardWarning() }
                },
                cardSignature: { viewModel.detectedCard(for: $0) },
                rollNamePreview: { viewModel.rollNamePreview(for: $0) },
                setCardRole: { viewModel.setCardRole($1, for: $0) },
                isIncluded: { viewModel.isSourceIncluded($0) },
                setIncluded: { viewModel.setSourcesIncluded($0, $1) },
                isSelectionLocked: transferViewModel.isTransferActive(for: viewModel.config.id)
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("sourcePanel")
            
            HStack {
                Spacer()
                Image(systemName: "arrow.down")
                    .font(.title3)
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            let verifyEnabled = viewModel.engineOptions.customVerifyEnabled

            DestinationListView(
                destinations: Binding(
                    get: { viewModel.destinations },
                    set: { viewModel.destinations = $0 }
                ),
                transferViewModel: transferViewModel,
                progress: transferViewModel.progress,
                refreshToken: driveRefreshCounter,
                showsTitle: false,
                headerView: AnyView(
                    FCCardHeader(title: "SAVE TO", dot: FilmCanTheme.brandYellow)
                ),
                footerView: nil,
                isTourHighlighted: appState.activeTourTargetId == "destinationPanel",
                requiredBytes: includedRequiredBytes,
                organizationPreset: previewOrganizationPreset,
                sourcePaths: viewModel.includedSourcePaths,
                mediaKind: { viewModel.mediaKind(for: $0) },
                rollName: { viewModel.rollNameOverride(for: $0) },
                shootMetadata: previewShootMetadata,
                copyFolderContents: viewModel.copyFolderContents,
                configId: viewModel.config.id,
                postVerifyEnabled: verifyEnabled,
                fulfilledDestinations: fulfilledDestinationsForCurrentConfig(),
                isIncluded: { viewModel.isDestinationIncluded($0) },
                setIncluded: { viewModel.setDestinationsIncluded($0, $1) }
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("destinationPanel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bytes the checked sources need on each checked destination.
    private var includedRequiredBytes: Int64 { previewInfo.totalBytes }

    /// Per-card sizes cover every listed source; the totals only the checked ones.
    func refreshPreview(bypassCache: Bool = false) {
        let sources = viewModel.sourcePaths
        let included = viewModel.includedSourcePaths
        previewInfo.isLoading = true

        Task.detached(priority: .utility) {
            var (bytes, files, folders, sizes, itemCounts) = PreviewCalculator.calculateTotalsAndSizes(for: sources, bypassCache: bypassCache)
            if included.count != sources.count {
                (bytes, files, folders, _, _) = PreviewCalculator.calculateTotalsAndSizes(for: included)
            }
            await MainActor.run {
                previewInfo.totalBytes = bytes
                previewInfo.fileCount = files
                previewInfo.folderCount = folders
                previewInfo.sourceSizes = sizes
                previewInfo.sourceItemCounts = itemCounts
                previewInfo.isLoading = false
            }
        }
    }

    private func sourceDriveNodesAndTotal() -> (nodes: [FlowLinkView.FlowNode], totalBytes: Int64) {
        PerfSignpost.region("sourceDriveNodes") {
            var sizes: [String: Int64] = [:]
            var names: [String: String] = [:]
            var totals: [String: Int64] = [:]
            var available: [String: Int64] = [:]
            var order: [String] = []
            for source in viewModel.includedSourcePaths {
                let cached = DriveInfoCache.shared.info(for: source)
                let summary = cached.summary
                if sizes[summary.id] == nil {
                    order.append(summary.id)
                    sizes[summary.id] = 0
                    names[summary.id] = summary.name
                    if transferViewModel.isTransferActive(for: viewModel.config.id),
                       let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                        totals[summary.id] = snapshot.totalBytes ?? 0
                        available[summary.id] = snapshot.availableBytes ?? 0
                    } else {
                        totals[summary.id] = cached.totalBytes ?? 0
                        available[summary.id] = cached.liveAvailableBytes ?? 0
                    }
                }
                // Green "to copy" amount must reflect the actual enumerated content
                // (excludes Trash, other files on the volume), not the whole-drive
                // used space. Fall back to drive-used only if content hasn't been
                // measured yet (e.g. preview still loading on a root volume).
                let contentSize = previewInfo.sourceSizes[source] ?? 0
                if contentSize > 0 {
                    sizes[summary.id] = (sizes[summary.id] ?? 0) + contentSize
                } else if summary.isRoot,
                          (sizes[summary.id] ?? 0) == 0,
                          let total = totals[summary.id],
                          let avail = available[summary.id] {
                    sizes[summary.id] = max(total - avail, 0)
                }
            }
            let nodes = order.map { id in
                FlowLinkView.FlowNode(
                    id: id,
                    name: names[id] ?? "Drive",
                    sizeBytes: sizes[id] ?? 0,
                    totalBytes: totals[id],
                    availableBytes: available[id]
                )
            }
            let totalBytes = nodes.reduce(Int64(0)) { $0 + $1.sizeBytes }
            return (nodes, totalBytes)
        }
    }

    private func destinationDriveNodes() -> [FlowLinkView.FlowNode] {
        PerfSignpost.region("destinationDriveNodes") {
            var available: [String: Int64] = [:]
            var totals: [String: Int64] = [:]
            var names: [String: String] = [:]
            var order: [String] = []
            for destination in viewModel.includedDestinationPaths {
                let cached = DriveInfoCache.shared.info(for: destination)
                let summary = cached.summary
                if available[summary.id] == nil {
                    order.append(summary.id)
                    if transferViewModel.isTransferActive(for: viewModel.config.id),
                       let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                        totals[summary.id] = snapshot.totalBytes ?? 0
                        available[summary.id] = snapshot.availableBytes ?? 0
                    } else {
                        totals[summary.id] = cached.totalBytes ?? 0
                        available[summary.id] = cached.liveAvailableBytes ?? 0
                    }
                    names[summary.id] = summary.name
                }
            }
            return order.map { id in
                FlowLinkView.FlowNode(
                    id: id,
                    name: names[id] ?? "Drive",
                    sizeBytes: 0,
                    totalBytes: totals[id],
                    availableBytes: available[id] ?? 0
                )
            }
        }
    }

    private func fulfilledDestinationsForCurrentConfig() -> Set<String> {
        var fulfilled = transferViewModel.verifiedDestinationsByConfig[viewModel.config.id] ?? []
        guard transferViewModel.isTransferActive(for: viewModel.config.id) else { return fulfilled }
        for result in transferViewModel.results where result.success {
            fulfilled.insert(result.destination)
        }
        return fulfilled
    }

    private func storedDriveIds(from fulfilledDestinations: Set<String>) -> Set<String> {
        guard !fulfilledDestinations.isEmpty else { return [] }
        var destinationsByDrive: [String: [String]] = [:]
        for destination in viewModel.destinations {
            let summary = DriveInfoCache.shared.info(for: destination).summary
            destinationsByDrive[summary.id, default: []].append(destination)
        }

        var storedDriveIds = Set<String>()
        for (driveId, destinations) in destinationsByDrive {
            if destinations.allSatisfy({ fulfilledDestinations.contains($0) }) {
                storedDriveIds.insert(driveId)
            }
        }
        return storedDriveIds
    }
}
