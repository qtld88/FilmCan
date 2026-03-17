import SwiftUI
import Foundation

extension BackupEditorView {
    func overviewSection(isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            nameRow
            
            if isWide {
                overviewRowLayout
            } else {
                overviewColumnLayout
            }
        }
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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FilmCanTheme.brandYellow)
                            .frame(width: 8, height: 8)
                        Text("COPY FROM")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        Spacer()
                    }
                ),
                footerView: sourcePreviewFooter
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("sourcePanel")
            
            Color.clear
                .frame(width: 60)
                .anchorPreference(key: DriveAnchorPreferenceKey.self, value: .bounds) { bounds in
                    DriveAnchorData(flowFrame: bounds)
                }
            
            let verifyEnabled = viewModel.rsyncOptions.copyEngine == .custom
                ? viewModel.rsyncOptions.customVerifyEnabled
                : viewModel.rsyncOptions.postVerify

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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FilmCanTheme.brandOrange)
                            .frame(width: 8, height: 8)
                        Text("SAVE TO")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        Spacer()
                    }
                ),
                footerView: nil,
                isTourHighlighted: appState.activeTourTargetId == "destinationPanel",
                requiredBytes: previewInfo.totalBytes,
                organizationPreset: effectiveOrganizationPreset,
                sourcePaths: viewModel.sourcePaths,
                copyFolderContents: viewModel.copyFolderContents,
                configId: viewModel.config.id,
                postVerifyEnabled: verifyEnabled,
                fulfilledDestinations: fulfilledDestinationsForCurrentConfig()
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
                    let storedDriveIds = (transferViewModel.isTransferring
                        && transferViewModel.activeConfigId == viewModel.config.id)
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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FilmCanTheme.brandYellow)
                            .frame(width: 8, height: 8)
                        Text("COPY FROM")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        Spacer()
                    }
                ),
                footerView: sourcePreviewFooter
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
            
            let verifyEnabled = viewModel.rsyncOptions.copyEngine == .custom
                ? viewModel.rsyncOptions.customVerifyEnabled
                : viewModel.rsyncOptions.postVerify

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
                    HStack(spacing: 8) {
                        Circle()
                            .fill(FilmCanTheme.brandOrange)
                            .frame(width: 8, height: 8)
                        Text("SAVE TO")
                            .font(FilmCanFont.label(13))
                            .foregroundColor(FilmCanTheme.textPrimary)
                        Spacer()
                    }
                ),
                footerView: nil,
                isTourHighlighted: appState.activeTourTargetId == "destinationPanel",
                requiredBytes: previewInfo.totalBytes,
                organizationPreset: selectedOrganizationPreset,
                sourcePaths: viewModel.sourcePaths,
                copyFolderContents: viewModel.copyFolderContents,
                configId: viewModel.config.id,
                postVerifyEnabled: verifyEnabled,
                fulfilledDestinations: fulfilledDestinationsForCurrentConfig()
            )
            .frame(maxWidth: .infinity)
            .tourAnchor("destinationPanel")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func refreshPreview() {
        let sources = viewModel.sourcePaths
        previewInfo.isLoading = true

        Task.detached(priority: .utility) {
            let (bytes, files, folders, sizes, itemCounts) = PreviewCalculator.calculateTotalsAndSizes(for: sources)
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
        var sizes: [String: Int64] = [:]
        var names: [String: String] = [:]
        var totals: [String: Int64] = [:]
        var available: [String: Int64] = [:]
        var order: [String] = []
        for source in viewModel.sourcePaths {
            let summary = DriveUtilities.summary(for: source)
            if sizes[summary.id] == nil {
                order.append(summary.id)
                sizes[summary.id] = 0
                names[summary.id] = summary.name
                if transferViewModel.isTransferring,
                   transferViewModel.activeConfigId == viewModel.config.id,
                   let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                    totals[summary.id] = snapshot.totalBytes ?? 0
                    available[summary.id] = snapshot.availableBytes ?? 0
                } else {
                    let capacity = DriveUtilities.capacity(for: source)
                    totals[summary.id] = capacity.total ?? 0
                    available[summary.id] = capacity.available ?? 0
                }
            }
            if summary.isRoot, let total = totals[summary.id], let avail = available[summary.id] {
                sizes[summary.id] = max(total - avail, 0)
            } else {
                sizes[summary.id] = (sizes[summary.id] ?? 0) + (previewInfo.sourceSizes[source] ?? 0)
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

    private func destinationDriveNodes() -> [FlowLinkView.FlowNode] {
        var available: [String: Int64] = [:]
        var totals: [String: Int64] = [:]
        var names: [String: String] = [:]
        var order: [String] = []
        for destination in viewModel.destinations {
            let summary = DriveUtilities.summary(for: destination)
            if available[summary.id] == nil {
                order.append(summary.id)
                if transferViewModel.isTransferring,
                   transferViewModel.activeConfigId == viewModel.config.id,
                   let snapshot = transferViewModel.driveCapacitySnapshot[summary.id] {
                    totals[summary.id] = snapshot.totalBytes ?? 0
                    available[summary.id] = snapshot.availableBytes ?? 0
                } else {
                    let capacity = DriveUtilities.capacity(for: destination)
                    totals[summary.id] = capacity.total ?? 0
                    available[summary.id] = capacity.available ?? 0
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

    private func fulfilledDestinationsForCurrentConfig() -> Set<String> {
        var fulfilled = transferViewModel.verifiedDestinationsByConfig[viewModel.config.id] ?? []
        guard transferViewModel.activeConfigId == viewModel.config.id else { return fulfilled }
        for result in transferViewModel.results where result.success {
            fulfilled.insert(result.destination)
        }
        return fulfilled
    }

    private func storedDriveIds(from fulfilledDestinations: Set<String>) -> Set<String> {
        guard !fulfilledDestinations.isEmpty else { return [] }
        var destinationsByDrive: [String: [String]] = [:]
        for destination in viewModel.destinations {
            let summary = DriveUtilities.summary(for: destination)
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
