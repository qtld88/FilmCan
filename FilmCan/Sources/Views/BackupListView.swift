import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct BackupListView: View {
    @ObservedObject var viewModel: BackupListViewModel
    @ObservedObject var transferViewModel: TransferViewModel
    @ObservedObject var appState: AppState
    var trailingInset: CGFloat = 0
    @ObservedObject private var storage = ConfigurationStorage.shared
    @State private var draggingConfigId: UUID? = nil
    
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(viewModel.filteredConfigurations) { config in
                        let lastEntry = storage.transferHistory.first { $0.configId == config.id }
                        let isActive = transferViewModel.isTransferring
                            && transferViewModel.activeConfigId == config.id
                        MovieTabButton(
                            config: config,
                            lastEntry: lastEntry,
                            isActiveTransfer: isActive,
                            progress: transferViewModel.progress,
                            isSelected: appState.selectedConfigId == config.id,
                            onSelect: {
                                NSApp.keyWindow?.makeFirstResponder(nil)
                                appState.selectConfig(config)
                            },
                            onRun: {
                                Task {
                                    await transferViewModel.startTransfer(config: config)
                                }
                            },
                            onDuplicate: {
                                var newConfig = config
                                newConfig.id = UUID()
                                newConfig.name = config.name + " Copy"
                                newConfig.createdAt = Date()
                                newConfig.lastUsedAt = nil
                                appState.storage.add(newConfig)
                                appState.selectedConfigId = newConfig.id
                            },
                            onDelete: {
                                appState.storage.delete(config)
                                if appState.selectedConfigId == config.id {
                                    appState.selectedConfigId = nil
                                }
                            },
                            onShowLogs: {
                                openLogs(for: config)
                            },
                            onShowSource: {
                                showInFinder(paths: config.sourcePaths)
                            },
                            onShowDestination: {
                                showInFinder(paths: config.destinationPaths)
                            }
                        )
                        .onDrag {
                            draggingConfigId = config.id
                            return NSItemProvider(object: config.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: MovieTabDropDelegate(
                                target: config,
                                storage: storage,
                                draggingConfigId: $draggingConfigId
                            )
                        )
                    }

                    Button(action: {
                        _ = appState.createNewConfig()
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.black)
                    .padding(4)
                    .background(FilmCanTheme.brandYellow)
                    .clipShape(Circle())
                    .help("New movie")
                    .tourAnchor("addBackup")
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .padding(.trailing, trailingInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(FilmCanTheme.sidebar)
    }
}

private struct MovieTabButton: View {
    let config: BackupConfiguration
    let lastEntry: TransferHistoryEntry?
    let isActiveTransfer: Bool
    @ObservedObject var progress: TransferProgress
    let isSelected: Bool
    let onSelect: () -> Void
    let onRun: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onShowLogs: () -> Void
    let onShowSource: () -> Void
    let onShowDestination: () -> Void

    @State private var isHovered = false
    @State private var isEditingTitle = false
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(iconColor)

            if isEditingTitle {
                TextField("Movie name", text: bindingForName)
                    .textFieldStyle(.plain)
                    .font(FilmCanFont.label(12))
                    .foregroundColor(textColor)
                    .focused($isTitleFocused)
                    .lineLimit(1)
                    .onSubmit { finishEditingTitle() }
                    .onChange(of: isTitleFocused) { focused in
                        if !focused { finishEditingTitle() }
                    }
                    .frame(maxWidth: 160, alignment: .leading)
            } else {
                Text(displayName)
                    .font(FilmCanFont.label(12))
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textSelection(.disabled)
                    .frame(maxWidth: 160, alignment: .leading)
            }

            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tabBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(progressOverlay)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            onSelect()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(displayName)
        .contextMenu {
            Button("Rename") { beginEditingTitle() }
            Button("Run Now") { onRun() }
            Button("Duplicate") { onDuplicate() }
            Button("Show Source") { onShowSource() }
            Button("Show Destination") { onShowDestination() }
            Button("Show Logs") { onShowLogs() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var displayName: String {
        let trimmed = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled Movie" : trimmed
    }

    private var bindingForName: Binding<String> {
        Binding(
            get: { config.name },
            set: { newValue in
                var updated = config
                updated.name = newValue
                AppState.shared.storage.update(updated)
            }
        )
    }

    private func beginEditingTitle() {
        isEditingTitle = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isTitleFocused = true
        }
    }

    private func finishEditingTitle() {
        isEditingTitle = false
        isTitleFocused = false
    }

    private var tabBackground: Color {
        if isSelected {
            return FilmCanTheme.panel
        }
        if isHovered {
            return FilmCanTheme.panel.opacity(0.6)
        }
        return FilmCanTheme.panel.opacity(0.35)
    }

    private var borderColor: Color {
        isSelected ? FilmCanTheme.brandYellow : FilmCanTheme.cardStroke
    }

    private var iconColor: Color {
        isSelected ? FilmCanTheme.brandYellow : FilmCanTheme.textSecondary
    }

    private var textColor: Color {
        isSelected ? FilmCanTheme.textPrimary : FilmCanTheme.textSecondary
    }

    private var statusColor: Color? {
        if isActiveTransfer {
            return FilmCanTheme.brandGreen
        }
        guard let lastEntry else { return nil }
        return lastEntry.success ? FilmCanTheme.brandGreen.opacity(0.8) : FilmCanTheme.brandRed
    }

    private var activeTransferProgress: Double {
        isActiveTransfer ? progress.overallProgress : 0
    }

    @ViewBuilder
    private var progressOverlay: some View {
        if isActiveTransfer {
            GeometryReader { geo in
                let clamped = max(0, min(activeTransferProgress, 1))
                Rectangle()
                    .fill(FilmCanTheme.brandGreen)
                    .frame(width: max(6, geo.size.width * clamped), height: 2)
                    .offset(x: 0, y: geo.size.height - 2)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct MovieTabDropDelegate: DropDelegate {
    let target: BackupConfiguration
    let storage: ConfigurationStorage
    @Binding var draggingConfigId: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingConfigId, draggingConfigId != target.id else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            storage.moveConfig(from: draggingConfigId, to: target.id)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingConfigId = nil
        return true
    }
}

private func openLogs(for config: BackupConfiguration) {
    guard config.logEnabled else { return }
    let path: String?
    switch config.logLocation {
    case .custom:
        path = config.customLogPath.isEmpty ? nil : config.customLogPath
    case .sameAsDestination:
        path = config.destinationPaths.first
    }
    guard let folder = path else { return }
    NSWorkspace.shared.open(URL(fileURLWithPath: folder))
}

private func showInFinder(paths: [String]) {
    let urls = paths.compactMap { path -> URL? in
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}
